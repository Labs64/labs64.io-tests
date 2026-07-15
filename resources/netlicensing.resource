*** Settings ***
Documentation    NetLicensing-specific keywords and variables.
Library          RequestsLibrary
Library          Collections
Resource         common.resource

*** Variables ***
${NLF_SESSION_ALIAS}    netlicensing
${NLF_DEMO_LICENSEE}    ITEST-DEMO
${NLF_DEMO_MODULE}      MTEST-DEMO

*** Keywords ***
Create NetLicensing Session
    [Documentation]    Open an authenticated HTTP session pointed at the NetLicensing base URL.
    Create Authenticated Session    ${NLF_SESSION_ALIAS}    ${NETLICENSING_BASE_URL}

Validate Licensee
    [Documentation]    POST a validation request for the given licensee and product module.
    [Arguments]    ${licensee}=${NLF_DEMO_LICENSEE}    ${module}=${NLF_DEMO_MODULE}
    ${data}=    Create Dictionary    productModuleNumber0=${module}
    ${headers}=    Create Dictionary
    ...    Accept=application/json
    ...    Content-Type=application/x-www-form-urlencoded
    ${response}=    POST On Session
    ...    ${NLF_SESSION_ALIAS}
    ...    /licensee/${licensee}/validate
    ...    data=${data}
    ...    headers=${headers}
    ...    expected_status=any
    RETURN    ${response}

Get Licensee
    [Documentation]    GET the details of the given licensee.
    [Arguments]    ${licensee}=${NLF_DEMO_LICENSEE}
    ${response}=    GET On Session    ${NLF_SESSION_ALIAS}    /licensee/${licensee}    expected_status=any
    RETURN    ${response}

List Products
    [Documentation]    GET all products visible to the authenticated vendor.
    ${response}=    GET On Session    ${NLF_SESSION_ALIAS}    /product    expected_status=any
    RETURN    ${response}
