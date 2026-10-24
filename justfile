# Labs64.IO :: Tests — Root justfile
#
# Prerequisites: just, python3, a running Labs64.IO stack reachable through its gateway
# edge (from the workspace: `just up`; see labs64.io-helm-charts/DEVELOPERS.md).
#
# Quick start (`just` lists everything, by group):
#   just smoke              → fast PR-gating subset, all modules
#   just regression         → full nightly-shape regression, excluding flaky
#   just test               → regression + isolated PSP-stub phase, with automatic cleanup
#   just test-module NAME   → everything for one module, e.g. `just test-module auditflow`
#   just open-log           → serve the most recent run's log.html (read this first on failure)
#   just ci                 → what the pull-request check runs: no cluster needed
#
# Targeting a different environment: env vars are forwarded as-is, e.g.
#   GATEWAY_BASE_URL=https://gateway.example.com just smoke
# See resources/common.resource for the full list of overridable variables.

# Robot console output mode (dotted, verbose, quiet, none).
# Note: If tests crash with "OSError: [Errno 5] Input/output error" under an IDE
# task runner, it means stdout was closed mid-run. Workaround: run with `console=none`
# (e.g., `just smoke console=none`).
console := "verbose"
ROBOT := ".venv/bin/robot --console " + console
ALL_TESTS := "tests/ ../labs64.io-auditflow/tests/e2e/ ../labs64.io-payment-gateway/tests/e2e/"
PSP_STUB_COMPOSE := "psp-stub/docker-compose.yml"
HELM_JUSTFILE := "../labs64.io-helm-charts/justfile"

# List the recipes by group (from the workspace: `just tests`)
default:
    @echo 'labs64.io-tests: the Robot Framework suites against a running stack. From the workspace: just tests <recipe>'
    @just --list --unsorted --list-heading ''

# Recipes by group (docs/justfiles.md in labs64.io-workspace): one file per group, in list order.
import 'just/setup.just'
import 'just/tests.just'
import 'just/psp-stub.just'
import 'just/quality-gates.just'
import 'just/renamed.just'
