*** Settings ***
Documentation    Payment Gateway authorization scope matrix, asserted at the gateway edge
...              (Traefik authproxy + Cedar). Mirrors the manual scope-matrix validation this
...              suite replaces: listPaymentDefinitions is public; listPaymentProviders needs
...              payment-provider:read; a token missing that scope is denied (403) even though
...              it authenticates successfully.
...
...              The ``local-k8s-only`` tagged cases below additionally corroborate the HTTP
...              assertion against the authproxy's Cedar decision log (kubectl) for the
...              listPaymentProviders operation — a deliberate, narrow exception to this suite's
...              normal "no kubectl" rule. They call `Skip Unless Local Kubernetes` first and
...              skip cleanly outside the local k3d dev cluster, so CI never fails on them. See
...              AGENTS.md "Local-only pod-log corroboration" for the full rationale/scope, and
...              `resources/payment_gateway.resource` for why these mirror auditflow's edge
...              corroboration but not its backend-delivery corroboration.
Resource         ../../resources/payment_gateway.resource
Test Teardown    Delete All Sessions

*** Test Cases ***
Payment Definitions Is Public And Ignores Any Credential State
    [Documentation]    GET /payment-definitions must succeed identically whether the caller is
    ...                unauthenticated or holds an unrelated scope — it is a public route.
    [Tags]    payment-gateway    regression    auth
    Create Unauthenticated Payment Gateway Session    pg-authz-public
    ${response}=    List Payment Definitions    pg-authz-public
    Response Status Should Be    ${response}    200

Payment Definitions Stays Public For A Token Holding An Unrelated Scope
    [Documentation]    GET /payment-definitions must return 200 even when the caller presents a
    ...                validly-signed token for a completely unrelated scope — a public route
    ...                must never accidentally start gating on whatever credential happens to be
    ...                attached, only unauthenticated access proves that in isolation.
    [Tags]    payment-gateway    regression    auth
    Create Payment Gateway Session With Scope    payment-provider:write    pg-authz-public-with-token
    ${response}=    List Payment Definitions    pg-authz-public-with-token
    Response Status Should Be    ${response}    200

Payment Providers Endpoint Rejects Requests With No Authorization Header
    [Documentation]    GET /payment-providers without an Authorization header at all must return
    ...                401. Distinct from the malformed-bearer case below (which proves a
    ...                present-but-invalid credential is also rejected); this is the plain
    ...                missing-credential case and belongs in the canonical matrix here, not only
    ...                in smoke.robot's fast reachability check.
    [Tags]    payment-gateway    regression    critical    auth
    Create Unauthenticated Payment Gateway Session    pg-authz-no-auth
    ${response}=    List Payment Providers    pg-authz-no-auth
    Response Status Should Be    ${response}    401

Payment Providers Denies A Malformed Bearer Credential With 401
    [Documentation]    A syntactically-invalid bearer credential on a protected route must be
    ...                rejected with 401 — not 403, which would imply the token was accepted
    ...                before the Cedar authorization check ran. Mirrors the auditflow matrix so
    ...                the two modules assert the same authentication-vs-authorization boundary.
    [Tags]    payment-gateway    regression    critical    auth
    # Deliberately nonsensical test fixture credential — not a real credential or signing key.
    ${headers}=    Create Dictionary
    ...    Authorization=Bearer test-fixture-malformed-jwt
    ...    Accept=application/json
    ...    Content-Type=application/json
    Create Session    pg-bad-auth    ${PAYMENT_GATEWAY_BASE_URL}    headers=${headers}    verify=True
    ${response}=    List Payment Providers    pg-bad-auth
    Response Status Should Be    ${response}    401

Payment Providers Denies A Token Missing The Read Scope
    [Documentation]    A valid, correctly-signed token that does not carry payment-provider:read
    ...                (here: only payment-provider:write) must be denied with 403 — holding a
    ...                different scope for the same resource does not imply read access.
    [Tags]    payment-gateway    regression    critical    auth    tenant-isolation
    Create Payment Gateway Session With Scope    payment-provider:write    pg-authz-wrong-scope
    ${response}=    List Payment Providers    pg-authz-wrong-scope
    Response Status Should Be    ${response}    403

Payment Providers Allows A Token With The Read Scope
    [Documentation]    A token carrying exactly payment-provider:read must be allowed through
    ...                the Cedar policy for GET /payment-providers.
    [Tags]    payment-gateway    regression    critical    auth
    Create Payment Gateway Session With Scope    payment-provider:read    pg-authz-correct-scope
    ${response}=    List Payment Providers    pg-authz-correct-scope
    Response Status Should Be    ${response}    200

Creating A Payment Provider Denies A Read-Only Scope
    [Documentation]    POST /payment-providers requires payment-provider:write; a token
    ...                carrying only payment-provider:read must be denied with 403.
    [Tags]    payment-gateway    regression    critical    auth    tenant-isolation
    Create Payment Gateway Session With Scope    payment-provider:read    pg-authz-create-denied
    ${response}=    Create Payment Provider    pg-authz-create-denied
    Response Status Should Be    ${response}    403

Getting A Payment Provider By Id Denies A Read-Only Scope
    [Documentation]    Same-resource read/write asymmetry: GET /payment-providers (list) needs
    ...                only payment-provider:read, but GET /payment-providers/{id} needs
    ...                payment-provider:write because the detail view exposes PSP configuration
    ...                (secrets). A read-scoped token that can list providers must therefore be
    ...                denied 403 on the detail endpoint — regressing this into a read grant
    ...                would leak PSP config. The 403 is decided at the edge before the id is
    ...                resolved, so a sentinel non-existent id still yields 403 (not 404).
    [Tags]    payment-gateway    regression    critical    auth    tenant-isolation
    Create Payment Gateway Session With Scope    payment-provider:read    pg-authz-detail-denied
    ${response}=    Get Payment Provider    00000000-0000-0000-0000-000000000000    pg-authz-detail-denied
    Response Status Should Be    ${response}    403

Payment Providers Endpoint Rejects A Token With No Scopes
    [Documentation]    A token authenticated via mock-oidc's no-access persona (valid signature,
    ...                no scopes) must be denied with 403, not silently granted default access.
    [Tags]    payment-gateway    regression    critical    auth
    Create Payment Gateway Session With Scope    no-access    pg-authz-no-scopes
    ${response}=    List Payment Providers    pg-authz-no-scopes
    Response Status Should Be    ${response}    403

Authproxy Logs Confirm Unauthenticated Payment Providers Request Was Rejected At The Edge
    [Documentation]    Local-k8s-only companion to "Payment Providers Endpoint Rejects Requests
    ...                With No Authorization Header": corroborates the HTTP 401 against the
    ...                authproxy's own no-token rejection log line, not just the response code.
    [Tags]    payment-gateway    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Unauthenticated Payment Gateway Session    pg-authz-no-auth-k8s
    ${response}=    List Payment Providers    pg-authz-no-auth-k8s
    Response Status Should Be    ${response}    401
    Authproxy Logs Should Show No-Token Rejection For Payment Providers

Authproxy Logs Confirm Wrong-Scope Payment Providers Request Was Denied At The Edge
    [Documentation]    Local-k8s-only companion to "Payment Providers Denies A Token Missing The
    ...                Read Scope": corroborates the HTTP 403 against the authproxy's Cedar
    ...                enforced-deny decision log for listPaymentProviders.
    [Tags]    payment-gateway    regression    auth    tenant-isolation    local-k8s-only
    Skip Unless Local Kubernetes
    Create Payment Gateway Session With Scope    payment-provider:write    pg-authz-wrong-scope-k8s
    ${response}=    List Payment Providers    pg-authz-wrong-scope-k8s
    Response Status Should Be    ${response}    403
    Authproxy Logs Should Show Cedar Decision For Payment Providers    enforced-deny

Authproxy Logs Confirm Correct-Scope Payment Providers Request Was Allowed At The Edge
    [Documentation]    Local-k8s-only companion to "Payment Providers Allows A Token With The
    ...                Read Scope": corroborates the HTTP 200 against the authproxy's Cedar
    ...                enforced-allow decision log for listPaymentProviders.
    [Tags]    payment-gateway    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Payment Gateway Session With Scope    payment-provider:read    pg-authz-correct-scope-k8s
    ${response}=    List Payment Providers    pg-authz-correct-scope-k8s
    Response Status Should Be    ${response}    200
    Authproxy Logs Should Show Cedar Decision For Payment Providers    enforced-allow

Authproxy Logs Confirm No-Scope Payment Providers Request Was Denied At The Edge
    [Documentation]    Local-k8s-only companion to "Payment Providers Endpoint Rejects A Token
    ...                With No Scopes": corroborates the HTTP 403 against the authproxy's Cedar
    ...                enforced-deny decision log for listPaymentProviders.
    [Tags]    payment-gateway    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Payment Gateway Session With Scope    no-access    pg-authz-no-scopes-k8s
    ${response}=    List Payment Providers    pg-authz-no-scopes-k8s
    Response Status Should Be    ${response}    403
    Authproxy Logs Should Show Cedar Decision For Payment Providers    enforced-deny
