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
${PAYMENT_GATEWAY_PROVIDERS_PATH}    /payment-gateway/api/v1/payment-providers

# Local-k8s-only: Payment Gateway's own backend deployment name for kubectl log corroboration
# (see AGENTS.md "Local-only pod-log corroboration"). Shared namespace/authproxy deployment
# vars live in common.resource. Never used unless `Local Kubernetes Available` is true.
${PAYMENT_GATEWAY_K8S_DEPLOYMENT}    %{PAYMENT_GATEWAY_K8S_DEPLOYMENT=labs64io-payment-gateway}

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

Authproxy Logs Should Show No-Token Rejection For Payment Providers
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authproxy Logs Should
    ...                Show No-Token Rejection` fixed to GET /payment-providers.
    [Arguments]    ${since}=90s
    Authproxy Logs Should Show No-Token Rejection    GET    ${PAYMENT_GATEWAY_PROVIDERS_PATH}    ${since}

Authproxy Logs Should Show Authz Decision For Payment Providers
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authproxy Logs Should
    ...                Show Authz Decision` fixed to Payment Gateway's listPaymentProviders
    ...                operation — the anchor op the base (non-k8s) scope-matrix cases already
    ...                use, so the log-corroboration cases mirror them 1:1.
    ...
    ...                Note: unlike AuditFlow, these cases corroborate only the authproxy's edge
    ...                decision, not backend delivery. AuditFlow's request schema carries a
    ...                client-supplied ``correlationId`` that makes a specific event
    ...                unambiguously identifiable in the backend's logs; payment-provider reads
    ...                have no equivalent per-request identifier, so a backend-log check here
    ...                couldn't be reliably attributed to one specific test call. Edge-decision
    ...                corroboration is still the security-relevant half — it proves cerbos itself
    ...                recorded the deny/allow, not just that the HTTP client received it.
    [Arguments]    ${outcome}    ${since}=90s
    Authproxy Logs Should Show Authz Decision    payment-gateway    listPaymentProviders    ${outcome}    ${since}

List Payments
    [Documentation]    GET /payments — requires payment:read scope.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /payments    expected_status=any
    RETURN    ${response}

Create Payment
    [Documentation]    POST /payments — requires payment:write scope.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    # Minimal stub body; authz checks occur before body validation in cerbos.
    ${body}=    Create Dictionary    amount=100    currency=USD
    ${response}=    POST On Session    ${alias}    /payments    json=${body}    expected_status=any
    RETURN    ${response}
