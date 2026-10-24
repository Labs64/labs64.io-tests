# Group `tests` (docs/justfiles.md in labs64.io-workspace). Imported by the justfile.

# Internal: run robot with a stdout-safe console mode (see ROBOT above), then surface the real
# result three ways so nothing is hidden by that: (1) a pass/fail/skip count parsed straight
# from the selected output.xml — the same ground-truth data Robot itself computed exit code
# $status from, not a guess; (2) written beside that output.xml, which survives if this terminal's
# stdout is broken; (3) the HTML report opened automatically, pass or fail. Every test-running
# recipe below delegates here instead of calling {{ROBOT}} directly.
#
# Run robot with a stdout-safe console, print the pass/fail count and open the HTML report
[private]
_run *args: install-venv
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
    echo "  (Use 'labs64.io-tests::just open-report' or 'labs64.io-tests::just open-log' to serve these in a browser)" 2>/dev/null || true
    if [ "$(uname)" = "Darwin" ]; then open "$output_dir/report.html" 2>/dev/null || true; fi
    exit $status

# Run the normal regression first, then temporarily switch PG to the PSP stub, run only
# provider scenarios, restore PG, and merge both Robot outputs into the top-level report.
# TEST_ALL_OUTPUT_DIR can isolate the whole run (CI uses results/nightly).
#
# Run the whole suite: the regression, then the PSP-stub scenarios, merged into one report
[group('tests')]
test: install-venv
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
        just disable-psp-stub
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
    just enable-psp-stub
    setup_status=$?
    if [ "$setup_status" -ne 0 ]; then
      exit "$setup_status"
    fi
    cleanup_required=1

    psp_attempted=1
    ROBOT_OUTPUT_DIR="$result_root/psp" just test-psp
    psp_status=$?

    just disable-psp-stub
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

# --exclude not-ga: modules whose images were never published (currently
# Checkout) can't be deployed by install.sh, so their cases would fail
# identically here and in CI regardless of a real regression.
# --exclude known-bug: a documented, unresolved defect shouldn't block every PR.
# It's excluded from regression too (see below) — target it directly with
# `test-file`/`test-case` to check on it.
# Run the fast PR-gating subset across all modules
[group('tests')]
smoke:
    @just _run --include smoke --exclude not-ga --exclude known-bug {{ALL_TESTS}}

# Run the full functional regression, excluding flaky, not-GA and known-bug cases (nightly shape)
[group('tests')]
regression:
    @just _run --exclude flaky --exclude not-ga --exclude known-bug --exclude psp-stub {{ALL_TESTS}}

# Run only the auth/authz matrix tests across all modules
[group('tests')]
test-auth:
    @just _run --include auth --exclude not-ga --exclude known-bug {{ALL_TESTS}}

# Run the log-corroboration cases for the local k3d cluster, which skip on any other kubectl context
[group('tests')]
test-local-k8s:
    @just _run --include local-k8s-only {{ALL_TESTS}}

# Run the common tests (E2E, integration) and the tests of all known modules
[group('tests')]
test-common:
    @just _run {{ALL_TESTS}}

# Run the ordinary suite for one module, leaving out the PSP stub cases
[group('tests')]
test-module module:
    @just _run --exclude psp-stub ../labs64.io-{{module}}/tests/e2e/

# Run a single Robot file
[group('tests')]
test-file file:
    @just _run {{file}}

# Run one named test case from a file
[group('tests')]
test-case name file:
    @just _run --test "{{name}}" {{file}}

# Serve the latest run's HTML report on localhost:8000
[group('tests')]
open-report:
    @echo "Serving report at http://localhost:8000/report.html (Press Ctrl+C to stop)"
    python3 -m http.server -d results 8000

# Serve the latest run's HTML log, with full request and response detail, on localhost:8000
[group('tests')]
open-log:
    @echo "Serving log at http://localhost:8000/log.html (Press Ctrl+C to stop)"
    python3 -m http.server -d results 8000

# Remove generated Robot Framework output
[group('tests')]
clean:
    rm -rf results output.xml log.html report.html
