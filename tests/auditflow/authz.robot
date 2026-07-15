*** Settings ***
Documentation    AuditFlow authentication & authorization regression, asserted entirely at the
...              gateway edge (Traefik authproxy + Cedar). Mirrors the manual scope-matrix
...              validation this suite replaces: a token with the wrong scope must be denied
...              (403), the correct scope must be allowed (200), and missing/malformed
...              credentials must be rejected (401) before any Cedar decision is made.
...
...              The ``local-k8s-only`` tagged cases below additionally corroborate the HTTP
...              assertion against kubectl pod logs (authproxy Cedar decision + AuditFlow
...              backend delivery) — a deliberate, narrow exception to this suite's normal
...              "no kubectl" rule. They call `Skip Unless Local Kubernetes` first and skip
...              cleanly outside the local k3d dev cluster, so CI never fails on them. See
...              AGENTS.md "Local-only pod-log corroboration" for the full rationale/scope.
Resource         ../../resources/auditflow.resource
Test Teardown    Delete All Sessions

*** Test Cases ***
Publish Without Authorization Header Returns 401
    [Documentation]    POST /audit/publish without an Authorization header must return 401 —
    ...                the phantom-JWT gap between the OpenAPI spec (bearer-JWT required) and
    ...                the implementation must never regress.
    [Tags]    auditflow    regression    critical    p0-blocker    auth
    Create Unauthenticated AuditFlow Session
    ${event}=    Build Valid Audit Event    unauth-check
    ${response}=    Publish Audit Event    ${event}
    Response Status Should Be    ${response}    401

Publish With Malformed Bearer Credential Returns 401
    [Documentation]    A syntactically-invalid bearer credential must be rejected with 401 —
    ...                not 403, which would imply the token was accepted before the
    ...                authorization check ran.
    [Tags]    auditflow    regression    critical    p0-blocker    auth
    # Deliberately nonsensical test fixture credential — not a real credential or signing key.
    ${headers}=    Create Dictionary
    ...    Authorization=Bearer test-fixture-malformed-jwt
    ...    Accept=application/json
    ...    Content-Type=application/json
    Create Session    auditflow-bad-auth    ${AUDITFLOW_BASE_URL}    headers=${headers}    verify=True
    ${event}=    Build Valid Audit Event    malformed-check
    ${response}=    POST On Session    auditflow-bad-auth    /audit/publish    json=${event}    expected_status=any
    Response Status Should Be    ${response}    401

Publish With Wrong Scope Is Denied With 403
    [Documentation]    A valid, correctly-signed token that carries a scope other than
    ...                audit-event:write (here: audit-event:read) must be denied by the Cedar
    ...                policy with 403 — a valid credential is not the same as an authorized one.
    [Tags]    auditflow    regression    critical    auth    tenant-isolation
    Create Session With Scope    auditflow-wrong-scope    ${AUDITFLOW_BASE_URL}    audit-event:read
    ${event}=    Build Valid Audit Event    wrong-scope-check
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-wrong-scope
    Response Status Should Be    ${response}    403

Publish With Correct Scope Is Allowed
    [Documentation]    A token carrying exactly the required audit-event:write scope must be
    ...                allowed through the Cedar policy and reach the backend.
    [Tags]    auditflow    regression    critical    auth
    Create Session With Scope    auditflow-correct-scope    ${AUDITFLOW_BASE_URL}    audit-event:write
    ${event}=    Build Valid Audit Event    correct-scope-check
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-correct-scope
    Response Status Should Be    ${response}    200

Publish With Multiple Scopes Including The Required One Is Allowed
    [Documentation]    A token carrying several scopes — one of which is the required
    ...                audit-event:write, the rest irrelevant — must still be allowed. The
    ...                Cedar edge policy uses OR/contains semantics over the scope set
    ...                (context.scopes.contains(...)); an unrelated extra scope riding along
    ...                must never cause a false deny.
    [Tags]    auditflow    regression    critical    auth
    Create Session With Scope    auditflow-multi-scope    ${AUDITFLOW_BASE_URL}
    ...    audit-event:read audit-event:write customer:read
    ${event}=    Build Valid Audit Event    multi-scope-check
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-multi-scope
    Response Status Should Be    ${response}    200

Publish With Valid Token Lacking Any Scope Is Denied With 403
    [Documentation]    A validly-signed token that carries NO scopes at all (mock-oidc
    ...                ``no-access`` persona) must be denied by the Cedar policy with 403 —
    ...                distinct from "wrong scope": here the token authenticates fine but the
    ...                scope set is empty, so ``context.scopes.contains(...)`` has nothing to
    ...                match. Migrated from labs64.io-helm-charts justfile `e2e-auth-test`.
    [Tags]    auditflow    regression    critical    auth
    Create Session With Scope    auditflow-no-scope    ${AUDITFLOW_BASE_URL}    no-access
    ${event}=    Build Valid Audit Event    no-scope-check
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-no-scope
    Response Status Should Be    ${response}    403

Unauthenticated Request Does Not Return A 500
    [Documentation]    An unauthenticated request must not produce an unexpected server error.
    ...                HTTP 500 on an auth-gated path may indicate a misconfigured auth filter
    ...                that crashes before issuing the proper 401.
    [Tags]    auditflow    regression    auth    error-handling
    Create Unauthenticated AuditFlow Session
    ${event}=    Build Valid Audit Event    no-500-check
    ${response}=    Publish Audit Event    ${event}
    ${status}=    Convert To Integer    ${response.status_code}
    Should Be True    ${status} != 500
    ...    msg=Unauthenticated request caused HTTP 500 — possible misconfigured auth filter. Expected 401.

Authproxy Logs Confirm Unauthenticated Publish Was Rejected At The Edge
    [Documentation]    Local-k8s-only companion to "Publish Without Authorization Header
    ...                Returns 401": corroborates the HTTP 401 against the authproxy's own
    ...                no-token rejection log line, not just the response code.
    [Tags]    auditflow    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Unauthenticated AuditFlow Session
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}
    Response Status Should Be    ${response}    401
    Authproxy Logs Should Show No-Token Rejection For Publish

Authproxy And Backend Logs Confirm Wrong-Scope Publish Was Denied At The Edge
    [Documentation]    Local-k8s-only companion to "Publish With Wrong Scope Is Denied With
    ...                403": corroborates the HTTP 403 against the authproxy's Cedar
    ...                enforced-deny decision log, and confirms the denied request's
    ...                correlationId never reached the AuditFlow backend at all.
    [Tags]    auditflow    regression    auth    tenant-isolation    local-k8s-only
    Skip Unless Local Kubernetes
    Create Session With Scope    auditflow-wrong-scope-k8s    ${AUDITFLOW_BASE_URL}    audit-event:read
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-wrong-scope-k8s
    Response Status Should Be    ${response}    403
    Authproxy Logs Should Show Cedar Decision For Publish    enforced-deny
    AuditFlow Backend Logs Should Not Contain Correlation Id    ${correlation_id}

Authproxy And Backend Logs Confirm Correct-Scope Publish Was Allowed And Delivered
    [Documentation]    Local-k8s-only companion to "Publish With Correct Scope Is Allowed":
    ...                corroborates the HTTP 200 against the authproxy's Cedar enforced-allow
    ...                decision log, and confirms the event's correlationId actually reached
    ...                and was processed by the AuditFlow backend — not just allowed at the edge.
    [Tags]    auditflow    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Session With Scope    auditflow-correct-scope-k8s    ${AUDITFLOW_BASE_URL}    audit-event:write
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-correct-scope-k8s
    Response Status Should Be    ${response}    200
    Authproxy Logs Should Show Cedar Decision For Publish    enforced-allow
    AuditFlow Backend Logs Should Contain Correlation Id    ${correlation_id}

Authproxy And Backend Logs Confirm Multiple-Scopes Publish Was Allowed And Delivered
    [Documentation]    Local-k8s-only companion to "Publish With Multiple Scopes Including The
    ...                Required One Is Allowed": corroborates the HTTP 200 against the
    ...                authproxy's Cedar enforced-allow decision log (showing the full scope
    ...                set, not just the required one), and confirms delivery to the backend.
    [Tags]    auditflow    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Session With Scope    auditflow-multi-scope-k8s    ${AUDITFLOW_BASE_URL}
    ...    audit-event:read audit-event:write customer:read
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-multi-scope-k8s
    Response Status Should Be    ${response}    200
    Authproxy Logs Should Show Cedar Decision For Publish    enforced-allow
    AuditFlow Backend Logs Should Contain Correlation Id    ${correlation_id}

Authproxy And Backend Logs Confirm No-Scope Publish Was Denied At The Edge
    [Documentation]    Local-k8s-only companion to "Publish With Valid Token Lacking Any Scope
    ...                Is Denied With 403": corroborates the HTTP 403 against the authproxy's
    ...                Cedar enforced-deny decision log, and confirms the denied request's
    ...                correlationId never reached the AuditFlow backend at all.
    [Tags]    auditflow    regression    auth    local-k8s-only
    Skip Unless Local Kubernetes
    Create Session With Scope    auditflow-no-scope-k8s    ${AUDITFLOW_BASE_URL}    no-access
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}    alias=auditflow-no-scope-k8s
    Response Status Should Be    ${response}    403
    Authproxy Logs Should Show Cedar Decision For Publish    enforced-deny
    AuditFlow Backend Logs Should Not Contain Correlation Id    ${correlation_id}
