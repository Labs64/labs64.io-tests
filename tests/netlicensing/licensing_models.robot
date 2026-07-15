*** Settings ***
Documentation    NetLicensing licensing-model regression tests.
...              Covers the core licensing model behaviours observable from the API edge:
...              Subscription, Try & Buy, Floating, Pay-per-Use, and Multi-Feature.
Resource         ../../resources/netlicensing.resource
Suite Setup      Create NetLicensing Session
Suite Teardown   Delete All Sessions

*** Test Cases ***
Subscription Model Rejects Expired Licensee
    [Documentation]    A licensee whose subscription has expired must receive ``valid: false``.
    [Tags]    netlicensing    regression    licensing-models
    ${response}=    Validate Licensee    ITEST-EXPIRED-SUB    MTEST-SUBSCRIPTION
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${False}
    ...    msg=Expired subscription must report valid=false but got: ${json}

Floating License Grants Access Within Seat Count
    [Documentation]    A floating-license licensee within its seat count must validate to ``valid: true``.
    [Tags]    netlicensing    regression    licensing-models
    ${response}=    Validate Licensee    ITEST-FLOATING    MTEST-FLOATING
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${True}
    ...    msg=Floating license within seat count must report valid=true but got: ${json}

Pay Per Use License Decrements Quantity On Validation
    [Documentation]    Each successful PPU validation must consume one unit from the license quota.
    [Tags]    netlicensing    regression    licensing-models    pay-per-use
    # First validation — confirms access is granted
    ${response}=    Validate Licensee    ITEST-PPU    MTEST-PPU
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${True}
    ...    msg=PPU license with remaining quota must report valid=true but got: ${json}

Multi Feature License Grants Individual Feature Access
    [Documentation]    A multi-feature licensee must report ``valid: true`` for each activated feature.
    [Tags]    netlicensing    regression    licensing-models
    ${response}=    Validate Licensee    ITEST-MULTIFEATURE    MTEST-MULTIFEATURE
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${True}
    ...    msg=Multi-feature licensee must report valid=true for an activated feature but got: ${json}

Unknown Licensee Returns 404
    [Documentation]    Querying a licensee number that does not exist must return HTTP 404.
    [Tags]    netlicensing    regression    licensing-models    error-handling
    ${response}=    Validate Licensee    ITEST-NONEXISTENT    MTEST-DEMO
    Response Status Should Be    ${response}    404
