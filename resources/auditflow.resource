*** Settings ***
Documentation    AuditFlow-specific keywords and variables.
...              AuditFlow's public contract is ``POST /audit/publish`` and its batch form
...              ``POST /audit/publish/batch`` (see
...              auditflow-api/src/main/resources/openapi/openapi-audit-v1.yaml). AuditFlow is a
...              router, not a system of record — it has no query API of its own, so these tests
...              only ever assert against the publish operations.
Library          RequestsLibrary
Library          Collections
Library          String
Resource         common.resource

*** Variables ***
${AUDITFLOW_SESSION_ALIAS}    auditflow
${AUDITFLOW_WRITE_SCOPE}      audit-event:write
${AUDITFLOW_GATEWAY_PATH}     /auditflow/api/v1/audit/publish

# Dedicated regression-test tenants (item 12), stamped by provider-neutral personas
# `auditflow-regression` / `auditflow-regression-quota` (never t_mock, which every
# other suite shares). Both mock OIDC and Keycloak implement the same persona contract.
${AUDITFLOW_REGRESSION_SCOPE}          auditflow-regression
${AUDITFLOW_REGRESSION_QUOTA_SCOPE}    auditflow-regression-quota
${AUDITFLOW_REGRESSION_SESSION}          auditflow-regression
${AUDITFLOW_REGRESSION_QUOTA_SESSION}    auditflow-regression-quota

# The unprovisioned secondary-tenant persona (t_mock_2): authenticated and correctly scoped, but no
# tenant record exists for it locally, so the ingest gate must refuse it with TENANT_NOT_PROVISIONED.
${AUDITFLOW_TENANT2_SCOPE}      auditflow-tenant-2
${AUDITFLOW_TENANT2_SESSION}    auditflow-tenant-2

# Response bodies of an error must never carry implementation detail (stack frames, framework or JDK
# class names). Deliberately narrow: it matches a leaked stack trace, not a validation message.
${INTERNALS_LEAK_PATTERN}    (?i)(\\sat\\s[\\w.$]+\\([\\w.]+:\\d+\\)|java\\.(lang|util|io)\\.|org\\.springframework|caused by|NullPointerException)

# Local-k8s-only: AuditFlow's own backend deployment name for kubectl log corroboration (see
# AGENTS.md "Local-only pod-log corroboration"). Shared namespace/authgateway deployment vars
# live in common.resource. Never used unless `Local Kubernetes Available` is true.
${AUDITFLOW_K8S_DEPLOYMENT}      %{AUDITFLOW_K8S_DEPLOYMENT=labs64io-auditflow}

*** Keywords ***
Create AuditFlow Session
    [Documentation]    Open a session authorized with the ``audit-event:write`` scope
    ...                required by POST /audit/publish.
    Create Session With Scope    ${AUDITFLOW_SESSION_ALIAS}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_WRITE_SCOPE}

Create Unauthenticated AuditFlow Session
    [Documentation]    Open an unauthenticated HTTP session pointed at the AuditFlow base URL.
    Create Unauthenticated Session    ${AUDITFLOW_SESSION_ALIAS}    ${AUDITFLOW_BASE_URL}

Publish Audit Event
    [Documentation]    POST an audit-event object to /audit/publish on the given session alias.
    [Arguments]    ${event}    ${alias}=${AUDITFLOW_SESSION_ALIAS}
    ${correlation_id}=    Get From Dictionary    ${event}    correlationId    ${EMPTY}
    ${headers}=    Create Dictionary    ${CORRELATION_ID_HEADER}=${correlation_id}
    ${response}=    POST On Session
    ...    ${alias}
    ...    /audit/publish
    ...    json=${event}
    ...    headers=${headers}
    ...    expected_status=any
    RETURN    ${response}

Publish Audit Event Batch
    [Documentation]    POST ``{"events": [...]}`` to /audit/publish/batch on the given session alias.
    [Arguments]    ${events}    ${alias}=${AUDITFLOW_SESSION_ALIAS}
    ${body}=    Create Dictionary    events=${events}
    ${response}=    POST On Session
    ...    ${alias}
    ...    /audit/publish/batch
    ...    json=${body}
    ...    expected_status=any
    RETURN    ${response}

Build Valid Audit Event
    [Documentation]    Return a well-formed audit-event dict satisfying the AuditEvent schema
    ...                (required: eventType, sourceSystem).
    [Arguments]    ${correlation_id}
    ${extra}=    Create Dictionary    userId=test-suite    action_name=test.event    action_status=SUCCESS
    ${event}=    Create Dictionary
    ...    eventType=api.call
    ...    sourceSystem=labs64.io-tests
    ...    correlationId=${correlation_id}
    ...    extra=${extra}
    RETURN    ${event}

Build Audit Event With Tenant
    [Documentation]    Return a well-formed audit-event dict carrying an explicit client-supplied
    ...                ``tenantId`` — used by tenant-isolation tests to prove the gateway-derived
    ...                tenant is authoritative and the payload value is ignored.
    [Arguments]    ${correlation_id}    ${tenant_id}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    Set To Dictionary    ${event}    tenantId=${tenant_id}
    RETURN    ${event}

Generate Spoof Tenant Id
    [Documentation]    Return a unique, schema-valid tenantId (``spoofed-<hex>``) that no
    ...                environment ever provisions — its uniqueness makes log-absence checks
    ...                attributable to a single test call.
    ${uuid}=    Evaluate    __import__('uuid').uuid4().hex[:12]
    RETURN    spoofed-${uuid}

Build Invalid Audit Event Missing Required Field
    [Documentation]    Return an audit-event dict missing the required ``eventType`` field,
    ...                to assert the API rejects it with HTTP 400.
    ${event}=    Create Dictionary    sourceSystem=labs64.io-tests
    RETURN    ${event}

Authgateway Logs Should Show No-Token Rejection For Publish
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authgateway Logs Should
    ...                Show No-Token Rejection` fixed to POST /audit/publish.
    [Arguments]    ${since}=90s
    Authgateway Logs Should Show No-Token Rejection    POST    ${AUDITFLOW_GATEWAY_PATH}    ${since}

Authgateway Logs Should Show Authz Decision For Publish
    [Documentation]    Local-k8s-only. Thin wrapper over the generic `Authgateway Logs Should
    ...                Show Authz Decision` fixed to AuditFlow's publishEvent operation.
    [Arguments]    ${outcome}    ${since}=90s
    Authgateway Logs Should Show Authz Decision    auditflow    publishEvent    ${outcome}    ${since}

AuditFlow Backend Logs Should Contain Correlation Id
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs contain the
    ...                successful publish message for the given correlation id — proving the
    ...                event was delivered past the gateway and handed to the output binding,
    ...                not merely accepted by authz or request logging.
    ...                Polls within a bounded window: the first service-to-service publication
    ...                may initialize OAuth and authorization clients before asynchronous delivery.
    [Arguments]    ${correlation_id}    ${since}=90s
    Wait Until Keyword Succeeds    20s    1s
    ...    Pod Logs Should Confirm Published Event    ${correlation_id}    ${since}

Pod Logs Should Confirm Published Event
    [Documentation]    Single-attempt helper for `AuditFlow Backend Logs Should Contain
    ...                Correlation Id`. Filters by the unique correlation id before checking the
    ...                publish-success message, so an earlier request/authz log cannot satisfy it.
    [Arguments]    ${correlation_id}    ${since}
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    ${event_logs}=    Get Lines Containing String    ${logs}    ${correlation_id}
    Should Contain    ${event_logs}    Audit event published successfully
    ...    msg=AuditFlow did not confirm publishing the event with correlationId '${correlation_id}'.

AuditFlow Backend Logs Should Not Mention Tenant
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs never mention
    ...                the given (unique, spoofed) tenantId in any routing/quarantine line —
    ...                proving the gateway-stamped tenant, not the client payload, drove
    ...                gating and routing. Callers must first sync on the same event's
    ...                correlationId so the pipeline has demonstrably already run.
    [Arguments]    ${tenant_id}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    Should Not Contain    ${logs}    '${tenant_id}'
    ...    msg=Spoofed client-supplied tenantId '${tenant_id}' appeared in AuditFlow backend logs — payload tenantId leaked past the authoritative gateway stamping.

AuditFlow Backend Logs Should Not Contain Correlation Id
    [Documentation]    Local-k8s-only. Assert the AuditFlow backend's recent logs do NOT
    ...                contain the given correlation id — proving a denied-at-the-edge request
    ...                never reached the backend at all.
    [Arguments]    ${correlation_id}    ${since}=90s
    ${logs}=    Fetch Recent Pod Logs    ${LABS64IO_K8S_NAMESPACE}    ${AUDITFLOW_K8S_DEPLOYMENT}    ${since}
    Should Not Contain    ${logs}    "correlationId": "${correlation_id}"
    ...    msg=Denied request's correlationId '${correlation_id}' unexpectedly reached the AuditFlow backend.

Create Regression Session
    [Documentation]    Open a session for the dedicated t_regression tenant (item 12: pipeline
    ...                routing, condition operators, secretRef resolution). Never t_mock —
    ...                this tenant's pipelines are deliberately failing probes, isolated so
    ...                they cannot affect any other suite.
    Create Session With Scope    ${AUDITFLOW_REGRESSION_SESSION}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_REGRESSION_SCOPE}

Create Regression Quota Session
    [Documentation]    Open a session for the dedicated t_regression_quota tenant (item 12:
    ...                quota enforcement) — provisioned with a tiny rateLimitPerSec/burst so a
    ...                handful of rapid publishes deterministically trips 429.
    Create Session With Scope    ${AUDITFLOW_REGRESSION_QUOTA_SESSION}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_REGRESSION_QUOTA_SCOPE}

Build Probe Audit Event
    [Documentation]    Return an audit-event whose `extra.op`/`extra.value` (and, for the
    ...                match:any pipeline, `extra.op_any`) drive exactly one t_regression probe
    ...                pipeline's condition — see values.local.yaml's `t_regression` pipeline
    ...                comment for the discriminator scheme. Pass ``${EMPTY}`` for ``value`` to
    ...                omit `extra.value` entirely (the exists/notExists negative cases).
    [Arguments]    ${correlation_id}    ${op}    ${value}=${EMPTY}    ${op_any}=${EMPTY}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    Set To Dictionary    ${event}[extra]    op=${op}
    IF    "${value}" != "${EMPTY}"
        Set To Dictionary    ${event}[extra]    value=${value}
    END
    IF    "${op_any}" != "${EMPTY}"
        Set To Dictionary    ${event}[extra]    op_any=${op_any}
    END
    RETURN    ${event}

Get DLQ Message Count
    [Documentation]    GET /actuator/dlq/<tenantId> and return the tenant-scoped, non-destructive
    ...                message count (every message is peeked then nacked back — inspection never
    ...                consumes). Uses the caller's own base session so the request goes through
    ...                the gateway edge, matching every other assertion in this suite.
    [Arguments]    ${alias}    ${tenant_id}
    ${response}=    GET On Session    ${alias}    /actuator/dlq/${tenant_id}    expected_status=200
    RETURN    ${response.json()}[messageCount]

Get DLQ Entries
    [Documentation]    GET /actuator/dlq/<tenantId>?limit=<limit>[&pipeline=<name>] and return the tenant's
    ...                entries (an order is not guaranteed). Each is a dict with ``eventId``, ``pipeline``,
    ...                ``reason``, ``attempts``, ``lastError``, ``event`` and, for a pipeline with steps that
    ...                finished some before failing, ``stepsDone``. Non-destructive, like the count.
    [Arguments]    ${alias}    ${tenant_id}    ${pipeline}=${EMPTY}    ${limit}=200
    ${params}=    Create Dictionary    limit=${limit}
    IF    "${pipeline}" != "${EMPTY}"
        Set To Dictionary    ${params}    pipeline=${pipeline}
    END
    ${response}=    GET On Session    ${alias}    /actuator/dlq/${tenant_id}    params=${params}    expected_status=200
    RETURN    ${response.json()}[entries]

DLQ Entry For Correlation Id
    [Documentation]    The tenant's DLQ entry of ``${pipeline}`` whose event carries ``${correlation_id}``, or fail
    ...                after ``${timeout}``. Polls: delivery is asynchronous (broker, then a failing sink, then the DLQ).
    [Arguments]    ${alias}    ${tenant_id}    ${pipeline}    ${correlation_id}    ${timeout}=30s
    ${entry}=    Wait Until Keyword Succeeds    ${timeout}    1s
    ...    Find DLQ Entry    ${alias}    ${tenant_id}    ${pipeline}    ${correlation_id}
    RETURN    ${entry}

Find DLQ Entry
    [Documentation]    Single-attempt helper for `DLQ Entry For Correlation Id`.
    [Arguments]    ${alias}    ${tenant_id}    ${pipeline}    ${correlation_id}
    ${entries}=    Get DLQ Entries    ${alias}    ${tenant_id}    ${pipeline}
    FOR    ${entry}    IN    @{entries}
        IF    "${entry}[event][correlationId]" == "${correlation_id}"    RETURN    ${entry}
    END
    ${count}=    Get Length    ${entries}
    Fail    No DLQ entry of pipeline '${pipeline}' for correlation id '${correlation_id}' yet (${count} entries of that pipeline).

Wait Until DLQ Count At Least
    [Documentation]    Poll GET /actuator/dlq/<tenantId> until messageCount reaches at least
    ...                ``${minimum}``, or fail after ``${timeout}``. Delivery is async (broker +
    ...                retry/backoff before a permanently-failing pipeline reaches the DLQ), so a
    ...                single immediate GET would be racy.
    [Arguments]    ${alias}    ${tenant_id}    ${minimum}    ${timeout}=30s
    Wait Until Keyword Succeeds    ${timeout}    1s
    ...    DLQ Count Should Be At Least    ${alias}    ${tenant_id}    ${minimum}

DLQ Count Should Be At Least
    [Documentation]    Single-attempt helper for `Wait Until DLQ Count At Least`.
    [Arguments]    ${alias}    ${tenant_id}    ${minimum}
    ${count}=    Get DLQ Message Count    ${alias}    ${tenant_id}
    Should Be True    ${count} >= ${minimum}
    ...    msg=Expected DLQ count for tenant '${tenant_id}' to reach at least ${minimum}, got ${count}.
    RETURN    ${count}

Replay DLQ
    [Documentation]    POST /actuator/dlq/<tenantId> (replay). Draining and republishing happens
    ...                synchronously inside this call (each message is forwarded then acked
    ...                before the next `basicGet`), so ``retriedCount`` in the response already
    ...                reflects the full drain by the time this keyword returns — no polling
    ...                needed to observe it.
    [Arguments]    ${alias}    ${tenant_id}
    ${response}=    POST On Session    ${alias}    /actuator/dlq/${tenant_id}    expected_status=200
    RETURN    ${response.json()}

Purge DLQ
    [Documentation]    DELETE /actuator/dlq/<tenantId>[?pipeline=<name>] — discard this tenant's DLQ
    ...                messages outright (no replay). Tenant-scoped like inspect/replay: another
    ...                tenant's messages are never touched. With ``${pipeline}`` only that pipeline's
    ...                entries are discarded.
    [Arguments]    ${alias}    ${tenant_id}    ${pipeline}=${EMPTY}
    ${params}=    Create Dictionary
    IF    "${pipeline}" != "${EMPTY}"
        Set To Dictionary    ${params}    pipeline=${pipeline}
    END
    ${response}=    DELETE On Session    ${alias}    /actuator/dlq/${tenant_id}    params=${params}    expected_status=200
    RETURN    ${response.json()}

Create Regression Session With Empty DLQ
    [Documentation]    Suite setup for every suite that asserts on t_regression's DLQ *count*.
    ...                Those assertions are before/after deltas, so they are only sound when
    ...                nothing else is queued or in flight. t_regression's pipelines are
    ...                deliberately-failing probes and nothing ever drains them, so without this
    ...                the backlog grows every run until (a) a replay's round-trip outruns its
    ...                settle window and (b) the stragglers land inside the next suite's
    ...                measurement window — which is exactly how dlq_replay and pipeline_routing
    ...                started failing together. Purging at setup bounds the backlog to what the
    ...                suite itself produces.
    Create Regression Session
    Purge DLQ    ${AUDITFLOW_REGRESSION_SESSION}    t_regression

Build Oversized Audit Event
    [Documentation]    Return an audit-event dict with a payload exceeding 2MB to test size limits.
    [Arguments]    ${correlation_id}
    ${event}=    Build Valid Audit Event    ${correlation_id}
    # Create a 15MB string (15,000,000 characters)
    ${large_string}=    Evaluate    'x' * 15000000
    Set To Dictionary    ${event}    oversized_field=${large_string}
    RETURN    ${event}

Create Secondary Tenant Session
    [Documentation]    Open a session for the unprovisioned t_mock_2 tenant persona (see
    ...                ``${AUDITFLOW_TENANT2_SCOPE}``): a valid, well-scoped token whose tenant has no
    ...                tenant record, i.e. the ingest gate's refusal path.
    Create Session With Scope    ${AUDITFLOW_TENANT2_SESSION}    ${AUDITFLOW_BASE_URL}    ${AUDITFLOW_TENANT2_SCOPE}

Send Raw Request
    [Documentation]    Send ``${method} ${path}`` on the given session with an arbitrary body and
    ...                Content-Type, for requests the JSON helpers cannot express: a wrong or missing
    ...                Content-Type, a malformed or non-UTF-8 body, an undeclared HTTP method. Pass
    ...                ``${NONE}`` as the Content-Type to send none (it also drops the session's
    ...                default). ``${headers}`` adds or overrides further request headers. Never
    ...                raises on the status: the caller asserts it.
    [Arguments]    ${alias}    ${method}    ${path}    ${body}=${NONE}    ${content_type}=application/json
    ...            ${headers}=${NONE}
    ${request_headers}=    Create Dictionary    Content-Type=${content_type}
    IF    $headers is not None
        Set To Dictionary    ${request_headers}    &{headers}
    END
    ${response}=    Run Keyword    ${method} On Session
    ...    ${alias}    ${path}    data=${body}    headers=${request_headers}    expected_status=any
    RETURN    ${response}

Get UTC Timestamp
    [Documentation]    The current UTC time plus ``${offset_seconds}`` (negative for the past) as an
    ...                ISO-8601 string, to build an ``eventTime`` relative to now.
    [Arguments]    ${offset_seconds}=0
    ${timestamp}=    Evaluate
    ...    (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=${offset_seconds})).strftime('%Y-%m-%dT%H:%M:%SZ')
    ...    modules=datetime
    RETURN    ${timestamp}

Timestamp Should Be Recent
    [Documentation]    Assert an ISO-8601 timestamp (any fractional precision) parses and lies within
    ...                ``${tolerance_seconds}`` of the test host's clock. The tolerance only has to
    ...                absorb clock skew between this host and the cluster, never test duration.
    [Arguments]    ${timestamp}    ${tolerance_seconds}=600
    ${delta}=    Evaluate
    ...    abs((datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(re.sub(r'(\\.\\d{6})\\d+', r'\\1', $timestamp).replace('Z', '+00:00'))).total_seconds())
    ...    modules=datetime, re
    Should Be True    ${delta} <= ${tolerance_seconds}
    ...    msg=Timestamp '${timestamp}' is ${delta}s away from now (allowed: ${tolerance_seconds}s).

Should Be A UUID
    [Documentation]    Assert the value is a canonical UUID string.
    [Arguments]    ${value}
    Should Match Regexp    ${value}    (?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$
    ...    msg='${value}' is not a UUID.

Response Should Be Error Response
    [Documentation]    Assert the response is the contract's ``ErrorResponse``: the expected HTTP
    ...                status, a JSON body with the expected ``code`` and a non-empty ``message`` and
    ...                ``timestamp``, and nothing of the implementation in it.
    [Arguments]    ${response}    ${status}    ${code}
    Response Status Should Be    ${response}    ${status}
    ${content_type}=    Get From Dictionary    ${response.headers}    Content-Type    ${EMPTY}
    Should Contain    ${content_type}    application/json
    ...    msg=Error response is not JSON (Content-Type '${content_type}'). Body: ${response.text}
    ${body}=    Set Variable    ${response.json()}
    Should Be Equal As Strings    ${body}[code]    ${code}
    ...    msg=Expected error code ${code} but got ${body}[code]. Body: ${response.text}
    Should Not Be Empty    ${body}[message]
    Should Not Be Empty    ${body}[timestamp]
    Response Should Not Leak Internals    ${response}

Response Should Not Leak Internals
    [Documentation]    Assert the body carries no stack frame and no framework or JDK class name.
    [Arguments]    ${response}
    Should Not Match Regexp    ${response.text}    ${INTERNALS_LEAK_PATTERN}
    ...    msg=Response leaks implementation detail: ${response.text}

Batch Response Should Be Consistent
    [Documentation]    Assert a processed batch (HTTP 200) is internally consistent and return its
    ...                body: exactly one result per request event, ``index`` equal to the position,
    ...                ``acceptedCount``/``rejectedCount`` equal to the ACCEPTED/REJECTED results,
    ...                and every REJECTED result carrying an error code.
    [Arguments]    ${response}    ${expected_total}
    Response Status Should Be    ${response}    200
    ${body}=    Set Variable    ${response.json()}
    ${results}=    Set Variable    ${body}[results]
    Length Should Be    ${results}    ${expected_total}
    ${accepted}=    Evaluate    len([r for r in $results if r['status'] == 'ACCEPTED'])
    ${rejected}=    Evaluate    len([r for r in $results if r['status'] == 'REJECTED'])
    Should Be Equal As Integers    ${body}[acceptedCount]    ${accepted}
    Should Be Equal As Integers    ${body}[rejectedCount]    ${rejected}
    ${total}=    Evaluate    ${accepted} + ${rejected}
    Should Be Equal As Integers    ${total}    ${expected_total}
    FOR    ${position}    ${result}    IN ENUMERATE    @{results}
        Should Be Equal As Integers    ${result}[index]    ${position}
        IF    "${result}[status]" == "REJECTED"
            Should Not Be Empty    ${result}[error][code]
        END
    END
    RETURN    ${body}

Build Valid Audit Event Batch
    [Documentation]    ``${count}`` well-formed events with distinct correlation ids derived from one
    ...                fresh prefix, as the list a batch request carries.
    [Arguments]    ${count}
    ${prefix}=    Generate Correlation ID
    ${events}=    Evaluate
    ...    [{'eventType': 'api.call', 'sourceSystem': 'labs64.io-tests', 'correlationId': '%s-%d' % ($prefix, i)} for i in range(int($count))]
    RETURN    ${events}

Get DLQ Info
    [Documentation]    GET /actuator/dlq/<tenantId>[?limit=<limit>][&pipeline=<name>] and return the whole
    ...                JSON body: the counts (``messageCount``, ``byPipeline``, ``byReason``,
    ...                ``legacyMessageCount``), and ``entries`` only when a ``limit`` was given.
    [Arguments]    ${alias}    ${tenant_id}    ${limit}=${EMPTY}    ${pipeline}=${EMPTY}
    ${params}=    Create Dictionary
    IF    "${limit}" != "${EMPTY}"
        Set To Dictionary    ${params}    limit=${limit}
    END
    IF    "${pipeline}" != "${EMPTY}"
        Set To Dictionary    ${params}    pipeline=${pipeline}
    END
    ${response}=    GET On Session    ${alias}    /actuator/dlq/${tenant_id}    params=${params}    expected_status=200
    RETURN    ${response.json()}
