*** Settings ***
Documentation    Checkout smoke checks — fast critical-path validation via the API edge.
Resource         ../../resources/checkout.resource
Suite Teardown   Delete All Sessions

*** Test Cases ***
Allow read-scoped access to customers (200)
    [Documentation]    GET /customers with customer:read token returns 200.
    [Tags]    checkout    smoke    critical
    Create Checkout Session With Scope    customer:read    checkout-read
    ${response}=    List Customers    checkout-read
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    items
