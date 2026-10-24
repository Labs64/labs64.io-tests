# Group `quality gates` (docs/justfiles.md in labs64.io-workspace). Imported by the justfile.

# What the pull-request check (.github/workflows/labs64io-regression-suite.yml, job static-checks) runs, in the same
# order: every protected operation has its generated edge test, and every suite resolves. Needs python3 and the sibling
# module checkouts the suites live in (labs64.io-auditflow, labs64.io-payment-gateway). No cluster.
#
# Run what the suite's pull-request check runs
[group('quality gates')]
ci: check-auth-suite dryrun

# tests/common/auth_enforcement.robot is generated from every module's x-labs64-auth (AGENTS.md): this fails when the
# committed file differs from what the generator writes, i.e. an operation was added or changed without its edge test.
#
# Check that the generated auth-enforcement suite matches the module OpenAPI specs
[group('quality gates')]
check-auth-suite: install-venv
    .venv/bin/python scripts/generate_auth_enforcement_suite.py --check

# Rewrite tests/common/auth_enforcement.robot from the module OpenAPI specs; commit the result
[group('quality gates')]
generate-auth-suite: install-venv
    .venv/bin/python scripts/generate_auth_enforcement_suite.py

# `robot --dryrun` resolves every keyword and `Resource` import without sending a single
# request, so a test calling a keyword that does not exist fails here instead of surfacing
# after a full provision as a test failure indistinguishable from a real regression. No tag
# filter, because an excluded suite must still be sound. Extra arguments go to the summary
# (CI passes `--artifact dryrun-report`).
#
# Validate all suites statically with robot --dryrun, without a cluster
[group('quality gates')]
dryrun *summary_args: install-venv
    #!/usr/bin/env bash
    set -uo pipefail
    {{ROBOT}} --dryrun --outputdir results/dryrun {{ALL_TESTS}}
    status=$?
    python3 scripts/robot_summary.py results/dryrun/output.xml --title "Dry run (static suite validation)" {{summary_args}}
    exit $status
