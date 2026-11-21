*** Settings ***
Documentation    Local-k8s-only fixture that shows what a module receives from the gateway: a
...              header-echo backend behind a route that carries the filter chain of a real module
...              route, copied at run time (scripts/header_echo_route.py) so the probe cannot drift
...              from the charts. A pure HTTP client cannot see these headers — see AGENTS.md
...              "Local-only pod-log corroboration".
Library          Collections
Library          Process
Resource         common.resource

*** Variables ***
${HEADER_ECHO_LABEL}           labs64.io/temp=header-echo-e2e
${HEADER_ECHO_NAME}            header-echo-e2e
${HEADER_ECHO_HOST}            header-echo.localhost
# The route whose filter chain the echo route copies: AuditFlow's first protected rule. Its name is
# the Helmfile release + "-gateway" (labs64.io-helm-charts, chart-libs `gateway-routes`).
${HEADER_ECHO_SOURCE_ROUTE}    %{HEADER_ECHO_SOURCE_ROUTE=labs64io-auditflow-gateway}
# The operation that route exposes (AuditFlow's only one) and the scope it needs.
${HEADER_ECHO_OPERATION}       /audit/publish
${HEADER_ECHO_SCOPE}           audit-event:write

*** Keywords ***
Deploy Header Echo Behind Gateway
    [Documentation]    Local-k8s-only. Start the echo backend and publish it on ``${HEADER_ECHO_HOST}``
    ...                with the real route's filters and path match, so the Auth Gateway decides exactly
    ...                as it does for AuditFlow. Returns once the gateway answers on the new host.
    Skip Unless Local Kubernetes
    Remove Header Echo
    Kubectl    apply    -n    ${LABS64IO_K8S_NAMESPACE}    -f    ${CURDIR}/header-echo.yaml
    Kubectl    rollout    status    deploy/${HEADER_ECHO_NAME}    -n    ${LABS64IO_K8S_NAMESPACE}    --timeout\=180s
    ${source}=    Kubectl    get    httproute    ${HEADER_ECHO_SOURCE_ROUTE}    -n    ${LABS64IO_K8S_NAMESPACE}    -o    json
    ${result}=    Run Process    python3    ${CURDIR}/../scripts/header_echo_route.py
    ...    ${HEADER_ECHO_NAME}    ${HEADER_ECHO_HOST}    ${HEADER_ECHO_LABEL}    stdin=${source}
    Should Be Equal As Integers    ${result.rc}    0    msg=Could not build the echo route: ${result.stderr}
    Kubectl With Input    ${result.stdout}    apply    -f    -
    Create Unauthenticated Session    header-echo-probe    ${AUDITFLOW_BASE_URL}
    Wait Until Keyword Succeeds    30x    1s    Gateway Should Serve Header Echo

Gateway Should Serve Header Echo
    [Documentation]    Fails until the new route is programmed: an unknown host is a 404, the Auth Gateway's
    ...                answer for a request without a token is a 401.
    ${response}=    Call Header Echo    header-echo-probe
    Should Be Equal As Integers    ${response.status_code}    401
    ...    msg=The echo route is not live yet (HTTP ${response.status_code}).

Call Header Echo
    [Documentation]    POST the module's real operation through the gateway, addressed to the echo host.
    ...                ``${extra_headers}`` are sent as given (spoofed identity headers, for example).
    [Arguments]    ${alias}    ${extra_headers}=${NONE}
    ${headers}=    Create Dictionary    Host=${HEADER_ECHO_HOST}
    IF    $extra_headers is not None    Set To Dictionary    ${headers}    &{extra_headers}
    ${response}=    POST On Session    ${alias}    ${HEADER_ECHO_OPERATION}
    ...    data={}    headers=${headers}    expected_status=any
    RETURN    ${response}

Headers The Module Received
    [Documentation]    The request headers the echo backend saw, names lower-cased. Fails unless the
    ...                request reached the backend (HTTP 200).
    [Arguments]    ${response}
    Response Status Should Be    ${response}    200
    RETURN    ${response.json()}[headers]

Remove Header Echo
    [Documentation]    Delete everything the fixture created, by label. Safe to call when nothing exists.
    ${available}=    Local Kubernetes Available
    IF    not ${available}    RETURN
    Run Process    kubectl    delete    httproute,svc,deploy,cm    -n    ${LABS64IO_K8S_NAMESPACE}
    ...    -l    ${HEADER_ECHO_LABEL}    --ignore-not-found    --wait\=false

Kubectl
    [Documentation]    Run kubectl and return stdout; fail with its stderr.
    [Arguments]    @{args}
    ${result}=    Run Process    kubectl    @{args}
    Should Be Equal As Integers    ${result.rc}    0    msg=kubectl ${args} failed: ${result.stderr}
    RETURN    ${result.stdout}

Kubectl With Input
    [Documentation]    Run kubectl with ``${input}`` on stdin; fail with its stderr.
    [Arguments]    ${input}    @{args}
    ${result}=    Run Process    kubectl    @{args}    stdin=${input}
    Should Be Equal As Integers    ${result.rc}    0    msg=kubectl ${args} failed: ${result.stderr}
