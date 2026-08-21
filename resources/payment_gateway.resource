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
${IDEMPOTENCY_KEY_HEADER}             Idempotency-Key

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

Get Payment
    [Documentation]    GET /payments/{id} — requires payment:read scope.
    [Arguments]    ${payment_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /payments/${payment_id}    expected_status=any
    RETURN    ${response}

Create Payment
    [Documentation]    POST /payments — requires payment:write scope.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    # Minimal stub body; authz checks occur before body validation in cerbos.
    ${body}=    Create Dictionary    amount=100    currency=USD
    ${response}=    POST On Session    ${alias}    /payments    json=${body}    expected_status=any
    RETURN    ${response}

Pay Payment
    [Documentation]    POST /payments/{id}/pay — requires payment:pay scope.
    [Arguments]    ${payment_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}    ${idempotency_key}=${EMPTY}
    ${headers}=    Create Dictionary
    IF    $idempotency_key
        Set To Dictionary    ${headers}    ${IDEMPOTENCY_KEY_HEADER}=${idempotency_key}
    END
    ${response}=    POST On Session    ${alias}    /payments/${payment_id}/pay    headers=${headers}    expected_status=any
    RETURN    ${response}

List Payment Transactions
    [Documentation]    GET /payment-transactions filtered by payment id — requires payment-transaction:read scope.
    [Arguments]    ${payment_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${params}=    Create Dictionary    paymentId=${payment_id}
    ${response}=    GET On Session    ${alias}    /payment-transactions    params=${params}    expected_status=any
    RETURN    ${response}

Get Payment Transaction
    [Documentation]    GET /payment-transactions/{id} — requires payment-transaction:read scope.
    [Arguments]    ${payment_transaction_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${response}=    GET On Session    ${alias}    /payment-transactions/${payment_transaction_id}    expected_status=any
    RETURN    ${response}

Ensure Active Noop Payment Provider
    [Documentation]    Return an active noop provider for the session tenant. Reuse an existing
    ...                active provider or create one without modifying inactive tenant fixtures.
    ...                The session must carry payment-provider:read and payment-provider:write.
    [Arguments]    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${list_response}=    List Payment Providers    ${alias}
    Response Status Should Be    ${list_response}    200
    ${providers}=    Get From Dictionary    ${list_response.json()}    items
    FOR    ${provider}    IN    @{providers}
        ${is_active_noop}=    Evaluate    $provider.get("provider") == "noop" and $provider.get("active") is True
        IF    ${is_active_noop}
            RETURN    ${provider}[id]
        END
    END
    ${create_response}=    Create Payment Provider    ${alias}
    Response Status Should Be    ${create_response}    200
    RETURN    ${create_response.json()}[id]

Build Valid Payment Request
    [Documentation]    Build the smallest valid CreatePaymentRequest defined by the PG OpenAPI contract.
    [Arguments]    ${payment_provider_id}
    ${item}=    Create Dictionary
    ...    name=Payment Gateway E2E item
    ...    price=${100}
    ...    quantity=${1}
    ${items}=    Create List    ${item}
    ${purchase_order}=    Create Dictionary
    ...    currency=EUR
    ...    items=${items}
    ...    grossAmount=${100}
    ${billing_info}=    Create Dictionary    email=payment-gateway-e2e@labs64.io
    ${request}=    Create Dictionary
    ...    paymentProviderId=${payment_provider_id}
    ...    purchaseOrder=${purchase_order}
    ...    billingInfo=${billing_info}
    RETURN    ${request}

Create Valid Payment
    [Documentation]    POST the smallest valid payment request defined by the PG OpenAPI contract.
    [Arguments]    ${payment_provider_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${body}=    Build Valid Payment Request    ${payment_provider_id}
    ${response}=    POST On Session    ${alias}    /payments    json=${body}    expected_status=any
    RETURN    ${response}

Create Payment With Correlation Id
    [Documentation]    POST a valid payment request with a caller-controlled correlation ID.
    [Arguments]    ${payment_provider_id}    ${correlation_id}    ${alias}=${PAYMENT_GATEWAY_SESSION_ALIAS}
    ${body}=    Build Valid Payment Request    ${payment_provider_id}
    ${headers}=    Create Dictionary    ${CORRELATION_ID_HEADER}=${correlation_id}
    ${response}=    POST On Session
    ...    ${alias}
    ...    /payments
    ...    json=${body}
    ...    headers=${headers}
    ...    expected_status=any
    RETURN    ${response}
