*** Settings ***
Documentation    Payment provider lifecycle regression — create, read, update, delete a tenant
...              payment provider via the noop PSP (no external sandbox required).
Resource         ../../resources/payment_gateway.resource
Suite Setup      Create Payment Gateway Session With Scope    payment-provider:write
Suite Teardown   Delete All Sessions

*** Test Cases ***
Payment Provider Lifecycle: Create, Read, Update, Delete
    [Documentation]    A tenant payment provider created against the noop PSP must be
    ...                retrievable, updatable, and deletable through its full lifecycle.
    [Tags]    payment-gateway    regression    critical
    ${create_response}=    Create Payment Provider
    Response Status Should Be    ${create_response}    200
    ${provider_id}=    Set Variable    ${create_response.json()}[id]
    Should Be Equal As Strings    ${create_response.json()}[provider]    noop
    Should Be True    ${create_response.json()}[active]

    ${get_response}=    Get Payment Provider    ${provider_id}
    Response Status Should Be    ${get_response}    200
    Should Be Equal As Strings    ${get_response.json()}[id]    ${provider_id}

    ${updates}=    Create Dictionary    active=${FALSE}
    ${update_response}=    Update Payment Provider    ${provider_id}    ${updates}
    Response Status Should Be    ${update_response}    200
    Should Be Equal    ${update_response.json()}[active]    ${FALSE}

    ${delete_response}=    Delete Payment Provider    ${provider_id}
    Response Status Should Be    ${delete_response}    204

    ${after_delete}=    Get Payment Provider    ${provider_id}
    Response Status Should Be    ${after_delete}    404
