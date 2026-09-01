# Labs64.IO :: Tests — Root justfile
#
# Prerequisites: just, python3, a running Labs64.IO stack reachable through its gateway
# edge (see labs64.io-helm-charts/DEVELOPERS.md, `just local-up`).
#
# Quick start:
#   just smoke              → fast PR-gating subset, all modules
#   just regression         → full nightly-shape regression, excluding flaky
#   just test               → ordinary regression against the normal provider configuration
#   just test-all           → ordinary regression + isolated PSP-stub phase, with automatic cleanup
#   just test-module NAME    → everything for one module, e.g. `just test-module auditflow`
#   just log                → open the most recent run's log.html (read this first on failure)
#
# Targeting a different environment: env vars are forwarded as-is, e.g.
#   GATEWAY_BASE_URL=https://staging.labs64.io just smoke
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
# from the selected output.xml — the same ground-truth data Robot itself computed exit code
# $status from, not a guess; (2) written beside that output.xml, which survives if this terminal's
# stdout is broken; (3) the HTML report opened automatically, pass or fail. Every test-running
# recipe below delegates here instead of calling {{ROBOT}} directly.
_run *args: install
    #!/usr/bin/env bash
    set -uo pipefail
    output_dir="${ROBOT_OUTPUT_DIR:-results}"
    mkdir -p "$output_dir"
    {{ROBOT}} --outputdir "$output_dir" {{args}}
    status=$?
    stat_line=$(grep -o '<stat pass="[0-9]*" fail="[0-9]*" skip="[0-9]*">All Tests' "$output_dir/output.xml" 2>/dev/null | head -1)
    if [ -n "$stat_line" ]; then
        summary=$(echo "$stat_line" | sed -E 's/<stat pass="([0-9]+)" fail="([0-9]+)" skip="([0-9]+)">.*/\1 passed, \2 failed, \3 skipped/')
    else
        summary="(could not read totals from $output_dir/output.xml)"
    fi
    echo "$summary" > "$output_dir/summary.txt"
    # Everything past this point is best-effort: some hosts (e.g. certain IDE run panels) close
    # stdout mid-run, which can make even a plain echo fail with EIO. That must never flip the
    # real result above — $status was captured before any of this, and is what gets returned.
    echo "$summary" 2>/dev/null || true
    echo "Results:" 2>/dev/null || true
    echo "  Summary: file://$(pwd)/$output_dir/report.html" 2>/dev/null || true
    echo "  Detail:  file://$(pwd)/$output_dir/log.html" 2>/dev/null || true
    echo "  (Use 'labs64.io-tests::just report' or 'labs64.io-tests::just log' to serve these in a browser)" 2>/dev/null || true
    if [ "$(uname)" = "Darwin" ]; then open "$output_dir/report.html" 2>/dev/null || true; fi
    exit $status

# ─────────────────────────────────────────────────────────────────────────────
# CI-shaped runs — mirrors .github/workflows/labs64io-regression-suite.yml
# ─────────────────────────────────────────────────────────────────────────────

# --exclude not-ga: modules whose images were never published (currently
# Checkout) can't be deployed by install.sh, so their cases would fail
# identically here and in CI regardless of a real regression.
# --exclude known-bug: a documented, unresolved defect shouldn't block every PR.
# It's excluded from regression too (see below) — target it directly with
# `test-file`/`test-case` to check on it.
# Fast, PR-gating subset across all modules (keep this one fast — see AGENTS.md)
smoke:
    @just _run --include smoke --exclude not-ga --exclude known-bug {{ALL_TESTS}}

# Full functional regression, excluding quarantined flaky, not-yet-GA cases, and known bugs (nightly shape)
regression:
    @just _run --exclude flaky --exclude not-ga --exclude known-bug --exclude psp-stub {{ALL_TESTS}}

# Alias for `regression`, kept for parity with the `test` recipe every other module justfile exposes
test: regression

# `robot --dryrun` resolves every keyword and `Resource` import without sending a single
# request, so a test calling a keyword that does not exist fails here instead of surfacing
# after a full provision as a test failure indistinguishable from a real regression. No tag
# filter, because an excluded suite must still be sound.
# Static suite validation — no cluster, seconds; same check CI's static-checks job runs
dryrun: install
    #!/usr/bin/env bash
    set -uo pipefail
    {{ROBOT}} --dryrun --outputdir results/dryrun {{ALL_TESTS}}
    status=$?
    python3 scripts/robot_summary.py results/dryrun/output.xml --title "Dry run (static suite validation)"
    exit $status

# ─────────────────────────────────────────────────────────────────────────────
# Targeted runs
# ─────────────────────────────────────────────────────────────────────────────

# Auth/authz matrix only, across all modules
auth:
    @just _run --include auth {{ALL_TESTS}}

# Local-k8s-only log-corroboration cases — self-skip unless local k3d is the active kubectl context
local-k8s:
    @just _run --include local-k8s-only {{ALL_TESTS}}

# Start a blank host-side WireMock process. Provider suites register their versioned
# mappings through the Admin API, so this also works when Docker cannot mount devcontainer paths.
psp-stub-up:
    #!/usr/bin/env bash
    set -euo pipefail
    fixture_dir="../labs64.io-payment-gateway/tests/psp-stub/wiremock/mappings"
    if [ ! -d "$fixture_dir" ]; then
      echo "Payment Gateway PSP fixtures not found at $fixture_dir" >&2
      exit 1
    fi
    stub_port="${PSP_STUB_PORT:-8090}"
    port_owner=$(docker ps --filter "publish=$stub_port" --no-trunc --quiet | head -1)
    current_container=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock)
    if [ -n "$port_owner" ] && [ "$port_owner" != "$current_container" ]; then
      echo "PSP stub port $stub_port is already published by another Docker container:" >&2
      docker ps --filter "id=$port_owner" >&2
      echo "Stop that container before running 'just test-up'." >&2
      exit 1
    fi
    docker compose -f {{PSP_STUB_COMPOSE}} up -d
    for attempt in {1..30}; do
      container_id=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock)
      health=$(docker inspect "$container_id" | jq --raw-output '.[0].State.Health.Status // .[0].State.Status')
      if [ "$health" = "healthy" ]; then
        echo "PSP stub is ready (published port: $stub_port)"
        exit 0
      fi
      if [ "$health" = "unhealthy" ] || [ "$health" = "exited" ]; then
        break
      fi
      sleep 1
    done
    docker compose -f {{PSP_STUB_COMPOSE}} logs
    echo "PSP stub container did not become healthy" >&2
    exit 1

# Stop the host-side WireMock process.
psp-stub-down:
    docker compose -f {{PSP_STUB_COMPOSE}} down

# Follow WireMock logs.
psp-stub-logs:
    docker compose -f {{PSP_STUB_COMPOSE}} logs -f

# Switch an already-running local k3d Payment Gateway deployment to the PSP-stub endpoint.
# This is optional local orchestration; the Robot scenarios themselves remain environment-agnostic.
test-up:
    #!/usr/bin/env bash
    set -euo pipefail
    node="k3d-labs64io-server-0"
    if ! docker inspect "$node" >/dev/null 2>&1; then
      echo "Local k3d cluster is not running; run 'just up' in labs64.io-helm-charts first" >&2
      exit 1
    fi
    restore_on_error() {
      status="${1:-$?}"
      trap - ERR INT TERM
      echo "PSP test environment setup failed; restoring the normal PG configuration" >&2
      just --justfile {{HELM_JUSTFILE}} payment-gateway-psp-stub-disable || true
      just psp-stub-down || true
      exit "$status"
    }
    trap restore_on_error ERR
    trap 'restore_on_error 130' INT
    trap 'restore_on_error 143' TERM
    just psp-stub-up
    stub_port="${PSP_STUB_PORT:-8090}"
    stub_host=""
    stub_ip=$(docker exec "$node" nslookup host.docker.internal 2>/dev/null \
      | awk '$1 == "Name:" && $2 == "host.docker.internal" { found=1; next } found && $1 == "Address:" { print $2; exit }' \
      || true)
    if [[ "$stub_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
      && docker exec "$node" wget -q -O /dev/null "http://host.docker.internal:$stub_port/__admin/health"; then
      stub_host="host.docker.internal"
    else
      stub_ip=$(docker exec "$node" ip route 2>/dev/null \
        | awk '$1 == "default" { print $3; exit }' || true)
      if [[ "$stub_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
        && docker exec "$node" wget -q -O /dev/null "http://$stub_ip:$stub_port/__admin/health"; then
        stub_host="$stub_ip"
      fi
    fi
    if [ -z "$stub_host" ]; then
      echo "The k3d node cannot reach the host-side PSP stub on port $stub_port." >&2
      restore_on_error 1
    fi
    stub_url="http://$stub_host:$stub_port"
    host_cidr="$stub_ip/32"
    echo "PSP stub route from k3d: $stub_url ($host_cidr)"
    just --justfile {{HELM_JUSTFILE}} payment-gateway-psp-stub-enable "$host_cidr" "$stub_url"
    trap - ERR INT TERM

# Restore the normal Payment Gateway deployment first, then stop WireMock.
test-down:
    #!/usr/bin/env bash
    set -u
    status=0
    just --justfile {{HELM_JUSTFILE}} payment-gateway-psp-stub-disable || status=$?
    just psp-stub-down || {
      stub_status=$?
      if [ "$status" -eq 0 ]; then status=$stub_status; fi
    }
    exit "$status"

# Show both sides of the local PSP test environment.
test-status:
    #!/usr/bin/env bash
    set -u
    container_id=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock 2>/dev/null || true)
    health=""
    if [ -n "$container_id" ]; then
      health=$(docker inspect "$container_id" 2>/dev/null | jq --raw-output '.[0].State.Health.Status // .[0].State.Status' || true)
    fi
    if [ "$health" = "healthy" ]; then
      echo "PSP stub: ready (published port: ${PSP_STUB_PORT:-8090})"
    else
      echo "PSP stub: stopped or unhealthy"
    fi
    application_config=$(kubectl --namespace labs64io get configmap labs64io-payment-gateway-app-ext \
      --output jsonpath='{.data.application\.yaml}' 2>/dev/null \
      || true)
    if [[ "$application_config" == *"api-base-url:"* ]]; then
      echo "Payment Gateway: PSP-stub configuration enabled"
      sed -n '/payment-provider:/,/spring:/p' <<<"$application_config"
    else
      echo "Payment Gateway: normal provider configuration"
    fi

# PSP integration scenarios. A selected PSP test fails when the stub is absent; it never
# silently skips and turns a broken nightly setup green.
test-psp:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "${PSP_STUB_BASE_URL:-}" ]; then
      if ! curl --fail --silent "$PSP_STUB_BASE_URL/__admin/health" >/dev/null; then
        echo "PSP stub is not reachable at $PSP_STUB_BASE_URL" >&2
        exit 1
      fi
    else
      container_id=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock)
      health=$(docker inspect "$container_id" | jq --raw-output '.[0].State.Health.Status // .[0].State.Status')
      if [ "$health" != "healthy" ]; then
        echo "Local PSP stub is not healthy; run 'just test-up' first" >&2
        exit 1
      fi
      for candidate in \
        "http://localhost:${PSP_STUB_PORT:-8090}" \
        "http://host.docker.internal:${PSP_STUB_PORT:-8090}"; do
        if curl --connect-timeout 2 --max-time 3 --fail --silent "$candidate/__admin/health" >/dev/null; then
          export PSP_STUB_BASE_URL="$candidate"
          break
        fi
      done
      if [ -z "${PSP_STUB_BASE_URL:-}" ]; then
        echo "PSP stub container is healthy, but Robot runner cannot reach its published port" >&2
        exit 1
      fi
    fi
    echo "PSP stub Robot endpoint: $PSP_STUB_BASE_URL"
    just _run --include psp-stub {{ALL_TESTS}}

# Backward-compatible short alias.
psp: test-psp

# Run the normal regression first, then temporarily switch PG to the PSP stub, run only
# provider scenarios, restore PG, and merge both Robot outputs into the top-level report.
# TEST_ALL_OUTPUT_DIR can isolate the whole run (CI uses results/nightly).
test-all: install
    #!/usr/bin/env bash
    set -uo pipefail
    result_root="${TEST_ALL_OUTPUT_DIR:-results}"
    cleanup_required=0
    regression_attempted=0
    psp_attempted=0
    combined_attempted=0

    print_result() {
      label=$1
      output_file=$2
      output_dir=$3
      attempted=$4
      if [ "$attempted" -ne 1 ] || [ ! -f "$output_file" ]; then
        printf '%-70s | NOT RUN |\n' "$label"
        return
      fi
      stat_line=$(grep -o '<stat pass="[0-9]*" fail="[0-9]*" skip="[0-9]*">All Tests' "$output_file" 2>/dev/null | head -1)
      if [ -z "$stat_line" ]; then
        printf '%-70s | UNKNOWN |\n' "$label"
        echo "Output:  $(pwd)/$output_file"
        return
      fi
      passed=$(sed -E 's/.*pass="([0-9]+)".*/\1/' <<<"$stat_line")
      failed=$(sed -E 's/.*fail="([0-9]+)".*/\1/' <<<"$stat_line")
      skipped=$(sed -E 's/.*skip="([0-9]+)".*/\1/' <<<"$stat_line")
      total=$((passed + failed + skipped))
      if [ "$failed" -eq 0 ]; then state=PASS; else state=FAIL; fi
      printf '%-70s | %s |\n' "$label" "$state"
      echo "$total tests, $passed passed, $failed failed, $skipped skipped"
      echo "Output:  $(pwd)/$output_dir/output.xml"
      echo "Log:     $(pwd)/$output_dir/log.html"
      echo "Report:  $(pwd)/$output_dir/report.html"
    }

    finalize() {
      final_status=$?
      trap - EXIT INT TERM
      if [ "$cleanup_required" -eq 1 ]; then
        echo "Restoring the normal Payment Gateway configuration" >&2
        just test-down
        final_cleanup_status=$?
        if [ "$final_status" -eq 0 ] && [ "$final_cleanup_status" -ne 0 ]; then
          final_status=$final_cleanup_status
        fi
      fi
      echo
      echo "=============================================================================="
      echo "Final test summary"
      print_result "Regression" "$result_root/regression/output.xml" "$result_root/regression" "$regression_attempted"
      print_result "PSP stub" "$result_root/psp/output.xml" "$result_root/psp" "$psp_attempted"
      print_result "Combined" "$result_root/output.xml" "$result_root" "$combined_attempted"
      if [ "$final_status" -eq 0 ]; then
        echo "Overall: PASS"
      else
        echo "Overall: FAIL (exit code $final_status)"
      fi
      echo "=============================================================================="
      exit "$final_status"
    }
    trap finalize EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    echo "=== Phase 1/2: normal regression ==="
    regression_attempted=1
    ROBOT_OUTPUT_DIR="$result_root/regression" just regression
    regression_status=$?
    if [ "$regression_status" -ne 0 ]; then
      echo "Normal regression failed; PSP mode was not enabled." >&2
      exit "$regression_status"
    fi

    echo "=== Phase 2/2: PSP stub regression ==="
    just test-up
    setup_status=$?
    if [ "$setup_status" -ne 0 ]; then
      exit "$setup_status"
    fi
    cleanup_required=1

    psp_attempted=1
    ROBOT_OUTPUT_DIR="$result_root/psp" just test-psp
    psp_status=$?

    just test-down
    cleanup_status=$?
    if [ "$cleanup_status" -eq 0 ]; then
      cleanup_required=0
    fi

    combined_attempted=1
    .venv/bin/rebot \
      --name "Labs64.IO full test suite" \
      --outputdir "$result_root" \
      --output output.xml \
      --log log.html \
      --report report.html \
      "$result_root/regression/output.xml" \
      "$result_root/psp/output.xml"
    rebot_status=$?

    stat_line=$(grep -o '<stat pass="[0-9]*" fail="[0-9]*" skip="[0-9]*">All Tests' "$result_root/output.xml" 2>/dev/null | head -1)
    if [ -n "$stat_line" ]; then
      summary=$(echo "$stat_line" | sed -E 's/<stat pass="([0-9]+)" fail="([0-9]+)" skip="([0-9]+)">.*/\1 passed, \2 failed, \3 skipped/')
      echo "$summary" > "$result_root/summary.txt"
    fi

    if [ "$psp_status" -ne 0 ]; then exit "$psp_status"; fi
    if [ "$cleanup_status" -ne 0 ]; then exit "$cleanup_status"; fi
    exit "$rebot_status"

# Run common tests (e2e, integration) + all known modules tests
test-common:
    @just _run {{ALL_TESTS}}

# Ordinary suite for one module; environment-specific PSP stub cases stay opt-in.
test-module module:
    @just _run --exclude psp-stub ../labs64.io-{{module}}/tests/e2e/

# One file: just test-file tests/auditflow/authz.robot
test-file file:
    @just _run {{file}}

# One named test case within a file
test-case name file:
    @just _run --test "{{name}}" {{file}}

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────

# Serve the most recent run's HTML report (pass/fail summary) on localhost:8000
report:
    @echo "Serving report at http://localhost:8000/report.html (Press Ctrl+C to stop)"
    python3 -m http.server -d results 8000

# Serve the most recent run's HTML log — full request/response detail per keyword, read first on failure
log:
    @echo "Serving log at http://localhost:8000/log.html (Press Ctrl+C to stop)"
    python3 -m http.server -d results 8000

# Remove generated Robot Framework output
clean:
    rm -rf results output.xml log.html report.html
