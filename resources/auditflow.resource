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
