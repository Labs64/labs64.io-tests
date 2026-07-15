*** Settings ***
Documentation    AuditFlow authentication-contract regression — P0 blocker for the phantom-JWT
...              defect class.
...
...              The OpenAPI spec advertises bearer-JWT protection on every AuditFlow endpoint.
...              A 200 (or any non-401) response to an unauthenticated request means the
...              phantom-JWT gap between spec and implementation is regressing.
...              All assertions go through the API edge only.
Resource         ../../resources/auditflow.resource
Suite Setup      Create Unauthenticated AuditFlow Session
Suite Teardown   Delete All Sessions

*** Test Cases ***
Events Query Endpoint Rejects Unauthenticated Request With 401
    [Documentation]    GET /events without an Authorization header must return HTTP 401.
    ...                A 200 here means the phantom-JWT gap between the OpenAPI spec
    ...                (bearer-JWT required) and the implementation is actively regressing.
    [Tags]    auditflow    regression    critical    p0-blocker    auth
    ${response}=    Query Events Unauthenticated
    Response Status Should Be    ${response}    401

Events Batch Endpoint Rejects Unauthenticated Ingestion With 401
    [Documentation]    POST /events/batch without an Authorization header must return HTTP 401.
    [Tags]    auditflow    regression    critical    p0-blocker    auth
    ${events}=    Create List
    ${response}=    POST On Session    auditflow    /events/batch    json=${events}    expected_status=any
    Response Status Should Be    ${response}    401

Invalid JWT Credential Is Rejected With 401
    [Documentation]    A request carrying a syntactically valid but cryptographically invalid
    ...                JWT must be rejected with HTTP 401 — not 403 (that would imply the token
    ...                was validated successfully before the authz check).
    [Tags]    auditflow    regression    critical    p0-blocker    auth
    # Deliberately nonsensical test fixture credential — not a real credential or signing key.
    ${bad_headers}=    Create Dictionary
    ...    Authorization=Bearer test-fixture-invalid-jwt
    ...    Accept=application/json
    Create Session    bad-auth    ${AUDITFLOW_BASE_URL}    headers=${bad_headers}    verify=True
    ${response}=    GET On Session    bad-auth    /events    expected_status=any
    Response Status Should Be    ${response}    401
    [Teardown]    Delete All Sessions

Expired JWT Credential Is Rejected With 401
    [Documentation]    A request carrying a JWT whose ``exp`` claim is in the past must be
    ...                rejected with HTTP 401.  An expired credential is not a valid credential.
    [Tags]    auditflow    regression    critical    p0-blocker    auth
    # Test fixture credential: exp=2023-11-14 (safely in the past). Not a real credential.
    ${headers}=    Create Dictionary
    ...    Authorization=Bearer test-fixture-expired-jwt
    ...    Accept=application/json
    Create Session    expired-auth    ${AUDITFLOW_BASE_URL}    headers=${headers}    verify=True
    ${response}=    GET On Session    expired-auth    /events    expected_status=any
    Response Status Should Be    ${response}    401
    [Teardown]    Delete All Sessions

Unauthenticated Request Does Not Return A 500
    [Documentation]    An unauthenticated request must not produce an unexpected server error.
    ...                HTTP 500 on an auth-gated path may indicate a misconfigured auth filter
    ...                that crashes before issuing the proper 401.
    [Tags]    auditflow    regression    auth    error-handling
    ${response}=    Query Events Unauthenticated
    ${status}=    Convert To Integer    ${response.status_code}
    Should Be True    ${status} != 500
    ...    msg=Unauthenticated request caused HTTP 500 — possible misconfigured auth filter. Expected 401.
