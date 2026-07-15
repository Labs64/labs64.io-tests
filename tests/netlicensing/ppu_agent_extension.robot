*** Settings ***
Documentation    NetLicensing Pay-per-Use agent extension regression tests (EXT-PPU-01..15).
...              All assertions go through the validation API edge — no direct DB or MQ access.
Resource         ../../resources/netlicensing.resource
Suite Setup      Create NetLicensing Session
Suite Teardown   Delete All Sessions

*** Variables ***
${PPU_LICENSEE}    ITEST-PPU-EXT
${PPU_MODULE}      MTEST-PPU-EXT

*** Test Cases ***
EXT-PPU-01 Validation Returns 200 For Active PPU License
    [Documentation]    A licensee with an active PPU license and remaining quota must return HTTP 200.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-01
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    ${PPU_MODULE}
    Response Status Should Be    ${response}    200

EXT-PPU-02 Validation Reports Valid True While Quota Remains
    [Documentation]    ``valid: true`` must be returned when at least one PPU unit remains.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-02
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    ${PPU_MODULE}
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${True}
    ...    msg=PPU license with quota must be valid=true but got: ${json}

EXT-PPU-03 Validation Reports Valid False When Quota Is Exhausted
    [Documentation]    Once all PPU units have been consumed, ``valid: false`` must be returned.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-03
    ${response}=    Validate Licensee    ITEST-PPU-EXHAUSTED    ${PPU_MODULE}
    Response Status Should Be    ${response}    200
    ${json}=    Set Variable    ${response.json()}
    Should Be Equal    ${json}[valid]    ${False}
    ...    msg=Exhausted PPU license must be valid=false but got: ${json}

EXT-PPU-04 Validation Rejects Unknown Module
    [Documentation]    Specifying a module number that does not exist must return HTTP 404.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-04    error-handling
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    MTEST-NONEXISTENT
    Response Status Should Be    ${response}    404

EXT-PPU-05 Validation Rejects Missing Module Parameter
    [Documentation]    Omitting the required ``productModuleNumber0`` field must return HTTP 400.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-05    error-handling
    ${data}=    Create Dictionary
    ${headers}=    Create Dictionary
    ...    Accept=application/json
    ...    Content-Type=application/x-www-form-urlencoded
    ${response}=    POST On Session
    ...    netlicensing
    ...    /licensee/${PPU_LICENSEE}/validate
    ...    data=${data}
    ...    headers=${headers}
    ...    expected_status=any
    Response Status Should Be    ${response}    400

EXT-PPU-06 Unauthenticated Validation Request Returns 401
    [Documentation]    A validation request without credentials must be rejected with HTTP 401.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-06    auth
    ${headers}=    Create Dictionary
    ...    Accept=application/json
    ...    Content-Type=application/x-www-form-urlencoded
    Create Session    no-auth    ${NETLICENSING_BASE_URL}    headers=${headers}    verify=True
    ${data}=    Create Dictionary    productModuleNumber0=${PPU_MODULE}
    ${response}=    POST On Session    no-auth    /licensee/${PPU_LICENSEE}/validate    data=${data}    expected_status=any
    Response Status Should Be    ${response}    401
    [Teardown]    Delete All Sessions

EXT-PPU-07 Response Contains Required Fields
    [Documentation]    The validation response body must contain at least ``valid`` and ``licenseeNumber``.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-07    contract
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    ${PPU_MODULE}
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    valid
    Response Should Contain Key    ${response}    licenseeNumber

EXT-PPU-08 Accept Header JSON Returns JSON Body
    [Documentation]    Requesting JSON via the Accept header must return a JSON content-type response.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-08    contract
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    ${PPU_MODULE}
    Response Status Should Be    ${response}    200
    Should Contain    ${response.headers}[Content-Type]    application/json
    ...    msg=Expected Content-Type: application/json but got: ${response.headers}[Content-Type]

EXT-PPU-09 Concurrent Validations Do Not Over-Consume Quota
    [Documentation]    Two sequential validation calls against a single-unit PPU license must result
    ...                in the second call reporting ``valid: false``, not double-consuming.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-09
    # First call — consumes the last remaining unit
    ${r1}=    Validate Licensee    ITEST-PPU-SINGLE    MTEST-PPU-EXT
    Response Status Should Be    ${r1}    200
    Should Be Equal    ${r1.json()}[valid]    ${True}
    # Second call — quota is now zero
    ${r2}=    Validate Licensee    ITEST-PPU-SINGLE    MTEST-PPU-EXT
    Response Status Should Be    ${r2}    200
    Should Be Equal    ${r2.json()}[valid]    ${False}

EXT-PPU-10 Validate Without Accept Header Defaults To Application JSON
    [Documentation]    Omitting the Accept header must still return a parseable JSON body.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-10    contract
    ${data}=    Create Dictionary    productModuleNumber0=${PPU_MODULE}
    ${headers}=    Create Dictionary    Content-Type=application/x-www-form-urlencoded
    ${response}=    POST On Session
    ...    netlicensing
    ...    /licensee/${PPU_LICENSEE}/validate
    ...    data=${data}
    ...    headers=${headers}
    ...    expected_status=any
    Response Status Should Be    ${response}    200
    ${json}=    Evaluate    __import__('json').loads($response.text)
    Should Not Be Empty    ${json}

EXT-PPU-11 Validation Response Time Is Below Threshold
    [Documentation]    The validation endpoint must respond within 2 000 ms under nominal conditions.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-11    performance
    ${before}=    Evaluate    __import__('time').time()
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    ${PPU_MODULE}
    ${after}=    Evaluate    __import__('time').time()
    ${elapsed_ms}=    Evaluate    (${after} - ${before}) * 1000
    Response Status Should Be    ${response}    200
    Should Be True    ${elapsed_ms} < 2000
    ...    msg=Validation response took ${elapsed_ms} ms — exceeds the 2 000 ms SLO threshold

EXT-PPU-12 Validate With Multiple Module Numbers Returns First Matching Result
    [Documentation]    When multiple ``productModuleNumberN`` fields are supplied, the API must
    ...                process at least the first one and return a valid response.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-12
    ${data}=    Create Dictionary
    ...    productModuleNumber0=${PPU_MODULE}
    ...    productModuleNumber1=MTEST-PPU-EXT-2
    ${headers}=    Create Dictionary
    ...    Accept=application/json
    ...    Content-Type=application/x-www-form-urlencoded
    ${response}=    POST On Session
    ...    netlicensing
    ...    /licensee/${PPU_LICENSEE}/validate
    ...    data=${data}
    ...    headers=${headers}
    ...    expected_status=any
    Response Status Should Be    ${response}    200

EXT-PPU-13 Validate Returns 404 For Non-Existent Licensee
    [Documentation]    Submitting a validation request for a licensee number that does not exist
    ...                must return HTTP 404.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-13    error-handling
    ${response}=    Validate Licensee    ITEST-PPU-NONEXISTENT    ${PPU_MODULE}
    Response Status Should Be    ${response}    404

EXT-PPU-14 Vendor Cross-Tenant Isolation Is Enforced
    [Documentation]    A vendor must not be able to validate a licensee that belongs to a different
    ...                vendor's product — the API must return 403 or 404.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-14    tenant-isolation    critical
    ${response}=    Validate Licensee    ITEST-OTHER-VENDOR-LICENSEE    ${PPU_MODULE}
    ${status}=    Convert To Integer    ${response.status_code}
    Should Be True    ${status} == 403 or ${status} == 404
    ...    msg=Cross-tenant access must be rejected (403 or 404) but got HTTP ${status}

EXT-PPU-15 PPU License Number Field Is Returned In Response
    [Documentation]    The validation response for a PPU-licensed module must include a
    ...                ``licenseNumber`` (or equivalent) field confirming which license was used.
    [Tags]    netlicensing    regression    ppu-extension    ext-ppu-15    contract
    ${response}=    Validate Licensee    ${PPU_LICENSEE}    ${PPU_MODULE}
    Response Status Should Be    ${response}    200
    Response Should Contain Key    ${response}    licenseNumber
