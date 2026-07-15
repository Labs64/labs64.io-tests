*** Settings ***
Documentation    Invoicing service smoke checks — critical-path validation via the API edge.
Library          RequestsLibrary
Library          Collections
Resource         ../../resources/common.resource
Suite Setup      Create Authenticated Session    invoicing    ${INVOICING_BASE_URL}
Suite Teardown   Delete All Sessions

*** Test Cases ***
Health Endpoint Returns 200
    [Documentation]    The Invoicing service health endpoint must return HTTP 200.
    [Tags]    invoicing    smoke    critical
    ${response}=    GET On Session    invoicing    /health    expected_status=any
    Response Status Should Be    ${response}    200

Invoices List Endpoint Is Reachable
    [Documentation]    GET /invoices must return 200 (or 206 for paginated responses).
    [Tags]    invoicing    smoke    critical
    ${response}=    GET On Session    invoicing    /invoices    expected_status=any
    ${status}=    Convert To Integer    ${response.status_code}
    Should Be True    ${status} == 200 or ${status} == 206
    ...    msg=Expected 200 or 206 from GET /invoices but got HTTP ${status}

Unauthenticated Request Is Rejected With 401
    [Documentation]    Any authenticated endpoint must reject requests without credentials.
    [Tags]    invoicing    smoke    auth    critical
    ${headers}=    Create Dictionary    Accept=application/json
    Create Session    inv-no-auth    ${INVOICING_BASE_URL}    headers=${headers}    verify=True
    ${response}=    GET On Session    inv-no-auth    /invoices    expected_status=any
    Response Status Should Be    ${response}    401
    [Teardown]    Delete All Sessions

Invoice Creation Requires Mandatory Fields
    [Documentation]    Attempting to create an invoice without required fields must be rejected
    ...                with HTTP 400 — not accepted and silently persisted incomplete.
    [Tags]    invoicing    smoke    error-handling
    ${empty_body}=    Create Dictionary
    ${response}=    POST On Session    invoicing    /invoices    json=${empty_body}    expected_status=any
    Response Status Should Be    ${response}    400
