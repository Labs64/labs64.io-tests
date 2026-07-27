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

# Dedicated regression-test tenants (item 12), stamped by mock-oidc personas
# `auditflow-regression` / `auditflow-regression-quota` (never t_mock, which every
# other suite shares) — see overrides/mock-oidc/mock-oidc.yaml and
# overrides/auditflow/values.local.yaml's `t_regression`/`t_regression_quota`.
${AUDITFLOW_REGRESSION_SCOPE}          auditflow-regression
${AUDITFLOW_REGRESSION_QUOTA_SCOPE}    auditflow-regression-quota
${AUDITFLOW_REGRESSION_SESSION}          auditflow-regression
${AUDITFLOW_REGRESSION_QUOTA_SESSION}    auditflow-regression-quota

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

Authproxy Logs Should Show Authz Decision For Publish
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authproxy Logs Should
    ...                Show Authz Decision` fixed to AuditFlow's publishEvent operation.
    [Arguments]    ${outcome}    ${since}=90s
    Authproxy Logs Should Show Authz Decision    auditflow    publishEvent    ${outcome}    ${since}

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

Create Regression Session
    [Documentation]    Open a session for the dedicated t_regression tenant (item 12: pipeline
    ...                routing, condition operators, secretRef resolution). Never t_mock —
    ...                this tenant's pipelines are deliberately failing probes, isolated so
    ...                they cannot affect any other suite.
    Create Session With Scope    ${AUDITFLOW_REGRESSION_SESSION}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_REGRESSION_SCOPE}

Create Regression Quota Session
    [Documentation]    Open a session for the dedicated t_regression_quota tenant (item 12:
    ...                quota enforcement) — provisioned with a tiny rateLimitPerSec/burst so a
    ...                handful of rapid publishes deterministically trips 429.
    Create Session With Scope    ${AUDITFLOW_REGRESSION_QUOTA_SESSION}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_REGRESSION_QUOTA_SCOPE}

Build Probe Audit Event
    [Documentation]    Return an audit-event whose `extra.op`/`extra.value` (and, for the
    ...                match:any pipeline, `extra.op_any`) drive exactly one t_regression probe
    ...                pipeline's condition — see values.local.yaml's `t_regression` pipeline
    ...                comment for the discriminator scheme. Pass ``${EMPTY}`` for ``value`` to
    ...                omit `extra.value` entirely (the exists/notExists negative cases).
    [Arguments]    ${correlation_id}    ${op}    ${value}=${EMPTY}    ${op_any}=${EMPTY}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    Set To Dictionary    ${event}[extra]    op=${op}
    IF    "${value}" != "${EMPTY}"
        Set To Dictionary    ${event}[extra]    value=${value}
    END
    IF    "${op_any}" != "${EMPTY}"
        Set To Dictionary    ${event}[extra]    op_any=${op_any}
    END
    RETURN    ${event}

Get DLQ Message Count
    [Documentation]    GET /actuator/dlq/<tenantId> and return the tenant-scoped, non-destructive
    ...                message count (every message is peeked then nacked back — inspection never
    ...                consumes). Uses the caller's own base session so the request goes through
    ...                the gateway edge, matching every other assertion in this suite.
    [Arguments]    ${alias}    ${tenant_id}
    ${response}=    GET On Session    ${alias}    /actuator/dlq/${tenant_id}    expected_status=200
    RETURN    ${response.json()}[messageCount]

Wait Until DLQ Count At Least
    [Documentation]    Poll GET /actuator/dlq/<tenantId> until messageCount reaches at least
    ...                ``${minimum}``, or fail after ``${timeout}``. Delivery is async (broker +
    ...                retry/backoff before a permanently-failing pipeline reaches the DLQ), so a
    ...                single immediate GET would be racy.
    [Arguments]    ${alias}    ${tenant_id}    ${minimum}    ${timeout}=30s
    Wait Until Keyword Succeeds    ${timeout}    1s
    ...    DLQ Count Should Be At Least    ${alias}    ${tenant_id}    ${minimum}

DLQ Count Should Be At Least
    [Documentation]    Single-attempt helper for `Wait Until DLQ Count At Least`.
    [Arguments]    ${alias}    ${tenant_id}    ${minimum}
    ${count}=    Get DLQ Message Count    ${alias}    ${tenant_id}
    Should Be True    ${count} >= ${minimum}
    ...    msg=Expected DLQ count for tenant '${tenant_id}' to reach at least ${minimum}, got ${count}.
    RETURN    ${count}

Replay DLQ
    [Documentation]    POST /actuator/dlq/<tenantId> (replay). Draining and republishing happens
    ...                synchronously inside this call (each message is forwarded then acked
    ...                before the next `basicGet`), so ``retriedCount`` in the response already
    ...                reflects the full drain by the time this keyword returns — no polling
    ...                needed to observe it.
    [Arguments]    ${alias}    ${tenant_id}
    ${response}=    POST On Session    ${alias}    /actuator/dlq/${tenant_id}    expected_status=200
    RETURN    ${response.json()}

Build Oversized Audit Event
    [Documentation]    Return an audit-event dict with a payload exceeding 2MB to test size limits.
    [Arguments]    ${correlation_id}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    # Create a 15MB string (15,000,000 characters)
    ${large_string}=    Evaluate    'x' * 15000000
    Set To Dictionary    ${event}    oversized_field=${large_string}
    RETURN    ${event}
