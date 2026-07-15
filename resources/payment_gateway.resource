*** Settings ***
Documentation    Payment Gateway-specific keywords and variables.
...              See payment-gateway-be/src/main/resources/openapi/openapi-payment-gateway-v1.yaml
...              for the canonical contract. The ``noop`` provider (always succeeds, no PSP
...              config required) is used for lifecycle tests so no real PSP sandbox is needed.
Library          RequestsLibrary
Library          Collections
Resource         common.resource

*** Variables ***
${PAYMENT_GATEWAY_SESSION_ALIAS}     payment-gateway
${PAYMENT_PROVIDER_READ_SCOPE}       payment-provider:read
${PAYMENT_PROVIDER_WRITE_SCOPE}      payment-provider:write
${NOOP_PROVIDER}                     noop

*** Keywords ***
Create Payment Gateway Session With Scope
    [Documentation]    Open a session authorized with the given scope against the
    ...                Payment Gateway base URL.
    [Arguments]    ${scope}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    Create Session With Scope    ${alias}    ${PAYMENT_GATEWAY_BASE_URL}    ${scope}

Create Unauthenticated Payment Gateway Session
    [Documentation]    Open an unauthenticated HTTP session pointed at the Payment Gateway base URL.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    Create Unauthenticated Session    ${alias}    ${PAYMENT_GATEWAY_BASE_URL}

List Payment Definitions
    [Documentation]    GET /payment-definitions — public, no authentication required.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /payment-definitions    expected_status=any
    RETURN    ${response}

List Payment Providers
    [Documentation]    GET /payment-providers — requires payment-provider:read scope.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /payment-providers    expected_status=any
    RETURN    ${response}

Create Payment Provider
    [Documentation]    POST /payment-providers — requires payment-provider:write scope.
    ...                Defaults to the ``noop`` provider, which needs no PSP config.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}    ${provider}=${NOOP_PROVIDER}    ${active}=${TRUE}
    ${body}=    Create Dictionary    provider=${provider}    active=${active}
    ${response}=    POST On Session    ${alias}    /payment-providers    json=${body}    expected_status=any
    RETURN    ${response}

Get Payment Provider
    [Documentation]    GET /payment-providers/{id} — requires payment-provider:write scope
    ...                (this endpoint exposes PSP configuration).
    [Arguments]    ${payment_provider_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /payment-providers/${payment_provider_id}    expected_status=any
    RETURN    ${response}

Update Payment Provider
    [Documentation]    PATCH /payment-providers/{id} — requires payment-provider:write scope.
    [Arguments]    ${payment_provider_id}    ${updates}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    PATCH On Session    ${alias}    /payment-providers/${payment_provider_id}    json=${updates}    expected_status=any
    RETURN    ${response}

Delete Payment Provider
    [Documentation]    DELETE /payment-providers/{id} — requires payment-provider:write scope.
    [Arguments]    ${payment_provider_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    DELETE On Session    ${alias}    /payment-providers/${payment_provider_id}    expected_status=any
    RETURN    ${response}
