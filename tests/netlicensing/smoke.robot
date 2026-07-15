*** Settings ***
Documentation    NetLicensing smoke checks — critical-path validation via the API edge only.
...              These tests run on every PR and must pass before any merge.
Resource         ../../resources/netlicensing.resource
Suite Setup      Create NetLicensing Session
Suite Teardown   Delete All Sessions

*** Test Cases ***
Try And Buy Module Validates True During Evaluation Window
    [Documentation]    Validate that a licensee in its evaluation window reports ``valid: true``
    ...                for the Try & Buy product module.  Mirrors the NetLicensing "Try it now"
    ...                curl example from the developer documentation.
    [Tags]    netlicensing    smoke    critical
    ${response}=    Validate Licensee    ${NLF_DEMO_LICENSEE}    ${NLF_DEMO_MODULE}
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${True}
    ...    msg=Expected valid=true for licensee in evaluation window, got: ${json}

Licensee Endpoint Returns Licensee Details
    [Documentation]    GET /licensee/{number} must return a 200 with the licensee data.
    [Tags]    netlicensing    smoke    critical
    ${response}=    Get Licensee    ${NLF_DEMO_LICENSEE}
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    number

Product List Endpoint Is Reachable
    [Documentation]    GET /product must return a 200, confirming the products endpoint is live.
    [Tags]    netlicensing    smoke
    ${response}=    List Products
    Response Status Should Be    ${response}    200
