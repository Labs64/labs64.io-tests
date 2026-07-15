*** Settings ***
Documentation    IAM Gateway smoke checks — critical-path authentication and authorisation
...              validation via the API edge only.
Library          RequestsLibrary
Library          Collections
Resource         ../../resources/common.resource
Suite Setup      Create Authenticated Session    iam-gateway    ${IAM_GATEWAY_BASE_URL}
Suite Teardown   Delete All Sessions

*** Test Cases ***
Health Endpoint Returns 200
    [Documentation]    The IAM Gateway health endpoint must return HTTP 200.
    [Tags]    iam-gateway    smoke    critical
    ${response}=    GET On Session    iam-gateway    /health    expected_status=any
    Response Status Should Be    ${response}    200

Token Introspection Endpoint Is Reachable
    [Documentation]    POST /introspect with a valid token must return 200 and an ``active`` field.
    [Tags]    iam-gateway    smoke    critical
    ${body}=    Create Dictionary    token=${API_TOKEN}
    ${response}=    POST On Session    iam-gateway    /introspect    json=${body}    expected_status=any
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    active

Unauthenticated Introspection Is Rejected With 401
    [Documentation]    The /introspect endpoint must reject unauthenticated requests with HTTP 401.
    [Tags]    iam-gateway    smoke    auth    critical
    ${headers}=    Create Dictionary    Accept=application/json
    Create Session    iam-no-auth    ${IAM_GATEWAY_BASE_URL}    headers=${headers}    verify=True
    ${body}=    Create Dictionary    token=some-token
    ${response}=    POST On Session    iam-no-auth    /introspect    json=${body}    expected_status=any
    Response Status Should Be    ${response}    401
    [Teardown]    Delete All Sessions

Cross Tenant Token Is Rejected
    [Documentation]    Attempting to use a token issued for Tenant A when calling as Tenant B
    ...                must be rejected — cross-tenant token reuse must not be permitted.
    [Tags]    iam-gateway    smoke    tenant-isolation    critical
    ${body}=    Create Dictionary    token=cross-tenant-fixture-token
    ${response}=    POST On Session    iam-gateway    /introspect    json=${body}    expected_status=any
    ${status}=    Convert To Integer    ${response.status_code}
    Should Be True    ${status} == 401 or ${status} == 403
    ...    msg=Cross-tenant token reuse must be rejected (401 or 403) but got HTTP ${status}
