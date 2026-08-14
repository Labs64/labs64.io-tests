<p align="center"><img src="https://raw.githubusercontent.com/Labs64/.github/master/assets/labs64-io-ecosystem.png" alt="Labs64.IO Ecosystem"></p>

# Labs64.IO :: Tests

Integration & Regression Test Suite for the [Labs64.IO Ecosystem](https://labs64.io).

## Overview

Black-box API-edge regression suite for the [Labs64.IO](https://labs64.io) platform, built with [Robot Framework](https://robotframework.org/) and [`robotframework-requests`](https://github.com/MarketSquare/robotframework-requests).

Every test exercises the **gateway edge** (Traefik + authproxy), never a backend port directly.
Explicitly tagged `local-k8s-only` probes may additionally corroborate an otherwise unobservable
auth or cross-service delivery effect through correlation-scoped pod logs; they never inspect
RabbitMQ or a database. See `AGENTS.md` for the narrow exception rules.

Covers `auditflow` and `payment-gateway` today. See `AGENTS.md` for how to extend this to another module.

## Repository Structure

```
labs64.io-tests/
├── requirements.txt                # Python dependencies
├── resources/                      # Shared Robot Framework resource files
│   ├── common.resource             # HTTP session helpers, mock-oidc token minting, shared vars
│   ├── auditflow.resource          # AuditFlow-specific keywords (POST /audit/publish)
│   └── payment_gateway.resource    # Payment Gateway-specific keywords
├── tests/
│   ├── common/
│   │   └── e2e/
│   │       └── payment_auditflow.robot # PG -> AuditFlow local-k8s delivery probe
│   ├── auditflow/
│   │   ├── smoke.robot             # happy path + 400 validation
│   │   └── authz.robot             # auth/authz matrix — see P0 Defect Coverage below
│   └── payment-gateway/
│       ├── smoke.robot
│       ├── payment_providers.robot # create/read/update/delete lifecycle (noop PSP)
│       └── authz.robot             # auth/authz scope matrix
└── .github/workflows/
    └── regression-suite.yml        # GitHub Actions CI workflow
```

## Tag Taxonomy

| Tag | Meaning | Runs where |
|---|---|---|
| `smoke` | Fast critical-path only | Every PR |
| `regression` | Full functional coverage per service | Nightly + pre-release |
| `contract` | Mirrors a path covered by Schemathesis | Informational |
| `e2e` | Cross-service flows | Targeted / pre-release |
| `critical` | Failure blocks a release | Always gating |
| `p0-blocker` | Guards a known-critical defect class | Always gating, never skipped |
| `flaky` | Quarantined — non-blocking | Nightly, excluded from gating |
| `auth` | Authentication / authorisation assertions | — |
| `tenant-isolation` | Cross-tenant / cross-scope isolation scenarios | — |
| `error-handling` | Error path / negative testing | — |

> `contract` and `flaky` are **reserved for future use** — no test currently carries
> them, and that's not drift. `contract` is earmarked for tests that mirror a path Schemathesis
> already covers (informational, not gating); `flaky` is for quarantining a genuinely flaky case
> without deleting its coverage. The `e2e` tag is active for cross-service flows spanning more
> than one module; environment-specific probes also carry a tag such as `local-k8s-only`.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

You need a running Labs64.IO stack reachable through its gateway edge — either the [local k3d cluster](../labs64.io-helm-charts/DEVELOPERS.md) (`just up` from `labs64.io-helm-charts/`) or one of the other [Deployment Modes](../labs64.io-helm-charts/README.md#deployment-modes) (AWS QA/Staging/Prod, or your own BYO-infra cluster) with `gateway.localhost`-equivalent base URLs and a reachable `mock-oidc`-equivalent token endpoint (see [Targeting a different environment](#targeting-a-different-environment) below). `mock-oidc` is a **dev-only** OIDC provider that mints scoped M2M tokens on demand — the auth/authz tests use it to mint tokens with exactly the scope they want to assert against, so no manually-provisioned credentials are needed for local runs.

## Running Tests

Fastest path: `just` (see `justfile` — `just smoke`, `just regression`, `just test-module auditflow`, `just log`, etc.; `just --list` for the full set). It wraps venv setup and the `robot` invocations below, writing output to `results/`. The rest of this section shows the underlying `robot` commands directly, for when you need a variation the justfile doesn't cover.

**All smoke tests (fast, every PR):**
```bash
robot --include smoke tests/
```

**A single service:**
```bash
robot tests/auditflow/
robot tests/payment-gateway/
```

**A single file or test case:**
```bash
robot tests/auditflow/authz.robot
robot --test "Publish With Correct Scope Is Allowed" tests/auditflow/authz.robot
```

**P0 blocker tests only (never skipped):**
```bash
robot --include p0-blocker tests/
```

**Full regression, excluding flaky:**
```bash
robot --include regression --exclude flaky tests/
```

**Auth/authz matrix only, across all services:**
```bash
robot --include auth tests/
```

Robot writes `output.xml`, `log.html`, and `report.html` to the current directory (or `--outputdir <dir>`) on every run — open `log.html` first when a test fails, it has the full request/response detail per keyword.

### Targeting a different environment

Base URLs and the mock-oidc endpoint are resolved from environment variables (see `resources/common.resource` for the full list and defaults):

```bash
GATEWAY_BASE_URL=https://staging.labs64.io \
MOCK_OIDC_BASE_URL=https://mock-oidc.staging.labs64.io \
robot --include smoke tests/
```

If `mock-oidc` isn't reachable in your target environment, set `API_TOKEN` to a pre-provisioned token instead — tests that don't need a specific scope combination fall back to it; scope-matrix tests in `authz.robot` require `mock-oidc` since they need multiple distinct scope combinations per suite.

## CI

The GitHub Actions workflow (`.github/workflows/regression-suite.yml`) runs:

- **On every PR:** smoke tests per service in parallel + P0 blocker tests
- **Nightly:** full regression suite across all services, excluding `flaky`
- **Manual trigger:** `workflow_dispatch`

## P0 Defect Coverage

| Defect class | Test file | Tag |
|---|---|---|
| Phantom JWT (auth gap between spec and implementation) | `tests/auditflow/authz.robot` | `p0-blocker` |

## Adding, running, or auditing tests

See the `test-suite-steward` skill (workspace-level `.agents/skills/test-suite-steward/`) — it covers where a new test belongs, the OpenAPI `x-labs64-auth`-driven authz matrix, how to run and interpret results, and a periodic suite-health audit (drift, coverage gaps, duplication, flaky handling).

## License

The core of the *Labs64.IO Ecosystem* is entirely open source and free forever. Community modules are licensed under [Apache License 2.0](LICENSE).
