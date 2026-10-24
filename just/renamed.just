# Recipes that were renamed. Each old name fails and names its replacement, so muscle memory and old scripts
# get a clear message instead of a different behaviour (docs/justfiles.md in labs64.io-workspace).
# Remove this file after 2027-01-31.

# Fail with the new name of a renamed recipe
[private]
_renamed old +new:
    @echo 'error: `just {{old}}` is now `just {{new}}` (see just/renamed.just).' >&2 && exit 1

[private]
auth *args:
    @just _renamed auth test-auth

[private]
install *args:
    @just _renamed install install-venv

[private]
local-k8s *args:
    @just _renamed local-k8s test-local-k8s

[private]
log *args:
    @just _renamed log open-log

[private]
psp *args:
    @just _renamed psp test-psp

[private]
psp-stub-down *args:
    @just _renamed psp-stub-down stop-wiremock

[private]
psp-stub-logs *args:
    @just _renamed psp-stub-logs show-wiremock-logs

[private]
psp-stub-up *args:
    @just _renamed psp-stub-up start-wiremock

[private]
report *args:
    @just _renamed report open-report

[private]
test-all *args:
    @just _renamed test-all test

[private]
test-down *args:
    @just _renamed test-down disable-psp-stub

[private]
test-status *args:
    @just _renamed test-status show-psp-stub

[private]
test-up *args:
    @just _renamed test-up enable-psp-stub
