# Labs64.IO :: Tests — Root justfile
#
# Prerequisites: just, python3, a running Labs64.IO stack reachable through its gateway
# edge (see labs64.io-helm-charts/DEVELOPERS.md, `just local-up`).
#
# Quick start:
#   just smoke              → fast PR-gating subset, all modules
#   just regression         → full nightly-shape regression, excluding flaky
#   just test-module NAME    → everything for one module, e.g. `just test-module auditflow`
#   just log                → open the most recent run's log.html (read this first on failure)
#
# Targeting a different environment: env vars are forwarded as-is, e.g.
#   GATEWAY_BASE_URL=https://staging.labs64.io just smoke
# See resources/common.resource for the full list of overridable variables.

# `--console none` disables Robot's own console writer entirely (all output modes —
# `verbose` and `dotted` alike — write to stdout and crash with "OSError: [Errno 5] Input/output
# error" if stdout is ever closed/broken mid-run, which happens under some IDE task runners and
# other non-plain-TTY invocations). `_run` below prints its own results pointer afterward, since
# Robot itself now prints nothing; the full detail always lives in results/log.html regardless.
ROBOT := ".venv/bin/robot --console none"
ALL_TESTS := "tests/ ../labs64.io-auditflow/tests/e2e/ ../labs64.io-checkout/tests/e2e/ ../labs64.io-payment-gateway/tests/e2e/"

# List available recipes
default:
    @just --list

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

# Create the virtualenv (if missing) and install/refresh dependencies
install:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d .venv ]; then
        python3 -m venv .venv
    fi
    .venv/bin/pip install -q -r requirements.txt

# Internal: run robot with a stdout-safe console mode (see ROBOT above), then surface the real
# result three ways so nothing is hidden by that: (1) a pass/fail/skip count parsed straight
# from results/output.xml — the same ground-truth data Robot itself computed exit code $status
# from, not a guess; (2) written to results/summary.txt, which survives even if this terminal's
# stdout is broken; (3) the HTML report opened automatically, pass or fail. Every test-running
# recipe below delegates here instead of calling {{ROBOT}} directly.
_run *args: install
    #!/usr/bin/env bash
    set -uo pipefail
    {{ROBOT}} --outputdir results {{args}}
    status=$?
    stat_line=$(grep -o '<stat pass="[0-9]*" fail="[0-9]*" skip="[0-9]*">All Tests' results/output.xml 2>/dev/null | head -1)
    if [ -n "$stat_line" ]; then
        summary=$(echo "$stat_line" | sed -E 's/<stat pass="([0-9]+)" fail="([0-9]+)" skip="([0-9]+)">.*/\1 passed, \2 failed, \3 skipped/')
    else
        summary="(could not read totals from results/output.xml)"
    fi
    echo "$summary" > results/summary.txt
    # Everything past this point is best-effort: some hosts (e.g. certain IDE run panels) close
    # stdout mid-run, which can make even a plain echo fail with EIO. That must never flip the
    # real result above — $status was captured before any of this, and is what gets returned.
    echo "$summary" 2>/dev/null || true
    echo "Results: results/report.html (summary) | results/log.html (detail) | results/summary.txt (plain text)" 2>/dev/null || true
    open results/report.html 2>/dev/null || true
    exit $status

# ─────────────────────────────────────────────────────────────────────────────
# CI-shaped runs — mirrors .github/workflows/regression-suite.yml
# ─────────────────────────────────────────────────────────────────────────────

# Fast, PR-gating subset across all modules (keep this one fast — see AGENTS.md)
smoke:
    @just _run --include smoke {{ALL_TESTS}}

# Guard tests for known-critical defect classes — always gating, never skipped
p0:
    @just _run --include p0-blocker {{ALL_TESTS}}

# Full functional regression, excluding quarantined flaky cases (nightly shape)
regression:
    @just _run --include regression --exclude flaky {{ALL_TESTS}}

# ─────────────────────────────────────────────────────────────────────────────
# Targeted runs
# ─────────────────────────────────────────────────────────────────────────────

# Auth/authz matrix only, across all modules
auth:
    @just _run --include auth {{ALL_TESTS}}

# Local-k8s-only log-corroboration cases — self-skip unless local k3d is the active kubectl context
local-k8s:
    @just _run --include local-k8s-only {{ALL_TESTS}}

# Run common tests (e2e, integration) + all known modules tests
test-common:
    @just _run {{ALL_TESTS}}

# Everything for one module, no tag filter: just test-module auditflow
test-module module:
    @just _run ../labs64.io-{{module}}/tests/e2e/

# One file: just test-file tests/auditflow/authz.robot
test-file file:
    @just _run {{file}}

# One named test case within a file
test-case name file:
    @just _run --test "{{name}}" {{file}}

# Everything, no tag filter at all (slowest option)
all:
    @just _run {{ALL_TESTS}}

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────

# Open the most recent run's HTML report (pass/fail summary)
report:
    open results/report.html

# Open the most recent run's HTML log — full request/response detail per keyword, read first on failure
log:
    open results/log.html

# Remove generated Robot Framework output
clean:
    rm -rf results output.xml log.html report.html
