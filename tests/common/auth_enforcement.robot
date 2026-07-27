*** Settings ***
Documentation    GENERATED — do not edit. Regenerate with
...              ``scripts/generate_auth_enforcement_suite.py`` (CI runs it with ``--check``).
...
...              Roadmap item 2: every operation that declares ``x-labs64-auth`` in a module's
...              OpenAPI spec is called at the gateway edge without credentials and must be
...              refused with 401 or 403. The case list is derived from the same annotation
...              that produces the Cerbos policies and the gateway routes, so the contract and
...              what the edge enforces cannot drift apart silently.
...
...              This is the edge half of item 2. Each backend additionally proves it fails
...              closed on its own, in its ``AuthEnforcementContractTest``. Both layers must
...              hold: the edge is where authorization is enforced, the backend is what
...              survives a misrouted request.
...
...              Operations declaring ``public: true`` are deliberately absent — they are
...              covered by each module's functional suite, not here.
Resource         ../../resources/common.resource
Test Teardown    Delete All Sessions

*** Test Cases ***
auditflow POST /audit/publish rejects anonymous callers
    [Documentation]    publishEvent declares x-labs64-auth requiring a tenant and scope(s) audit-event:write. An unauthenticated call must be refused at the edge.
    [Tags]    auditflow    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${AUDITFLOW_BASE_URL}    POST    /audit/publish

payment-gateway GET /payment-providers rejects anonymous callers
    [Documentation]    listPaymentProviders declares x-labs64-auth requiring a tenant and scope(s) payment-provider:read. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    GET    /payment-providers

payment-gateway POST /payment-providers rejects anonymous callers
    [Documentation]    createPaymentProvider declares x-labs64-auth requiring a tenant and scope(s) payment-provider:write. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    POST    /payment-providers

payment-gateway GET /payment-providers/{paymentProviderId} rejects anonymous callers
    [Documentation]    getPaymentProvider declares x-labs64-auth requiring a tenant and scope(s) payment-provider:write. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    GET    /payment-providers/sample

payment-gateway PATCH /payment-providers/{paymentProviderId} rejects anonymous callers
    [Documentation]    updatePaymentProvider declares x-labs64-auth requiring a tenant and scope(s) payment-provider:write. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    PATCH    /payment-providers/sample

payment-gateway DELETE /payment-providers/{paymentProviderId} rejects anonymous callers
    [Documentation]    deletePaymentProvider declares x-labs64-auth requiring a tenant and scope(s) payment-provider:write. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    DELETE    /payment-providers/sample

payment-gateway GET /payments rejects anonymous callers
    [Documentation]    listPayments declares x-labs64-auth requiring a tenant and scope(s) payment:read. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    GET    /payments

payment-gateway POST /payments rejects anonymous callers
    [Documentation]    createPayment declares x-labs64-auth requiring a tenant and scope(s) payment:write. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    POST    /payments

payment-gateway GET /payments/{paymentId} rejects anonymous callers
    [Documentation]    getPayment declares x-labs64-auth requiring a tenant and scope(s) payment:read. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    GET    /payments/sample

payment-gateway POST /payments/{paymentId}/pay rejects anonymous callers
    [Documentation]    payPayment declares x-labs64-auth requiring a tenant and scope(s) payment:pay. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    POST    /payments/sample/pay

payment-gateway POST /payments/{paymentId}/close rejects anonymous callers
    [Documentation]    closePayment declares x-labs64-auth requiring a tenant and scope(s) payment:write. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    POST    /payments/sample/close

payment-gateway GET /payment-transactions rejects anonymous callers
    [Documentation]    listPaymentTransactions declares x-labs64-auth requiring a tenant and scope(s) payment-transaction:read. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    GET    /payment-transactions

payment-gateway GET /payment-transactions/{paymentTransactionId} rejects anonymous callers
    [Documentation]    getPaymentTransaction declares x-labs64-auth requiring a tenant and scope(s) payment-transaction:read. An unauthenticated call must be refused at the edge.
    [Tags]    payment-gateway    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${PAYMENT_GATEWAY_BASE_URL}    GET    /payment-transactions/sample

checkout GET /customers rejects anonymous callers
    [Documentation]    listCustomers declares x-labs64-auth requiring a tenant and scope(s) customer:read. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    GET    /customers

checkout POST /customers rejects anonymous callers
    [Documentation]    createCustomer declares x-labs64-auth requiring a tenant and scope(s) customer:write. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    POST    /customers

checkout GET /customers/{id} rejects anonymous callers
    [Documentation]    getCustomer declares x-labs64-auth requiring a tenant and scope(s) customer:read. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    GET    /customers/00000000-0000-4000-8000-000000000000

checkout PATCH /customers/{id} rejects anonymous callers
    [Documentation]    updateCustomer declares x-labs64-auth requiring a tenant and scope(s) customer:write. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    PATCH    /customers/00000000-0000-4000-8000-000000000000

checkout POST /purchase-orders rejects anonymous callers
    [Documentation]    createPurchaseOrder declares x-labs64-auth requiring a tenant and scope(s) purchase-order:write. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    POST    /purchase-orders

checkout GET /purchase-orders rejects anonymous callers
    [Documentation]    listPurchaseOrders declares x-labs64-auth requiring a tenant and scope(s) purchase-order:read. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    GET    /purchase-orders

checkout GET /purchase-orders/{id} rejects anonymous callers
    [Documentation]    getPurchaseOrder declares x-labs64-auth requiring a tenant and scope(s) purchase-order:read. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    GET    /purchase-orders/00000000-0000-4000-8000-000000000000

checkout PATCH /purchase-orders/{id} rejects anonymous callers
    [Documentation]    updatePurchaseOrder declares x-labs64-auth requiring a tenant and scope(s) purchase-order:write. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    PATCH    /purchase-orders/00000000-0000-4000-8000-000000000000

checkout POST /purchase-orders/{id}/checkout rejects anonymous callers
    [Documentation]    checkoutPurchaseOrder declares x-labs64-auth requiring a tenant and scope(s) purchase-order:checkout. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    POST    /purchase-orders/00000000-0000-4000-8000-000000000000/checkout

checkout GET /checkout-transactions rejects anonymous callers
    [Documentation]    listCheckoutTransactions declares x-labs64-auth requiring a tenant and scope(s) checkout-transaction:read. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    GET    /checkout-transactions

checkout GET /checkout-transactions/{id} rejects anonymous callers
    [Documentation]    getCheckoutTransaction declares x-labs64-auth requiring a tenant and scope(s) checkout-transaction:read. An unauthenticated call must be refused at the edge.
    [Tags]    checkout    regression    auth    auth-enforcement    p0-blocker    generated
    Protected Operation Should Reject Anonymous Access    ${CHECKOUT_BASE_URL}    GET    /checkout-transactions/00000000-0000-4000-8000-000000000000

