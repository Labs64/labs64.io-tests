*** Settings ***
Documentation    What a module receives from the gateway (RFC_03 Principle 1: the module sees the trusted
...              X-Auth-* identity headers and never the caller's JWT). A header-echo backend sits behind a
...              copy of AuditFlow's real route, so the Auth Gateway, the route filters and the middlewares
...              are the ones the modules get. Local k3d cluster only; it skips before creating anything on
...              any other kubectl context.
Resource         ../../../resources/gateway_echo.resource
Suite Setup      Deploy Header Echo Behind Gateway
Suite Teardown   Remove Header Echo
Test Teardown    Delete All Sessions

*** Variables ***
${SESSION}    header-echo-e2e

*** Test Cases ***
A request without a token never reaches the module
    [Documentation]    The Auth Gateway answers 401 itself; the echo backend is not called.
    [Tags]    auth    regression    e2e    local-k8s-only
    Create Unauthenticated Session    ${SESSION}    ${AUDITFLOW_BASE_URL}
    ${response}=    Call Header Echo    ${SESSION}
    Response Status Should Be    ${response}    401

The module receives the identity headers and no bearer token
    [Documentation]    The caller's Authorization header is used by ForwardAuth and then removed; the module
    ...                gets only the headers the Auth Gateway derived from it.
    [Tags]    auth    regression    e2e    local-k8s-only
    Create Session With Scope    ${SESSION}    ${AUDITFLOW_BASE_URL}    ${HEADER_ECHO_SCOPE}
    ${response}=    Call Header Echo    ${SESSION}
    ${received}=    Headers The Module Received    ${response}
    # Positive control first: the probe does see the gateway's headers, so an absent
    # Authorization is the gateway's doing and not an echo that cannot see headers.
    Dictionary Should Contain Key    ${received}    x-auth-user
    Dictionary Should Contain Key    ${received}    x-auth-tenant
    Dictionary Should Contain Key    ${received}    x-auth-scopes
    Dictionary Should Not Contain Key    ${received}    authorization
    ...    msg=The bearer token reached the module (RFC_03 Principle 1).

Spoofed identity headers are replaced, not passed on
    [Documentation]    A client cannot choose who it is: the gateway removes inbound X-Auth-* before it
    ...                decides and sets its own afterwards.
    [Tags]    auth    tenant-isolation    regression    e2e    local-k8s-only
    Create Session With Scope    ${SESSION}    ${AUDITFLOW_BASE_URL}    ${HEADER_ECHO_SCOPE}
    ${spoofed}=    Create Dictionary    X-Auth-User=attacker    X-Auth-Tenant=spoofed    X-Auth-Scopes=admin
    ${response}=    Call Header Echo    ${SESSION}    ${spoofed}
    ${received}=    Headers The Module Received    ${response}
    Should Not Be Equal    ${received}[x-auth-user]    attacker
    Should Not Be Equal    ${received}[x-auth-tenant]    spoofed
    Should Not Contain    ${received}[x-auth-scopes]    admin
    Dictionary Should Not Contain Key    ${received}    authorization

Alias spellings of the identity headers never reach the module
    [Documentation]    Removing X-Auth-* is not enough when the edge forwards names that merely alias them
    ...                (``X_Auth_User``, ``X.Auth.User``): a backend that derives variable names from header
    ...                names (nginx ``$http_x_auth_user``, CGI/WSGI) reads the alias as the real header. Traefik
    ...                must drop them (``aliasHeadersStrategy: delete``) or refuse the request (``reject``).
    [Tags]    auth    tenant-isolation    regression    e2e    local-k8s-only
    Create Session With Scope    ${SESSION}    ${AUDITFLOW_BASE_URL}    ${HEADER_ECHO_SCOPE}
    ${aliases}=    Create Dictionary
    ...    X_Auth_User=attacker    X.Auth.Tenant=spoofed    X_Auth_Scopes=admin    X.Auth.Request.Id=forged
    ${response}=    Call Header Echo    ${SESSION}    ${aliases}
    Pass Execution If    ${response.status_code} == 400    Rejected at the edge (aliasHeadersStrategy: reject): nothing reached the module.
    ${received}=    Headers The Module Received    ${response}
    # Positive control: the probe sees the gateway's own headers, so the absent aliases are the edge's doing.
    Dictionary Should Contain Key    ${received}    x-auth-user
    Should Not Be Equal    ${received}[x-auth-user]    attacker
    FOR    ${name}    IN    @{received.keys()}
        Should Not Match Regexp    ${name}    ^x[_.]auth
        ...    msg=The alias header '${name}' reached the module (Traefik aliasHeadersStrategy).
    END
