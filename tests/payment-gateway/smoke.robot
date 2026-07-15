*** Settings ***
Documentation    Payment Gateway smoke checks — critical-path validation via the API edge.
...              Third-party PSP (Stripe/PayPal/Adyen) endpoints are not called in CI;
...              a Karate-style mock or test-mode credentials are used instead.
Library          RequestsLibrary
Library          Collections
Resource         ../../resources/common.resource
Suite Setup      Create Authenticated Session    payment-gateway    ${PAYMENT_GATEWAY_BASE_URL}
Suite Teardown   Delete All Sessions

*** Test Cases ***
Health Endpoint Returns 200
    [Documentation]    The Payment Gateway health endpoint must return HTTP 200.
    [Tags]    payment-gateway    smoke    critical
    ${response}=    GET On Session    payment-gateway    /health    expected_status=any
    Response Status Should Be    ${response}    200

Payment Methods Endpoint Is Reachable
    [Documentation]    GET /payment-methods must return 200 with the list of configured PSP adapters.
    [Tags]    payment-gateway    smoke    critical
    ${response}=    GET On Session    payment-gateway    /payment-methods    expected_status=any
    Response Status Should Be    ${response}    200

Unauthenticated Request Is Rejected With 401
    [Documentation]    Any authenticated endpoint must reject requests without credentials.
    [Tags]    payment-gateway    smoke    auth    critical
    ${headers}=    Create Dictionary    Accept=application/json
    Create Session    pg-no-auth    ${PAYMENT_GATEWAY_BASE_URL}    headers=${headers}    verify=True
    ${response}=    GET On Session    pg-no-auth    /payment-methods    expected_status=any
    Response Status Should Be    ${response}    401
    [Teardown]    Delete All Sessions
