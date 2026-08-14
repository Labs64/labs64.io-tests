*** Settings ***
Documentation    Local Kubernetes probe for Payment Gateway to AuditFlow event delivery.
...              A unique correlation ID ties the gateway PG request to AuditFlow's asynchronous
...              processing log. The test skips before creating sessions outside k3d-labs64io.
Resource         ../../../resources/payment_gateway.resource
Resource         ../../../resources/auditflow.resource
Test Teardown    Delete All Sessions

*** Variables ***
${PAYMENT_AUDITFLOW_E2E_SCOPES}    payment-provider:read payment-provider:write payment:write
${PAYMENT_AUDITFLOW_SESSION}       payment-auditflow-e2e

*** Test Cases ***
Created payment event reaches AuditFlow
    [Documentation]    Creating a payment through the gateway eventually produces an AuditFlow
    ...                event carrying the same correlation ID.
    [Tags]    e2e    regression    local-k8s-only    payment-gateway    auditflow
    Skip Unless Local Kubernetes
    Create Payment Gateway Session With Scope
    ...    ${PAYMENT_AUDITFLOW_E2E_SCOPES}
    ...    ${PAYMENT_AUDITFLOW_SESSION}
    ${provider_id}=    Ensure Active Noop Payment Provider    ${PAYMENT_AUDITFLOW_SESSION}
    ${correlation_id}=    Generate Correlation ID

    ${response}=    Create Payment With Correlation Id
    ...    ${provider_id}
    ...    ${correlation_id}
    ...    ${PAYMENT_AUDITFLOW_SESSION}

    Response Status Should Be    ${response}    201
    Response Should Contain Key    ${response}    id
    AuditFlow Backend Logs Should Contain Correlation Id    ${correlation_id}
