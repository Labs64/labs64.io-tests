*** Settings ***
Documentation    Tenant isolation at the gateway edge for the AuditFlow tenant model
...              (silo routing, ingest gate, authoritative tenant stamping).
...
...              The gateway-derived tenant (token ``tenant`` claim → ``X-Auth-Tenant``) is
...              authoritative: a client-supplied ``tenantId`` in the payload must NEVER
...              influence which tenant an event is stamped, gated, or routed as. The local
...              mock-oidc provider mints every token with the same fixed ``tenant: t_mock``
...              claim (no second-tenant persona exists yet), so a literal two-tenant matrix
...              cannot be minted here; these cases instead prove the two facts that ARE
...              observable at the edge: (1) a spoofed body tenantId changes nothing, and
...              (2) when the ingest gate rejects, it does so with the contract's 403
...              ``TENANT_NOT_PROVISIONED`` shape, never a 5xx.
...
...              TODO(mock-oidc): add a second-tenant persona (different ``tenant`` claim) to
...              overrides/mock-oidc/mock-oidc.yaml in labs64.io-helm-charts; then extend this
...              suite with a true cross-tenant deny case.
Resource         ../../resources/auditflow.resource
Test Teardown    Delete All Sessions

*** Test Cases ***
Client-Supplied TenantId Cannot Change The Publish Outcome
    [Documentation]    Two publishes on the same write-scope token — one without a body
    ...                tenantId, one spoofing a unique never-provisioned tenantId — must yield
    ...                the SAME status. The gateway stamps the token's tenant over the payload
    ...                before gating, so a spoofed tenantId can neither unlock another tenant's
    ...                pipelines (no sudden 200) nor smuggle the event into an unprovisioned
    ...                tenant (no sudden 403). Environment-agnostic: passes whether or not the
    ...                stamped t_mock tenant is provisioned, because both requests are judged
    ...                as the SAME tenant either way.
    [Tags]    auditflow    regression    critical    auth    tenant-isolation
    Create AuditFlow Session
    ${control_id}=    Generate Correlation ID
    ${control_event}=    Build Valid Audit Event    ${control_id}
    ${control}=    Publish Audit Event    ${control_event}
    ${spoof_tenant}=    Generate Spoof Tenant Id
    ${spoof_id}=    Generate Correlation ID
    ${spoof_event}=    Build Audit Event With Tenant    ${spoof_id}    ${spoof_tenant}
    ${spoofed}=    Publish Audit Event    ${spoof_event}
    Should Be Equal As Integers    ${control.status_code}    ${spoofed.status_code}
    ...    msg=Spoofed body tenantId changed the publish outcome (${control.status_code} vs ${spoofed.status_code}) — client-supplied tenantId must never override the gateway tenant.
    Should Be True    ${control.status_code} in (200, 403)
    ...    msg=Publish returned unexpected status ${control.status_code} (body: ${control.text}).

Ingest Gate Rejection Uses The Contract Error Shape
    [Documentation]    Wherever the AuditFlow tenant model is active and the token's tenant is
    ...                not provisioned, the ingest gate must reject with HTTP 403 and the
    ...                OpenAPI ``TENANT_NOT_PROVISIONED`` error code — never a 5xx, and never a
    ...                silent 200 into a black hole. Where the tenant model is not yet deployed
    ...                (or t_mock is provisioned) the publish is 200 and the case passes
    ...                vacuously; the paired smoke/authz 200-cases already pin that path.
    [Tags]    auditflow    regression    auth    tenant-isolation    error-handling
    Create AuditFlow Session
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Valid Audit Event    ${correlation_id}
    ${response}=    Publish Audit Event    ${event}
    Should Be True    ${response.status_code} in (200, 403)
    ...    msg=Publish returned unexpected status ${response.status_code} (body: ${response.text}).
    IF    ${response.status_code} == 403
        Should Be Equal As Strings    ${response.json()}[code]    TENANT_NOT_PROVISIONED
        ...    msg=Ingest-gate 403 carried the wrong error code: ${response.text}
    END

Backend Logs Confirm A Spoofed TenantId Never Reached The Pipeline
    [Documentation]    Local-k8s-only companion to "Client-Supplied TenantId Cannot Change The
    ...                Publish Outcome": after a 200 publish carrying a unique spoofed body
    ...                tenantId, the backend's routing/quarantine logs must never mention that
    ...                spoofed tenant — proving the event was stamped and processed as the
    ...                token's tenant, not the payload's. Attributable because both the
    ...                correlationId and the spoofed tenantId are unique to this test call.
    [Tags]    auditflow    regression    auth    tenant-isolation    local-k8s-only
    Skip Unless Local Kubernetes
    Create AuditFlow Session
    ${spoof_tenant}=    Generate Spoof Tenant Id
    ${correlation_id}=    Generate Correlation ID
    ${event}=    Build Audit Event With Tenant    ${correlation_id}    ${spoof_tenant}
    ${response}=    Publish Audit Event    ${event}
    IF    ${response.status_code} != 200
        Skip    Publish was rejected at ingest (${response.status_code}) — no pipeline processing to corroborate.
    END
    # Sync on this event's own delivery before asserting the negative, so the absence check
    # cannot pass merely because the async pipeline hasn't run yet.
    AuditFlow Backend Logs Should Contain Correlation Id    ${correlation_id}
    AuditFlow Backend Logs Should Not Mention Tenant    ${spoof_tenant}
