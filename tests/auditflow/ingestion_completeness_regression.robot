*** Settings ***
Documentation    AuditFlow ingestion-completeness regression — P0 blocker for the dead-DLQ
...              silent-audit-loss defect class.
...
...              All assertions go through the API edge only (no RabbitMQ / infra access):
...              submit a batch via the ingestion endpoint, wait for the async pipeline to
...              settle, then verify every event is retrievable via the query API.
...              A count mismatch means events were accepted at the edge but silently dropped
...              — the exact dead-DLQ failure mode.
Resource         ../../resources/auditflow.resource
Suite Setup      Create AuditFlow Session
Suite Teardown   Delete All Sessions

*** Variables ***
${BATCH_SIZE}              50
${PIPELINE_SETTLE_SECS}    5

*** Test Cases ***
All Submitted Audit Events Must Be Retrievable — None Silently Dropped
    [Documentation]    Submit a batch of ${BATCH_SIZE} events with a unique correlation ID,
    ...                wait ${PIPELINE_SETTLE_SECS} s for the async pipeline to settle, then
    ...                assert that the query API returns exactly ${BATCH_SIZE} events.
    ...
    ...                Failure indicates the dead-DLQ / silent-loss regression is active:
    ...                events were accepted at the edge but never became queryable.
    [Tags]    auditflow    regression    critical    p0-blocker
    ${correlation_id}=    Generate Correlation ID
    ${events}=            Build Event Batch    ${correlation_id}    ${BATCH_SIZE}

    # Step 1 — submit the batch and confirm acceptance
    ${ingest_response}=    Submit Audit Event Batch    ${events}
    Response Status Should Be    ${ingest_response}    202

    # Step 2 — allow the async ingestion pipeline to settle
    Sleep    ${PIPELINE_SETTLE_SECS}s
    ...    reason=Waiting for async pipeline to process batch (correlation_id=${correlation_id})

    # Step 3 — query and assert completeness
    ${query_response}=    Query Events By Correlation ID    ${correlation_id}
    Response Status Should Be    ${query_response}    200
    ${json}=    Set Variable    ${query_response.json()}
    ${total_count}=    Convert To Integer    ${json}[totalCount]
    Should Be Equal As Integers    ${total_count}    ${BATCH_SIZE}
    ...    msg=Expected ${BATCH_SIZE} events to be queryable but found ${total_count}. Events were accepted at the ingestion edge but silently lost before becoming queryable — dead-DLQ regression detected.

Partial Batch Loss Is Detected
    [Documentation]    Submit a batch and assert the total count is not less than expected.
    ...                Even one missing event constitutes a silent-loss failure.
    [Tags]    auditflow    regression    critical    p0-blocker
    ${correlation_id}=    Generate Correlation ID
    ${events}=            Build Event Batch    ${correlation_id}    ${BATCH_SIZE}

    ${ingest_response}=    Submit Audit Event Batch    ${events}
    Response Status Should Be    ${ingest_response}    202
    Sleep    ${PIPELINE_SETTLE_SECS}s

    ${query_response}=    Query Events By Correlation ID    ${correlation_id}
    Response Status Should Be    ${query_response}    200
    ${json}=    Set Variable    ${query_response.json()}
    ${total_count}=    Convert To Integer    ${json}[totalCount]
    Should Be True    ${total_count} >= ${BATCH_SIZE}
    ...    msg=Only ${total_count} of ${BATCH_SIZE} submitted events are queryable — partial silent loss detected (dead-DLQ regression).

Empty Batch Is Rejected With 400
    [Documentation]    An empty event batch must be rejected immediately with HTTP 400
    ...                rather than being silently accepted and lost.
    [Tags]    auditflow    regression    error-handling
    ${empty_batch}=    Create List
    ${response}=    Submit Audit Event Batch    ${empty_batch}
    Response Status Should Be    ${response}    400

Event Batch With Invalid Schema Is Rejected With 400
    [Documentation]    A batch containing structurally invalid event objects (missing required
    ...                fields) must be rejected with HTTP 400 at the ingestion edge, not
    ...                accepted and silently dropped downstream.
    [Tags]    auditflow    regression    error-handling    contract
    ${bad_event}=    Create Dictionary    unexpectedField=oops
    ${bad_batch}=    Create List    ${bad_event}
    ${response}=    Submit Audit Event Batch    ${bad_batch}
    Response Status Should Be    ${response}    400
