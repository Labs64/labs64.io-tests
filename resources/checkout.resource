*** Settings ***
Documentation    Checkout-specific keywords and variables.
...              See checkout-be/src/main/resources/openapi/openapi-checkout-v1.yaml
...              for the canonical contract.
Library          RequestsLibrary
Library          Collections
Resource         common.resource

*** Variables ***
${CHECKOUT_SESSION_ALIAS}     checkout
${CUSTOMER_READ_SCOPE}        customer:read
${CUSTOMER_WRITE_SCOPE}       customer:write

*** Keywords ***
Create Checkout Session With Scope
    [Documentation]    Open a session authorized with the given scope against the Checkout base URL.
    [Arguments]    ${scope}    ${alias}=${CHECKOUT_SESSION_ALIAS}
    Create Session With Scope    ${alias}    ${CHECKOUT_BASE_URL}    ${scope}

Create Unauthenticated Checkout Session
    [Documentation]    Open an unauthenticated HTTP session pointed at the Checkout base URL.
    [Arguments]    ${alias}=${CHECKOUT_SESSION_ALIAS}
    Create Unauthenticated Session    ${alias}    ${CHECKOUT_BASE_URL}

List Customers
    [Documentation]    GET /customers — requires customer:read scope.
    [Arguments]    ${alias}=${CHECKOUT_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /customers    expected_status=any
    RETURN    ${response}
