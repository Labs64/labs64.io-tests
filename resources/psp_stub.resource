*** Settings ***
Documentation    Keywords for controlling and inspecting the external WireMock PSP stub.
Library          RequestsLibrary
Library          Collections
Library          OperatingSystem

*** Variables ***
${PSP_STUB_SESSION_ALIAS}              psp-stub
${PSP_STUB_BASE_URL}                   %{PSP_STUB_BASE_URL=http://localhost:8090}
${STRIPE_CHECKOUT_SESSIONS_API_PATH}    /v1/checkout/sessions
${PAYPAL_OAUTH_API_PATH}                /v1/oauth2/token
${PAYPAL_ORDERS_API_PATH}               /v2/checkout/orders
${PAYPAL_WEBHOOK_VERIFY_API_PATH}       /v1/notifications/verify-webhook-signature

*** Keywords ***
PSP Stub Should Be Available
    [Documentation]    Connect to the externally managed stub and fail when its required setup is absent.
    Create Session    ${PSP_STUB_SESSION_ALIAS}    ${PSP_STUB_BASE_URL}
    GET On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/health
    ...    expected_status=200

Reset PSP Stub Requests
    [Documentation]    Clear WireMock's request journal while keeping configured mappings.
    ${response}=    DELETE On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/requests
    ...    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    200

Reset PSP Stub State
    [Documentation]    Remove mappings and requests so every test can install its own isolated PSP contract.
    ${mappings_response}=    DELETE On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/mappings
    ...    expected_status=any
    Should Be Equal As Integers    ${mappings_response.status_code}    200
    Reset PSP Stub Requests

Register PSP Stub Mapping From File
    [Documentation]    Register one versioned WireMock mapping from a file visible to the Robot runner.
    [Arguments]    ${mapping_path}
    ${mapping_text}=    Get File    ${mapping_path}
    ${mapping}=    Evaluate    json.loads($mapping_text)    modules=json
    ${response}=    POST On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/mappings
    ...    json=${mapping}
    ...    expected_status=any
    ${created}=    Evaluate    $response.status_code in (200, 201)
    Should Be True    ${created}    WireMock did not register ${mapping_path}: ${response.text}

Register PSP Stub Mappings From Directory
    [Documentation]    Register all mappings matching a provider-specific file pattern in stable order.
    [Arguments]    ${mapping_directory}    ${pattern}=*.json
    @{mapping_files}=    List Files In Directory
    ...    ${mapping_directory}
    ...    pattern=${pattern}
    ...    absolute=${TRUE}
    Should Not Be Empty    ${mapping_files}    No PSP mappings matched ${mapping_directory}/${pattern}
    FOR    ${mapping_file}    IN    @{mapping_files}
        Register PSP Stub Mapping From File    ${mapping_file}
    END

Find Stripe Checkout Session Create Requests
    [Documentation]    Return WireMock journal entries matching Stripe's create-session API.
    ${matcher}=    Create Dictionary
    ...    method=POST
    ...    urlPath=${STRIPE_CHECKOUT_SESSIONS_API_PATH}
    ${response}=    POST On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/requests/find
    ...    json=${matcher}
    ...    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    200
    RETURN    ${response.json()}[requests]

Get Only Stripe Checkout Session Create Request
    [Documentation]    Return the single create-session request, failing on zero or duplicate PSP calls.
    ${requests}=    Find Stripe Checkout Session Create Requests
    Length Should Be    ${requests}    1
    RETURN    ${requests}[0]

Parse Stripe Form Request
    [Documentation]    Decode Stripe's application/x-www-form-urlencoded SDK request body.
    [Arguments]    ${request}
    ${form}=    Evaluate    urllib.parse.parse_qs($request["body"], keep_blank_values=True)    modules=urllib.parse
    RETURN    ${form}

Stripe Checkout Request Should Match Payment
    [Documentation]    Verify the material outbound SDK contract and return its callback URLs.
    [Arguments]    ${request}    ${transaction_id}    ${api_key}
    ${headers}=    Get From Dictionary    ${request}    headers
    ${authorization}=    Evaluate    next((v[0] if isinstance(v, list) else v) for k, v in $headers.items() if k.lower() == "authorization")
    ${stripe_idempotency_key}=    Evaluate    next((v[0] if isinstance(v, list) else v) for k, v in $headers.items() if k.lower() == "idempotency-key")
    Should Be Equal As Strings    ${authorization}    Bearer ${api_key}
    Should Be Equal As Strings    ${stripe_idempotency_key}    ${transaction_id}
    ${form}=    Parse Stripe Form Request    ${request}
    Should Be Equal As Strings    ${form}[mode][0]    payment
    Should Be Equal As Strings    ${form}[client_reference_id][0]    ${transaction_id}
    Should Be Equal As Strings    ${form}[metadata[paymentTransactionId]][0]    ${transaction_id}
    Should Be Equal As Strings    ${form}[payment_intent_data[metadata][paymentTransactionId]][0]    ${transaction_id}
    Should Be Equal As Strings    ${form}[line_items[0][price_data][currency]][0]    eur
    Should Be Equal As Integers    ${form}[line_items[0][price_data][unit_amount]][0]    100
    Should Be Equal As Integers    ${form}[line_items[0][quantity]][0]    1
    Should Be Equal As Strings    ${form}[customer_email][0]    payment-gateway-e2e@labs64.io
    ${success_url}=    Set Variable    ${form}[success_url][0]
    ${cancel_url}=    Set Variable    ${form}[cancel_url][0]
    Should Contain    ${success_url}    /providers/stripe/checkout-sessions/
    Should Contain    ${success_url}    stripeSessionId={CHECKOUT_SESSION_ID}
    Should Contain    ${cancel_url}    /providers/stripe/checkout-sessions/
    Should End With    ${cancel_url}    /cancel
    RETURN    ${success_url}    ${cancel_url}

Get Checkout Session Id From Provider Callback URL
    [Documentation]    Extract PG's checkout-session UUID from a generated provider callback URL.
    [Arguments]    ${callback_url}
    ${session_id}=    Evaluate    urllib.parse.urlparse($callback_url).path.split("/checkout-sessions/", 1)[1].split("/", 1)[0]    modules=urllib.parse
    RETURN    ${session_id}

Register Stripe Checkout Session Retrieval Stub
    [Documentation]    Add a per-test retrieve response tied to the real PG transaction ID.
    [Arguments]    ${stripe_session_id}    ${transaction_id}    ${payment_status}=paid    ${status}=complete
    ${metadata}=    Create Dictionary    paymentTransactionId=${transaction_id}
    ${response_body}=    Create Dictionary
    ...    id=${stripe_session_id}
    ...    object=checkout.session
    ...    client_reference_id=${transaction_id}
    ...    metadata=${metadata}
    ...    payment_intent=pi_test_psp_stub
    ...    payment_status=${payment_status}
    ...    status=${status}
    ${request_pattern}=    Create Dictionary
    ...    method=GET
    ...    urlPath=/v1/checkout/sessions/${stripe_session_id}
    ${response_headers}=    Create Dictionary    Content-Type=application/json
    ${response_definition}=    Create Dictionary
    ...    status=${200}
    ...    headers=${response_headers}
    ...    jsonBody=${response_body}
    ${mapping}=    Create Dictionary
    ...    name=Stripe - retrieve Checkout Session ${stripe_session_id}
    ...    priority=${1}
    ...    request=${request_pattern}
    ...    response=${response_definition}
    ${response}=    POST On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/mappings
    ...    json=${mapping}
    ...    expected_status=any
    ${created}=    Evaluate    $response.status_code in (200, 201)
    Should Be True    ${created}    WireMock did not register the Stripe retrieval mapping: ${response.text}

Stripe API Request Count Should Be
    [Documentation]    Assert an exact number of HTTP calls reached a Stripe API path.
    [Arguments]    ${method}    ${url_path}    ${expected_count}
    PSP API Request Count Should Be    ${method}    ${url_path}    ${expected_count}

PSP API Request Count Should Be
    [Documentation]    Assert an exact number of HTTP calls reached a PSP API path.
    [Arguments]    ${method}    ${url_path}    ${expected_count}
    ${matcher}=    Create Dictionary    method=${method}    urlPath=${url_path}
    ${response}=    POST On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/requests/count
    ...    json=${matcher}
    ...    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal As Integers    ${response.json()}[count]    ${expected_count}

Stripe Checkout Session Create Request Count Should Be
    [Documentation]    Assert how many real Stripe SDK create-session calls reached WireMock.
    [Arguments]    ${expected_count}
    Stripe API Request Count Should Be    POST    ${STRIPE_CHECKOUT_SESSIONS_API_PATH}    ${expected_count}

Find PSP API Requests
    [Documentation]    Return WireMock request-journal entries matching an HTTP method and path.
    [Arguments]    ${method}    ${url_path}
    ${matcher}=    Create Dictionary    method=${method}    urlPath=${url_path}
    ${response}=    POST On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/requests/find
    ...    json=${matcher}
    ...    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    200
    RETURN    ${response.json()}[requests]

Get Only PSP API Request
    [Documentation]    Return one matching PSP call, failing on zero or duplicate calls.
    [Arguments]    ${method}    ${url_path}
    ${requests}=    Find PSP API Requests    ${method}    ${url_path}
    Length Should Be    ${requests}    1
    RETURN    ${requests}[0]

Get PSP Request Header
    [Documentation]    Read a recorded request header case-insensitively and normalize list values.
    [Arguments]    ${request}    ${header_name}
    ${headers}=    Get From Dictionary    ${request}    headers
    ${namespace}=    Create Dictionary    headers=${headers}    header_name=${header_name}
    ${value}=    Evaluate
    ...    next((v[0] if isinstance(v, list) else v) for k, v in headers.items() if k.lower() == header_name.lower())
    ...    namespace=${namespace}
    RETURN    ${value}

Parse JSON PSP Request
    [Documentation]    Decode a recorded PSP request JSON body.
    [Arguments]    ${request}
    ${body}=    Evaluate    json.loads($request["body"])    modules=json
    RETURN    ${body}

PayPal OAuth Request Should Match Credentials
    [Documentation]    Verify PayPal SDK client-credentials authentication.
    [Arguments]    ${request}    ${expected_basic_authorization}
    ${authorization}=    Get PSP Request Header    ${request}    Authorization
    Should Be Equal As Strings    ${authorization}    Basic ${expected_basic_authorization}
    ${form}=    Evaluate    urllib.parse.parse_qs($request["body"], keep_blank_values=True)    modules=urllib.parse
    Should Be Equal As Strings    ${form}[grant_type][0]    client_credentials

PayPal Create Order Request Should Match Payment
    [Documentation]    Verify material PayPal order fields and return its generated callback URLs.
    [Arguments]    ${request}    ${payment_id}    ${transaction_id}    ${access_token}
    ${authorization}=    Get PSP Request Header    ${request}    Authorization
    ${paypal_request_id}=    Get PSP Request Header    ${request}    PayPal-Request-Id
    ${prefer}=    Get PSP Request Header    ${request}    Prefer
    Should Be Equal As Strings    ${authorization}    Bearer ${access_token}
    Should Be Equal As Strings    ${paypal_request_id}    ${transaction_id}
    Should Be Equal As Strings    ${prefer}    return=representation
    ${body}=    Parse JSON PSP Request    ${request}
    Should Be Equal As Strings    ${body}[intent]    CAPTURE
    Should Be Equal As Strings    ${body}[purchase_units][0][reference_id]    ${transaction_id}
    Should Be Equal As Strings    ${body}[purchase_units][0][custom_id]    ${payment_id}
    Should Be Equal As Strings    ${body}[purchase_units][0][invoice_id]    ${transaction_id}
    Should Be Equal As Strings    ${body}[purchase_units][0][amount][currency_code]    EUR
    Should Be Equal As Strings    ${body}[purchase_units][0][amount][value]    1.00
    Should Be Equal As Strings    ${body}[purchase_units][0][amount][breakdown][item_total][value]    1.00
    Should Be Equal As Strings    ${body}[purchase_units][0][items][0][name]    Payment Gateway E2E item
    Should Be Equal As Strings    ${body}[purchase_units][0][items][0][unit_amount][value]    1.00
    Should Be Equal As Strings    ${body}[purchase_units][0][items][0][quantity]    1
    Should Be Equal As Strings    ${body}[purchase_units][0][items][0][category]    DIGITAL_GOODS
    Should Be Equal As Strings    ${body}[payer][email_address]    payment-gateway-e2e@labs64.io
    Should Be Equal As Strings    ${body}[application_context][shipping_preference]    NO_SHIPPING
    Should Be Equal As Strings    ${body}[application_context][user_action]    PAY_NOW
    ${return_url}=    Set Variable    ${body}[application_context][return_url]
    ${cancel_url}=    Set Variable    ${body}[application_context][cancel_url]
    Should Contain    ${return_url}    /providers/paypal/checkout-sessions/
    Should End With    ${return_url}    /return
    Should Contain    ${cancel_url}    /providers/paypal/checkout-sessions/
    Should End With    ${cancel_url}    /cancel
    RETURN    ${return_url}    ${cancel_url}

PayPal Capture Request Should Match Transaction
    [Documentation]    Verify PayPal capture authentication and idempotency contract.
    [Arguments]    ${request}    ${transaction_id}    ${access_token}
    ${authorization}=    Get PSP Request Header    ${request}    Authorization
    ${paypal_request_id}=    Get PSP Request Header    ${request}    PayPal-Request-Id
    ${prefer}=    Get PSP Request Header    ${request}    Prefer
    Should Be Equal As Strings    ${authorization}    Bearer ${access_token}
    Should Be Equal As Strings    ${paypal_request_id}    ${transaction_id}
    Should Be Equal As Strings    ${prefer}    return=representation

PayPal Webhook Verification Request Should Match
    [Documentation]    Verify the provider forwards PayPal headers, webhook ID, and full event for verification.
    [Arguments]    ${request}    ${event_id}    ${event_type}    ${webhook_id}    ${transmission_signature}
    ${authorization}=    Get PSP Request Header    ${request}    Authorization
    Should Be Equal As Strings    ${authorization}    Bearer paypal-access-token
    ${body}=    Parse JSON PSP Request    ${request}
    Should Be Equal As Strings    ${body}[auth_algo]    SHA256withRSA
    Should Be Equal As Strings    ${body}[cert_url]    https://api.paypal.test/certs/psp-stub.pem
    Should Be Equal As Strings    ${body}[transmission_id]    transmission-psp-stub
    Should Be Equal As Strings    ${body}[transmission_sig]    ${transmission_signature}
    Should Be Equal As Strings    ${body}[webhook_id]    ${webhook_id}
    Should Be Equal As Strings    ${body}[webhook_event][id]    ${event_id}
    Should Be Equal As Strings    ${body}[webhook_event][event_type]    ${event_type}

Register PayPal Capture Error Stub
    [Documentation]    Override one PayPal order capture with an upstream HTTP 500 response.
    [Arguments]    ${order_id}
    ${request_pattern}=    Create Dictionary
    ...    method=POST
    ...    urlPath=/v2/checkout/orders/${order_id}/capture
    ${response_headers}=    Create Dictionary    Content-Type=application/json
    ${error_body}=    Create Dictionary
    ...    name=INTERNAL_SERVER_ERROR
    ...    message=Stubbed PayPal capture failure
    ...    debug_id=paypal-capture-error
    ${response_definition}=    Create Dictionary
    ...    status=${500}
    ...    headers=${response_headers}
    ...    jsonBody=${error_body}
    ${mapping}=    Create Dictionary
    ...    name=PayPal - capture order upstream error
    ...    priority=${1}
    ...    request=${request_pattern}
    ...    response=${response_definition}
    ${response}=    POST On Session
    ...    ${PSP_STUB_SESSION_ALIAS}
    ...    /__admin/mappings
    ...    json=${mapping}
    ...    expected_status=any
    ${created}=    Evaluate    $response.status_code in (200, 201)
    Should Be True    ${created}    WireMock did not register the PayPal capture error mapping: ${response.text}
