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

AuditFlow Backend Logs Should Not Contain Correlation Id
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs do NOT
    ...                contain the given correlation id — proving a denied-at-the-edge request
    ...                never reached the backend at all.
    [Arguments]    ${correlation_id}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    Should Not Contain    ${logs}    "correlationId": "${correlation_id}"
    ...    msg=Denied request's correlationId '${correlation_id}' unexpectedly reached the AuditFlow backend.
