*** Settings ***
Documentation    Payment Gateway smoke checks — fast critical-path validation via the API edge.
...              These tests run on every PR. Only the ``noop`` PSP is exercised — real PSP
...              (Stripe/PayPal) sandboxes are never called from this suite.
Resource         ../../resources/payment_gateway.resource
Suite Teardown   Delete All Sessions

*** Test Cases ***
Payment Definitions Are Reachable Without Authentication
    [Documentation]    GET /payment-definitions is a public endpoint and must return 200
    ...                without any credentials.
    [Tags]    payment-gateway    smoke    critical
    Create Unauthenticated Payment Gateway Session    pg-public
    ${response}=    List Payment Definitions    pg-public
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    items

Payment Providers Are Reachable With A Read-Scoped Token
    [Documentation]    GET /payment-providers with a payment-provider:read token must return 200.
    [Tags]    payment-gateway    smoke    critical
    Create Payment Gateway Session With Scope    payment-provider:read    pg-read
    ${response}=    List Payment Providers    pg-read
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    items

Payment Providers Endpoint Rejects Unauthenticated Requests
    [Documentation]    GET /payment-providers without credentials must return 401.
    [Tags]    payment-gateway    smoke    auth    critical
    Create Unauthenticated Payment Gateway Session    pg-no-auth
    ${response}=    List Payment Providers    pg-no-auth
    Response Status Should Be    ${response}    401
