*** Settings ***
Documentation    Common keywords and variables shared across all Labs64.IO test suites.
Library          RequestsLibrary
Library          Collections
Library          String
Library          OperatingSystem

*** Variables ***
# Base URLs are resolved from environment variables; fallback to localhost defaults for local runs.
${NETLICENSING_BASE_URL}      %{NETLICENSING_BASE_URL=https://go.netlicensing.io/core/v2/rest}
${AUDITFLOW_BASE_URL}         %{AUDITFLOW_BASE_URL=http://localhost:8080}
${PAYMENT_GATEWAY_BASE_URL}   %{PAYMENT_GATEWAY_BASE_URL=http://localhost:8081}
${IAM_GATEWAY_BASE_URL}       %{IAM_GATEWAY_BASE_URL=http://localhost:8082}
${INVOICING_BASE_URL}         %{INVOICING_BASE_URL=http://localhost:8083}
${API_TOKEN}                  %{API_TOKEN=${EMPTY}}

*** Keywords ***
Create Authenticated Session
    [Documentation]    Create an HTTP session with bearer-token authentication headers.
    [Arguments]    ${alias}    ${base_url}    ${token}=${API_TOKEN}
    ${auth_header}=    Set Variable    Bearer ${token}
    ${headers}=    Create Dictionary
    ...    Authorization=${auth_header}
    ...    Accept=application/json
    ...    Content-Type=application/json
    Create Session    ${alias}    ${base_url}    headers=${headers}    verify=True

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
