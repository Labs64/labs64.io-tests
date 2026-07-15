*** Settings ***
Documentation    Common keywords and variables shared across all Labs64.IO test suites.
Library          RequestsLibrary
Library          Collections
Library          String
Library          OperatingSystem
Library          Process

*** Variables ***
# All module URLs go through the Traefik/authproxy gateway edge — never straight to a
# backend port. Authorization (Cedar) is enforced at the gateway; a backend hit directly
# would skip it entirely (services trust gateway-supplied X-Auth-* headers).
${GATEWAY_BASE_URL}           %{GATEWAY_BASE_URL=http://gateway.localhost}
${AUDITFLOW_BASE_URL}         %{AUDITFLOW_BASE_URL=${GATEWAY_BASE_URL}/auditflow/api/v1}
${PAYMENT_GATEWAY_BASE_URL}   %{PAYMENT_GATEWAY_BASE_URL=${GATEWAY_BASE_URL}/payment-gateway/api/v1}

# mock-oidc (DEV ONLY) mints M2M tokens on demand — see `Get OIDC Token` below.
${MOCK_OIDC_BASE_URL}         %{MOCK_OIDC_BASE_URL=http://mock-oidc.localhost}
${OIDC_ISSUER_ID}             %{OIDC_ISSUER_ID=labs64io}
${OIDC_CLIENT_ID}             %{OIDC_CLIENT_ID=local-test}
${OIDC_CLIENT_SECRET}         %{OIDC_CLIENT_SECRET=local-test}

# Optional static override for environments where mock-oidc isn't reachable (e.g. a
# pre-provisioned CI service token). Prefer `Get OIDC Token` / `Create Session With Scope`
# wherever a specific scope combination needs to be asserted.
${API_TOKEN}                  %{API_TOKEN=${EMPTY}}

# Pinned local dev cluster context (see labs64.io-helm-charts/DEVELOPERS.md, `k3d cluster
# create --config k3d/labs64io.yaml`). `Local Kubernetes Available` only returns true for an
# exact match — never for an arbitrary/shared/prod kubectl context — see AGENTS.md
# "Local-only pod-log corroboration" for why kubectl appears here at all.
${LOCAL_K8S_CONTEXT}           %{LOCAL_K8S_CONTEXT=k3d-labs64io}

# Shared local-k8s-only namespace/deployment names — every Labs64.IO module and the
# authproxy share one namespace and one authproxy instance, so these live here rather than
# being redeclared per module. Module backend deployment names (e.g. AUDITFLOW_K8S_DEPLOYMENT)
# stay in each module's own resource file. Never used unless `Local Kubernetes Available` is true.
${LABS64IO_K8S_NAMESPACE}      %{LABS64IO_K8S_NAMESPACE=labs64io}
${AUTHPROXY_K8S_DEPLOYMENT}    %{AUTHPROXY_K8S_DEPLOYMENT=labs64io-traefik-authproxy}

*** Keywords ***
Get OIDC Token
    [Documentation]    Request an M2M access token from mock-oidc for the given ``scope``.
    ...                ``scope`` may be a named persona (``admin``, ``auditflow``, ``ecommerce``,
    ...                ``no-access``) that maps to a curated, fixed scope set, or any other literal
    ...                string (e.g. ``audit-event:read``), which mock-oidc echoes verbatim into the
    ...                token's ``scope`` claim — letting a test mint exactly the scope it wants to
    ...                assert against. DEV-ONLY provider; never point this at a non-local environment.
    [Arguments]    ${scope}
    ${data}=    Create Dictionary
    ...    grant_type=client_credentials
    ...    client_id=${OIDC_CLIENT_ID}
    ...    client_secret=${OIDC_CLIENT_SECRET}
    ...    scope=${scope}
    ${response}=    POST    ${MOCK_OIDC_BASE_URL}/${OIDC_ISSUER_ID}/token    data=${data}
    Response Status Should Be    ${response}    200
    RETURN    ${response.json()}[access_token]

Create Authenticated Session
    [Documentation]    Create an HTTP session with bearer-token authentication headers.
    ...                Fails with a clear message if the token is empty so missing
    ...                credentials are never silently swallowed as a 401 auth failure.
    [Arguments]    ${alias}    ${base_url}    ${token}
    Should Not Be Empty    ${token}
    ...    msg=Bearer token must not be empty. Use `Get OIDC Token`/`Create Session With Scope`, or set API_TOKEN.
    ${auth_header}=    Set Variable    Bearer ${token}
    ${headers}=    Create Dictionary
    ...    Authorization=${auth_header}
    ...    Accept=application/json
    ...    Content-Type=application/json
    Create Session    ${alias}    ${base_url}    headers=${headers}    verify=True

Create Session With Scope
    [Documentation]    Open an authenticated HTTP session pointed at ``base_url``, using a
    ...                freshly-minted mock-oidc token carrying exactly ``scope``. This is the
    ...                primary way authz tests assert allow/deny behavior for a specific scope.
    [Arguments]    ${alias}    ${base_url}    ${scope}
    ${token}=    Get OIDC Token    ${scope}
    Create Authenticated Session    ${alias}    ${base_url}    ${token}

Create Unauthenticated Session
    [Documentation]    Create an HTTP session without any authentication headers.
    [Arguments]    ${alias}    ${base_url}
    ${headers}=    Create Dictionary    Accept=application/json
    Create Session    ${alias}    ${base_url}    headers=${headers}    verify=True

Response Status Should Be
    [Documentation]    Assert the HTTP response status code and log the body on failure.
    [Arguments]    ${response}    ${expected_status}
    Should Be Equal As Integers    ${response.status_code}    ${expected_status}
    ...    msg=Expected HTTP ${expected_status} but received ${response.status_code}. Body: ${response.text}

Response Should Contain Key
    [Documentation]    Assert that a JSON response body contains a top-level key.
    [Arguments]    ${response}    ${key}
    ${json}=    Set Variable    ${response.json()}
    Dictionary Should Contain Key    ${json}    ${key}

Generate Correlation ID
    [Documentation]    Return a unique correlation identifier prefixed with ``test-``.
    ${uuid}=    Evaluate    __import__('uuid').uuid4().hex
    RETURN    test-${uuid}

Local Kubernetes Available
    [Documentation]    Return ``${True}`` only when ``kubectl`` is on PATH and its current
    ...                context exactly matches ``${LOCAL_K8S_CONTEXT}`` (the pinned local k3d
    ...                dev cluster). Never returns true for a shared/staging/prod context, and
    ...                never raises — a missing kubectl binary (e.g. on a GitHub Actions
    ...                runner) is treated as "not available", not an error.
    ${result}=    Run Process    kubectl config current-context    shell=True
    IF    ${result.rc} != 0    RETURN    ${False}
    ${context}=    Strip String    ${result.stdout}
    RETURN    ${context == '${LOCAL_K8S_CONTEXT}'}

Skip Unless Local Kubernetes
    [Documentation]    Skip (not fail) the current test unless the local k3d dev cluster is the
    ...                active kubectl context. Keeps kubectl-based corroboration opt-in and
    ...                CI-silent — see AGENTS.md "Local-only pod-log corroboration".
    ${available}=    Local Kubernetes Available
    IF    not ${available}
        Skip    Local k3d cluster (context '${LOCAL_K8S_CONTEXT}') is not active — skipping kubectl-based log corroboration.
    END

Fetch Recent Pod Logs
    [Documentation]    Local-k8s-only. Return the last ``${since}`` of combined-container
    ...                kubectl logs for ``${deployment}`` in ``${namespace}``. Generic across
    ...                modules — callers must call `Skip Unless Local Kubernetes` first.
    [Arguments]    ${namespace}    ${deployment}    ${since}=90s
    # Literal `=` chars below are escaped (`\=`) — Run Process accepts **kwargs, so any
    # unescaped `=` in a cell is misparsed as a named argument rather than shell text.
    ${result}=    Run Process
    ...    kubectl logs -n ${namespace} deploy/${deployment} --all-containers\=true --since\=${since}
    ...    shell=True
    RETURN    ${result.stdout}

Authproxy Logs Should Show Cedar Decision
    [Documentation]    Local-k8s-only. Assert the authproxy recently logged a Cedar ``${outcome}``
    ...                (``enforced-allow``/``enforced-deny``) for ``${module}``'s ``${op}``
    ...                operation — corroborates the HTTP status a test already asserted against
    ...                the edge's own independent decision log. Matches the log format
    ...                ``cedar outcome=<outcome> module=<module> op=<op>``. Generic across
    ...                modules; each module's resource file may wrap this with its own defaults.
    [Arguments]    ${module}    ${op}    ${outcome}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUTHPROXY_K8S_DEPLOYMENT}    ${since}
    Should Contain    ${logs}    outcome=${outcome} module=${module} op=${op}
    ...    msg=Expected authproxy Cedar outcome '${outcome}' for ${module}::${op} not found in recent logs.

Authproxy Logs Should Show No-Token Rejection
    [Documentation]    Local-k8s-only. Assert the authproxy recently logged a no-token rejection
    ...                for ``${method} ${gateway_path}`` — corroborates a 401-for-missing-auth
    ...                HTTP assertion against the edge's own decision log. Generic across modules.
    [Arguments]    ${method}    ${gateway_path}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUTHPROXY_K8S_DEPLOYMENT}    ${since}
    Should Contain    ${logs}    Auth rejected [no-token] — ${method} ${gateway_path}
    ...    msg=Expected authproxy no-token rejection log line for ${method} ${gateway_path} not found in recent logs.
