*** Settings ***
Documentation    AuditFlow smoke checks — fast critical-path validation via the API edge.
...              These tests run on every PR. AuditFlow's public contract is a single
...              endpoint, POST /audit/publish; there is no query API by design.
Resource         ../../resources/auditflow.resource
Suite Setup      Create AuditFlow Session
Suite Teardown   Delete All Sessions

*** Test Cases ***
Publishing A Valid Event Returns 200 With Event Id Header
    [Documentation]    POSTing a well-formed audit event to /audit/publish must be accepted
    ...                synchronously with HTTP 200 and echo the assigned event id in the
    ...                X-Audit-Event-Id response header.
    [Tags]    auditflow    smoke    critical
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}
    Response Status Should Be    ${response}    200
    Dictionary Should Contain Key    ${response.headers}    X-Audit-Event-Id

Publishing An Event Missing A Required Field Returns 400
    [Documentation]    An audit event missing the required ``eventType`` field must be
    ...                rejected with HTTP 400 and a VALIDATION_ERROR error code.
    [Tags]    auditflow    smoke    error-handling
    ${event}=    Build Invalid Audit Event Missing Required Field
    ${response}=    Publish Audit Event    ${event}
    Response Status Should Be    ${response}    400
    ${body}=    Set Variable    ${response.json()}
    Should Be Equal As Strings    ${body}[code]    VALIDATION_ERROR
