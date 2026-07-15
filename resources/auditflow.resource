*** Settings ***
Documentation    AuditFlow-specific keywords and variables.
Library          RequestsLibrary
Library          Collections
Library          String
Resource         common.resource

*** Variables ***
${AUDITFLOW_SESSION_ALIAS}      auditflow
${AUDITFLOW_INGESTION_SETTLE}   5    # seconds to wait for the async ingestion pipeline

*** Keywords ***
Create AuditFlow Session
    [Documentation]    Open an authenticated HTTP session pointed at the AuditFlow base URL.
    Create Authenticated Session    ${AUDITFLOW_SESSION_ALIAS}    ${AUDITFLOW_BASE_URL}

Create Unauthenticated AuditFlow Session
    [Documentation]    Open an unauthenticated HTTP session pointed at the AuditFlow base URL.
    Create Unauthenticated Session    ${AUDITFLOW_SESSION_ALIAS}    ${AUDITFLOW_BASE_URL}

Submit Audit Event Batch
    [Documentation]    POST a list of audit-event objects to the batch ingestion endpoint.
    [Arguments]    ${events}
    ${response}=    POST On Session
    ...    ${AUDITFLOW_SESSION_ALIAS}
    ...    /events/batch
    ...    json=${events}
    ...    expected_status=any
    RETURN    ${response}

Query Events By Correlation ID
    [Documentation]    GET events filtered by the given correlation ID.
    [Arguments]    ${correlation_id}
    ${params}=    Create Dictionary    correlationId=${correlation_id}
    ${response}=    GET On Session
    ...    ${AUDITFLOW_SESSION_ALIAS}
    ...    /events
    ...    params=${params}
    ...    expected_status=any
    RETURN    ${response}

Query Events Unauthenticated
    [Documentation]    GET /events without an Authorization header — expects 401.
    ${response}=    GET On Session
    ...    ${AUDITFLOW_SESSION_ALIAS}
    ...    /events
    ...    expected_status=any
    RETURN    ${response}

Build Event Batch
    [Documentation]    Return a list of ``size`` event dicts sharing ``correlation_id``.
    [Arguments]    ${correlation_id}    ${size}
    ${events}=    Create List
    FOR    ${i}    IN RANGE    ${size}
        ${event}=    Create Dictionary
        ...    correlationId=${correlation_id}
        ...    sequence=${i}
        ...    action=test.event
        ...    actor=test-suite
        Append To List    ${events}    ${event}
    END
    RETURN    ${events}
