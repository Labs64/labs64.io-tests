*** Settings ***
Documentation    AuditFlow smoke checks — fast critical-path validation via the API edge.
...              These tests run on every PR.
Resource         ../../resources/auditflow.resource
Suite Setup      Create AuditFlow Session
Suite Teardown   Delete All Sessions

*** Test Cases ***
Health Endpoint Returns 200
    [Documentation]    The AuditFlow health or readiness endpoint must return HTTP 200,
    ...                confirming the service is reachable and up.
    [Tags]    auditflow    smoke    critical
    ${response}=    GET On Session    auditflow    /health    expected_status=any
    Response Status Should Be    ${response}    200

Events Endpoint Is Reachable With Valid Credentials
    [Documentation]    GET /events with a valid bearer token must return HTTP 200 (or 206),
    ...                confirming the query path is live.
    [Tags]    auditflow    smoke    critical
    ${response}=    GET On Session    auditflow    /events    expected_status=any
    ${status}=    Convert To Integer    ${response.status_code}
    Should Be True    ${status} == 200 or ${status} == 206
    ...    msg=Expected 200 or 206 from /events with valid credentials but got HTTP ${status}

Single Event Ingestion Returns 202
    [Documentation]    POSTing a single well-formed audit event to /events/batch must be
    ...                accepted immediately with HTTP 202.
    [Tags]    auditflow    smoke    critical
    ${correlation_id}=    Generate Correlation ID
    ${events}=    Build Event Batch    ${correlation_id}    1
    ${response}=    Submit Audit Event Batch    ${events}
    Response Status Should Be    ${response}    202
