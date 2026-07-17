*** Settings ***
Documentation    AuditFlow-specific keywords and variables.
...              AuditFlow's public contract is a single endpoint, ``POST /audit/publish``
...              (see auditflow-api/src/main/resources/openapi/openapi-audit-v1.yaml). AuditFlow
...              is a router, not a system of record — it has no query API of its own, so these
...              tests only ever assert against /audit/publish.
Library          RequestsLibrary
Library          Collections
Library          String
Resource         common.resource

*** Variables ***
${AUDITFLOW_SESSION_ALIAS}    auditflow
${AUDITFLOW_WRITE_SCOPE}      audit-event:write
${AUDITFLOW_GATEWAY_PATH}     /auditflow/api/v1/audit/publish

# Local-k8s-only: AuditFlow's own backend deployment name for kubectl log corroboration (see
# AGENTS.md "Local-only pod-log corroboration"). Shared namespace/authproxy deployment vars
# live in common.resource. Never used unless `Local Kubernetes Available` is true.
${AUDITFLOW_K8S_DEPLOYMENT}      %{AUDITFLOW_K8S_DEPLOYMENT=labs64io-auditflow}

*** Keywords ***
Create AuditFlow Session
    [Documentation]    Open a session authorized with the ``audit-event:write`` scope
    ...                required by POST /audit/publish.
    Create Session With Scope    ${AUDITFLOW_SESSION_ALIAS}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_WRITE_SCOPE}

Create Unauthenticated AuditFlow Session
    [Documentation]    Open an unauthenticated HTTP session pointed at the AuditFlow base URL.
    Create Unauthenticated Session    ${AUDITFLOW_SESSION_ALIAS}    ${AUDITFLOW_BASE_URL}

Publish Audit Event
    [Documentation]    POST an audit-event object to /audit/publish on the given session alias.
    [Arguments]    ${event}    ${alias}=${AUDITFLOW_SESSION_ALIAS}
    ${response}=    POST On Session
    ...    ${alias}
    ...    /audit/publish
    ...    json=${event}
    ...    expected_status=any
    RETURN    ${response}

Build Valid Audit Event
    [Documentation]    Return a well-formed audit-event dict satisfying the AuditEvent schema
    ...                (required: eventType, sourceSystem).
    [Arguments]    ${correlation_id}
    ${extra}=    Create Dictionary    userId=test-suite    action_name=test.event    action_status=SUCCESS
    ${event}=    Create Dictionary
    ...    eventType=api.call
    ...    sourceSystem=labs64.io-tests
    ...    correlationId=${correlation_id}
    ...    extra=${extra}
    RETURN    ${event}

Build Audit Event With Tenant
    [Documentation]    Return a well-formed audit-event dict carrying an explicit client-supplied
    ...                ``tenantId`` — used by tenant-isolation tests to prove the gateway-derived
    ...                tenant is authoritative and the payload value is ignored.
    [Arguments]    ${correlation_id}    ${tenant_id}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    Set To Dictionary    ${event}    tenantId=${tenant_id}
    RETURN    ${event}

Generate Spoof Tenant Id
    [Documentation]    Return a unique, schema-valid tenantId (``spoofed-<hex>``) that no
    ...                environment ever provisions — its uniqueness makes log-absence checks
    ...                attributable to a single test call.
    ${uuid}=    Evaluate    __import__('uuid').uuid4().hex[:12]
    RETURN    spoofed-${uuid}

Build Invalid Audit Event Missing Required Field
    [Documentation]    Return an audit-event dict missing the required ``eventType`` field,
    ...                to assert the API rejects it with HTTP 400.
    ${event}=    Create Dictionary    sourceSystem=labs64.io-tests
    RETURN    ${event}

Authproxy Logs Should Show No-Token Rejection For Publish
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authproxy Logs Should
    ...                Show No-Token Rejection` fixed to POST /audit/publish.
    [Arguments]    ${since}=90s
    Authproxy Logs Should Show No-Token Rejection    POST    ${AUDITFLOW_GATEWAY_PATH}    ${since}

Authproxy Logs Should Show Cedar Decision For Publish
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authproxy Logs Should
    ...                Show Cedar Decision` fixed to AuditFlow's publishEvent operation.
    [Arguments]    ${outcome}    ${since}=90s
    Authproxy Logs Should Show Cedar Decision    auditflow    publishEvent    ${outcome}    ${since}

AuditFlow Backend Logs Should Contain Correlation Id
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs contain the
    ...                given correlation id — proving the event was actually delivered past the
    ...                gateway and processed by the pipeline, not just allowed at the edge.
    ...                Retries briefly: pipeline processing is asynchronous (RabbitMQ) relative
    ...                to the synchronous HTTP 200.
    [Arguments]    ${correlation_id}    ${since}=90s
    Wait Until Keyword Succeeds    10x    500ms
    ...    Pod Logs Should Contain Correlation Id    ${correlation_id}    ${since}

Pod Logs Should Contain Correlation Id
    [Documentation]    Single-attempt helper for `AuditFlow Backend Logs Should Contain
    ...                Correlation Id` — see that keyword for the retry wrapper.
    [Arguments]    ${correlation_id}    ${since}
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    Should Contain    ${logs}    "correlationId": "${correlation_id}"
    ...    msg=Expected correlationId '${correlation_id}' not found in AuditFlow backend logs — event may not have been delivered.

AuditFlow Backend Logs Should Not Mention Tenant
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs never mention
    ...                the given (unique, spoofed) tenantId in any routing/quarantine line —
    ...                proving the gateway-stamped tenant, not the client payload, drove
    ...                gating and routing. Callers must first sync on the same event's
    ...                correlationId so the pipeline has demonstrably already run.
    [Arguments]    ${tenant_id}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    Should Not Contain    ${logs}    '${tenant_id}'
    ...    msg=Spoofed client-supplied tenantId '${tenant_id}' appeared in AuditFlow backend logs — payload tenantId leaked past the authoritative gateway stamping.

AuditFlow Backend Logs Should Not Contain Correlation Id
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs do NOT
    ...                contain the given correlation id — proving a denied-at-the-edge request
    ...                never reached the backend at all.
    [Arguments]    ${correlation_id}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    Should Not Contain    ${logs}    "correlationId": "${correlation_id}"
    ...    msg=Denied request's correlationId '${correlation_id}' unexpectedly reached the AuditFlow backend.

Build Oversized Audit Event
    [Documentation]    Return an audit-event dict with a payload exceeding 2MB to test size limits.
    [Arguments]    ${correlation_id}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    # Create a 15MB string (15,000,000 characters)
    ${large_string}=    Evaluate    'x' * 15000000
    Set To Dictionary    ${event}    oversized_field=${large_string}
    RETURN    ${event}
