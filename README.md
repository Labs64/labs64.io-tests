<p align="center"><img src="https://raw.githubusercontent.com/Labs64/.github/master/assets/labs64-io-ecosystem.png" alt="Labs64.IO Ecosystem"></p>

# Labs64.IO :: Tests

[![Regression Suite](https://github.com/Labs64/labs64.io-tests/actions/workflows/labs64io-regression-suite.yml/badge.svg)](https://github.com/Labs64/labs64.io-tests/actions/workflows/labs64io-regression-suite.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![📖 Documentation](https://img.shields.io/badge/📖-Documentation-AB6543.svg)](https://labs64.io/docs/index.html)

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
├── scripts/
│   ├── generate_auth_enforcement_suite.py  # generates tests/common/auth_enforcement.robot
│   ├── mirror_edge_images.sh       # pull :edge images into the local k3d registry
│   ├── robot_summary.py            # output.xml -> job summary (totals + failures by cause)
│   └── wait_for_pods.sh            # CI readiness gate; fails fast on unrecoverable pods
└── .github/workflows/
    └── labs64io-regression-suite.yml        # GitHub Actions CI workflow
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
| `not-ga` | Targets a module whose images have never been published | Always excluded, kept for when it ships |
| `auth` | Authentication / authorisation assertions | — |
| `tenant-isolation` | Cross-tenant / cross-scope isolation scenarios | — |
| `error-handling` | Error path / negative testing | — |

> `contract` and `flaky` are **reserved for future use** — no test currently carries
> them, and that's not drift. `contract` is earmarked for tests that mirror a path Schemathesis
> already covers (informational, not gating); `flaky` is for quarantining a genuinely flaky case
> without deleting its coverage. The `e2e` tag is active for cross-service flows spanning more
> than one module; environment-specific probes also carry a tag such as `local-k8s-only`.
>
> `not-ga` **is** currently carried — by every Checkout case, generated and hand-written. No
> *released* Checkout image exists (`labs64/checkout`, `labs64/checkout-ui` have only ever
> published `:edge`), so `charts/labs64io-ecosystem` defaults `checkout.enabled` to `false`
> and the PR gate's install.sh stack never serves it; a call there would be a `503 no
> available server`, not a pass/fail signal about the module itself. `smoke`/`p0`/`regression`
> all `--exclude not-ga` so that structural fact doesn't read as a permanent regression.
>
> The nightly job is now the exception: it deploys Checkout's `:edge` image, so those cases
> would actually run there. Dropping the tag is therefore a judgement call per job, not a
> blocked one — remove it from a module's cases (and the `not_ga=True` module entry in
> `scripts/generate_auth_enforcement_suite.py`, for the generated suite) once its suites are
> confirmed green, and unconditionally the day its chart flips `enabled` to `true` by default.

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
robot --include smoke --exclude not-ga tests/
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
robot --include p0-blocker --exclude not-ga tests/
```

**Full regression, excluding flaky and not-yet-GA modules:**
```bash
robot --include regression --exclude flaky --exclude not-ga tests/
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

The GitHub Actions workflow (`.github/workflows/labs64io-regression-suite.yml`) runs three jobs:

| Job | Trigger | Target it provisions |
|---|---|---|
| **Static Checks** | every PR, ~1 min | none — no cluster needed |
| **Smoke** | every PR | ephemeral k3d + `bash install.sh install` (the **published** ecosystem chart, same pattern as `labs64io-published-chart-e2e.yml` in `labs64.io-helm-charts`) |
| **Full Regression** | nightly, `release`, `workflow_dispatch` | k3d + local registry + **Helmfile** (`just up`), running each module's `:edge` image |

**Static Checks** is the fastest way to find a broken test. It runs
`scripts/generate_auth_enforcement_suite.py --check` (every operation declaring
`x-labs64-auth` has a generated edge test) and `robot --dryrun` over every suite, which
resolves each keyword and `Resource` import without sending a request — so a test calling a
keyword that doesn't exist fails in seconds instead of surfacing an hour later as a test
failure indistinguishable from a real regression. Run the same check locally with
`just dryrun`.

**Full Regression** deliberately provisions differently from the PR gate. Its item-12 suites
(pipeline routing, condition operators, redaction, DLQ replay, quota enforcement, secretRef
resolution) assert against fixtures that exist only in `labs64.io-helm-charts`'
`overrides/auditflow/values.local.yaml` — the `t_regression` tenant and its deliberately
failing probe pipelines, `t_regression_quota`'s tiny quota, and the global redaction rule.
`install.sh`'s quickstart profile provisions only a `t_mock` demo tenant, so on that path
every one of those cases fails `403 TENANT_NOT_PROVISIONED` no matter how healthy the code
is. The Helmfile path is also the only one that applies each module's local override
(central Cerbos PDP address, `env` secretRef resolver, gateway routes), and — because it
creates the `k3d-labs64io` context — the only one where the `local-k8s-only` cases actually
execute instead of self-skipping.

### What nightly runs against

Every module publishes `<image>:edge` to Docker Hub after a green master build — the
`edge-image` job in each repo's CI, via `labs64.io-workspace`'s reusable
`docker-publish.yml`. Nightly mirrors those tags into the k3d registry
(`scripts/mirror_edge_images.sh`) as the `localhost:5005/<name>:latest` references the
Helmfile local overrides pin, and deploys them. Nothing is built here: nightly exists to
find integration failures *between* modules, and rebuilding eight images to do that would
re-run work each module's CI already did while adding several more ways to go red for
reasons that are not a regression.

The mirror step writes every image's source digest to the job summary, so a red nightly
says exactly which builds it ran against — `:edge` moves on every master push, so
timestamps alone would not.

If a module's `:edge` tag is missing, the step fails listing every missing image together
with the workflow that publishes it, rather than deploying a half-mirrored stack of mixed
vintages.

Every job excludes `not-ga`; see the `not-ga` entry in [Tag Taxonomy](#tag-taxonomy). Note
that Checkout and Customer Portal — which have never had a released image — now publish
`:edge` too, so nightly does deploy them (the Helmfile app layer deploys them regardless,
and an unpublished image would otherwise sit in `ImagePullBackOff`). Dropping `not-ga` from
that job's filter is a one-line change once those suites are confirmed green.

Every robot step writes a triage summary to the GitHub job summary via
`scripts/robot_summary.py`: totals, failures grouped by cause, then the failing test list.
A broken environment reads as one fat row ("39 × `TENANT_NOT_PROVISIONED`") rather than 39
individual regressions, without downloading the `log.html` artifact.

## P0 Defect Coverage

| Defect class | Test file | Tag |
|---|---|---|
| Phantom JWT (auth gap between spec and implementation) | `tests/auditflow/authz.robot` | `p0-blocker` |

## Adding, running, or auditing tests

See the `test-suite-steward` skill (workspace-level `.agents/skills/test-suite-steward/`) — it covers where a new test belongs, the OpenAPI `x-labs64-auth`-driven authz matrix, how to run and interpret results, and a periodic suite-health audit (drift, coverage gaps, duplication, flaky handling).

## License

The core of the *Labs64.IO Ecosystem* is entirely open source and free forever. Community modules are licensed under [Apache License 2.0](LICENSE).
