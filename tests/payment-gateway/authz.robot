*** Settings ***
Documentation    Payment Gateway authorization scope matrix, asserted at the gateway edge
...              (Traefik authproxy + Cedar). Mirrors the manual scope-matrix validation this
...              suite replaces: listPaymentDefinitions is public; listPaymentProviders needs
...              payment-provider:read; a token missing that scope is denied (403) even though
...              it authenticates successfully.
Resource         ../../resources/payment_gateway.resource
Suite Teardown   Delete All Sessions

*** Test Cases ***
Payment Definitions Is Public And Ignores Any Credential State
    [Documentation]    GET /payment-definitions must succeed identically whether the caller is
    ...                unauthenticated or holds an unrelated scope — it is a public route.
    [Tags]    payment-gateway    regression    auth
    Create Unauthenticated Payment Gateway Session    pg-authz-public
    ${response}=    List Payment Definitions    pg-authz-public
    Response Status Should Be    ${response}    200
    [Teardown]    Delete All Sessions

Payment Providers Denies A Token Missing The Read Scope
    [Documentation]    A valid, correctly-signed token that does not carry payment-provider:read
    ...                (here: only payment-provider:write) must be denied with 403 — holding a
    ...                different scope for the same resource does not imply read access.
    [Tags]    payment-gateway    regression    critical    auth    tenant-isolation
    Create Payment Gateway Session With Scope    payment-provider:write    pg-authz-wrong-scope
    ${response}=    List Payment Providers    pg-authz-wrong-scope
    Response Status Should Be    ${response}    403
    [Teardown]    Delete All Sessions

Payment Providers Allows A Token With The Read Scope
    [Documentation]    A token carrying exactly payment-provider:read must be allowed through
    ...                the Cedar policy for GET /payment-providers.
    [Tags]    payment-gateway    regression    critical    auth
    Create Payment Gateway Session With Scope    payment-provider:read    pg-authz-correct-scope
    ${response}=    List Payment Providers    pg-authz-correct-scope
    Response Status Should Be    ${response}    200
    [Teardown]    Delete All Sessions

Creating A Payment Provider Denies A Read-Only Scope
    [Documentation]    POST /payment-providers requires payment-provider:write; a token
    ...                carrying only payment-provider:read must be denied with 403.
    [Tags]    payment-gateway    regression    critical    auth    tenant-isolation
    Create Payment Gateway Session With Scope    payment-provider:read    pg-authz-create-denied
    ${response}=    Create Payment Provider    pg-authz-create-denied
    Response Status Should Be    ${response}    403
    [Teardown]    Delete All Sessions

Payment Providers Endpoint Rejects A Token With No Scopes
    [Documentation]    A token authenticated via mock-oidc's no-access persona (valid signature,
    ...                no scopes) must be denied with 403, not silently granted default access.
    [Tags]    payment-gateway    regression    critical    auth
    Create Payment Gateway Session With Scope    no-access    pg-authz-no-scopes
    ${response}=    List Payment Providers    pg-authz-no-scopes
    Response Status Should Be    ${response}    403
    [Teardown]    Delete All Sessions
