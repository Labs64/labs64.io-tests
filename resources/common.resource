*** Settings ***
Documentation    Common keywords and variables shared across all Labs64.IO test suites.
Library          RequestsLibrary
Library          Collections
Library          String
Library          OperatingSystem

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
