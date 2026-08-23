*** Test Cases ***
Check Idempotency
    ${idempotency_key}=    Set Variable    ${NONE}
    ${has_idempotency_key}=    Evaluate    $idempotency_key is not None
    Log To Console    Has IDK? ${has_idempotency_key}
    IF    ${has_idempotency_key}
        Log To Console    YES
    ELSE
        Log To Console    NO
    END
