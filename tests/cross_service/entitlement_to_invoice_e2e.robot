*** Settings ***
Documentation    Cross-service end-to-end flow: entitlement check → invoice generation.
...
...              This test exercises the critical path that links NetLicensing (entitlement)
...              with the Invoicing service: confirm a licensee is entitled, then assert that
...              a corresponding invoice can be created and retrieved.  Every assertion goes
...              through the public API edge — no direct DB or MQ access.
Library          RequestsLibrary
Library          Collections
Resource         ../../resources/common.resource
Resource         ../../resources/netlicensing.resource
Suite Setup      Setup E2E Sessions
Suite Teardown   Delete All Sessions

*** Variables ***
${E2E_LICENSEE}    ITEST-E2E-LICENSEE
${E2E_MODULE}      MTEST-E2E-MODULE

*** Keywords ***
Setup E2E Sessions
    Create Authenticated Session    netlicensing    ${NETLICENSING_BASE_URL}
    Create Authenticated Session    invoicing       ${INVOICING_BASE_URL}

*** Test Cases ***
Entitled Licensee Can Have An Invoice Generated
    [Documentation]    Full entitlement-to-invoice path:
    ...                1. Validate the licensee is entitled via NetLicensing.
    ...                2. Create an invoice for that licensee via the Invoicing service.
    ...                3. Retrieve the created invoice and confirm it exists.
    [Tags]    cross-service    e2e    regression    critical
    # Step 1 — confirm entitlement
    ${validation}=    Validate Licensee    ${E2E_LICENSEE}    ${E2E_MODULE}
    Response Status Should Be    ${validation}    200
    Should Be Equal    ${validation.json()}[valid]    ${True}
    ...    msg=E2E test requires an entitled licensee but got valid=false

    # Step 2 — create an invoice for the entitled licensee
    ${invoice_body}=    Create Dictionary
    ...    licenseeNumber=${E2E_LICENSEE}
    ...    moduleNumber=${E2E_MODULE}
    ...    description=E2E smoke invoice
    ${create_response}=    POST On Session    invoicing    /invoices    json=${invoice_body}    expected_status=any
    Response Status Should Be    ${create_response}    201
    ${invoice_id}=    Set Variable    ${create_response.json()}[id]
    Should Not Be Empty    ${invoice_id}    msg=Created invoice must return a non-empty id

    # Step 3 — retrieve the invoice and confirm it is persisted
    ${get_response}=    GET On Session    invoicing    /invoices/${invoice_id}    expected_status=any
    Response Status Should Be    ${get_response}    200
    ${retrieved}=    Set Variable    ${get_response.json()}
    Should Be Equal    ${retrieved}[id]    ${invoice_id}
    ...    msg=Retrieved invoice id ${retrieved}[id] does not match created id ${invoice_id}

Non-Entitled Licensee Does Not Produce An Invoice
    [Documentation]    If NetLicensing reports ``valid: false``, no invoice must be created.
    ...                The Invoicing service must refuse the request with 402 or 403.
    [Tags]    cross-service    e2e    regression
    # Step 1 — confirm the licensee is NOT entitled (uses an expired licensee fixture)
    ${validation}=    Validate Licensee    ITEST-EXPIRED-SUB    MTEST-E2E-MODULE
    Response Status Should Be    ${validation}    200
    Should Be Equal    ${validation.json()}[valid]    ${False}
    ...    msg=This test requires an expired/non-entitled licensee fixture

    # Step 2 — attempt to create an invoice; must be refused
    ${invoice_body}=    Create Dictionary
    ...    licenseeNumber=ITEST-EXPIRED-SUB
    ...    moduleNumber=MTEST-E2E-MODULE
    ...    description=E2E refused invoice
    ${create_response}=    POST On Session    invoicing    /invoices    json=${invoice_body}    expected_status=any
    ${status}=    Convert To Integer    ${create_response.status_code}
    Should Be True    ${status} == 402 or ${status} == 403
    ...    msg=Invoice creation for a non-entitled licensee must be refused (402 or 403) but got HTTP ${status}
