<p align="center"><img src="https://raw.githubusercontent.com/Labs64/.github/master/assets/labs64-io-ecosystem.png" alt="Labs64.IO Ecosystem"></p>

# Labs64.IO :: Tests

Integration & Regression Test Suite for the [Labs64.IO Ecosystem](https://labs64.io).

## Overview

Black-box API-edge regression suite for the [Labs64.IO](https://labs64.io) platform, built with [Robot Framework](https://robotframework.org/) and [`robotframework-requests`](https://github.com/MarketSquare/robotframework-requests).

Every test asserts through the **public API edge** only — no RabbitMQ, kubectl, or internal infrastructure access. This matches how an ISV or AI agent actually experiences the platform and keeps the suite's secrets surface minimal.

## Repository Structure

```
labs64.io-tests/
├── requirements.txt                # Python dependencies
├── resources/                      # Shared Robot Framework resource files
│   ├── common.resource             # HTTP session helpers, shared variables
│   ├── netlicensing.resource       # NetLicensing-specific keywords
│   └── auditflow.resource          # AuditFlow-specific keywords
├── tests/
│   ├── netlicensing/
│   │   ├── smoke.robot
│   │   ├── licensing_models.robot
│   │   └── ppu_agent_extension.robot    # EXT-PPU-01..15
│   ├── auditflow/
│   │   ├── smoke.robot
│   │   ├── ingestion_completeness_regression.robot   # P0 — dead-DLQ / silent loss
│   │   └── jwt_auth_regression.robot                 # P0 — phantom-JWT auth gap
│   ├── payment-gateway/smoke.robot
│   ├── iam-gateway/smoke.robot
│   ├── invoicing/smoke.robot
│   └── cross_service/
│       └── entitlement_to_invoice_e2e.robot
├── manual/
│   └── netlicensing-smoke.hurl     # Hurl one-off smoke checks (not run in CI)
└── .github/workflows/
    └── regression-suite.yml        # GitHub Actions CI workflow
```

## Tag Taxonomy

| Tag | Meaning | Runs where |
|---|---|---|
| `smoke` | Fast critical-path only | Every PR |
| `regression` | Full functional coverage per service | Nightly + pre-release |
| `contract` | Mirrors a path covered by Schemathesis | Informational |
| `e2e` | Cross-service flows | Pre-release only |
| `critical` | Failure blocks a release | Always gating |
| `p0-blocker` | Guards a known-critical defect class | Always gating, never skipped |
| `flaky` | Quarantined — non-blocking | Nightly, excluded from gating |
| `auth` | Authentication / authorisation assertions | — |
| `tenant-isolation` | Cross-tenant isolation scenarios | — |
| `error-handling` | Error path / negative testing | — |

## Setup

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Running Tests

**All smoke tests:**
```bash
robot --include smoke tests/
```

**P0 blocker tests only (dead-DLQ + phantom-JWT regressions):**
```bash
robot --include p0-blocker tests/
```

**Full regression, excluding flaky:**
```bash
robot --include regression --exclude flaky tests/
```

**Single service:**
```bash
robot tests/netlicensing/
```

**Target environment (override via environment variables):**
```bash
NETLICENSING_BASE_URL=https://staging.netlicensing.io/core/v2/rest \
API_TOKEN=<your-token> \
robot --include smoke tests/netlicensing/
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `NETLICENSING_BASE_URL` | `https://go.netlicensing.io/core/v2/rest` | NetLicensing API base URL |
| `AUDITFLOW_BASE_URL` | `http://localhost:8080` | AuditFlow service base URL |
| `PAYMENT_GATEWAY_BASE_URL` | `http://localhost:8081` | Payment Gateway base URL |
| `IAM_GATEWAY_BASE_URL` | `http://localhost:8082` | IAM Gateway base URL |
| `INVOICING_BASE_URL` | `http://localhost:8083` | Invoicing service base URL |
| `API_TOKEN` | *(empty)* | ****** for API authentication — set via CI secret (`secrets.API_TOKEN`), never hardcoded |

## CI

The GitHub Actions workflow (`.github/workflows/regression-suite.yml`) runs:

- **On every PR:** smoke tests per service in parallel + P0 blocker tests
- **Nightly:** full regression suite across all services, excluding `flaky`
- **Manual trigger:** `workflow_dispatch`

## Manual / Exploratory Checks

The `manual/` directory contains [Hurl](https://hurl.dev/) files that mirror the NetLicensing "Try it now" curl examples from the developer documentation. These are **not** run in CI — they are for ad-hoc manual checks:

```bash
hurl --variable netlicensing_base_url=https://go.netlicensing.io/core/v2/rest \
     manual/netlicensing-smoke.hurl
```

## P0 Defect Coverage

| Defect class | Test file | Tag |
|---|---|---|
| Dead-DLQ / silent audit-event loss | `tests/auditflow/ingestion_completeness_regression.robot` | `p0-blocker` |
| Phantom JWT (auth gap between spec and implementation) | `tests/auditflow/jwt_auth_regression.robot` | `p0-blocker` |
