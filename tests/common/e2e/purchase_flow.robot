*** Settings ***
Documentation    Cross-service end-to-end functional flows.
...              These flows test the interactions between Checkout, Payment Gateway, and Auditflow.
Resource         ../../resources/checkout.resource
Resource         ../../resources/payment_gateway.resource
Resource         ../../resources/auditflow.resource
Suite Teardown   Delete All Sessions

*** Test Cases ***
Complete end-to-end purchase flow
    [Documentation]    Verify customer creation, purchase order, checkout session, and audit event emission.
    [Tags]    e2e    regression
    # TODO: Implement the full E2E flow once Checkout and Payment Gateway mocks are finalized.
    # 1. Create a Customer (Checkout API)
    # 2. Create a Purchase Order (Checkout API)
    # 3. Initiate a Checkout (Payment Gateway API)
    # 4. Verify the Audit Event was successfully emitted and stored (Auditflow API).
    Skip    Skipping E2E test kickstart stub.
