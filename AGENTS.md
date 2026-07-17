# AGENTS.md — Labs64.IO :: Tests

Guidance for AI agents working in this repository. Read this before making changes.

## What this is

Black-box, API-edge integration & regression suite for the Labs64.IO ecosystem, built with Robot Framework. It is deliberately slim: one `resources/<module>.resource` + `tests/<module>/` pair per covered module, no test framework abstraction beyond what Robot Framework itself provides. Don't add a plugin system, a DSL, or a generic "test runner" layer — this suite grows by adding another module folder, not by adding infrastructure.

## Contract-first, always

Every test must map to an operation that actually exists in the module's OpenAPI spec (e.g. `labs64.io-auditflow/auditflow-api/src/main/resources/openapi/openapi-audit-v1.yaml`). Before writing or updating a test:

1. Read the module's OpenAPI spec — its `paths` are the only endpoints that exist. Do not guess at conventional-sounding endpoints (`/health`, `/events`) that "should" exist — this suite previously drifted this way (auditflow tests targeted a `GET /events` query endpoint that was never in the contract; AuditFlow is a router with no query API by design, see its `AGENTS.md`).
2. Read each operation's `x-labs64-auth` annotation (`public: true`, or `tenant: true` + `scopes: [...]`) — this is the same annotation the authproxy's Cedar policy generation reads, and it is the source of truth for what the auth/authz matrix in `authz.robot` should assert.
3. Use the `test-suite-steward` skill (workspace-level `.agents/skills/test-suite-steward/`) to diff existing tests against the current spec and scaffold the matrix — it automates steps 1–2, and also covers running and auditing the suite more broadly.

## Running tests

`just` wraps the `robot` invocations documented in `README.md` (venv setup, tag filters, output
to `results/`) — `just --list` for the full set, `just smoke` / `just regression` / `just
test-module <name>` / `just log` for the common ones. It's a thin wrapper, not a framework layer:
every recipe still shells out to plain `robot` — see "What NOT to do" below.

## Gateway edge only

All base URLs point at the Traefik/authproxy gateway (`http://gateway.localhost/<module>/api/v1`), never a backend port directly. Cedar authorization is enforced at the gateway; backends trust gateway-supplied `X-Auth-*` headers and in the `local` profile may even fall back to a default tenant. Hitting a backend directly makes an authz test meaningless — it would pass or fail regardless of the token.

## Minting tokens with `mock-oidc`

`resources/common.resource` provides `Get OIDC Token` / `Create Session With Scope`, which call the local dev-only `mock-oidc` provider (`POST http://mock-oidc.localhost/labs64io/token`, `grant_type=client_credentials`). The `scope` form param is echoed verbatim into the JWT for any value that isn't one of the named personas (`admin`, `auditflow`, `ecommerce`, `no-access`) — so a test can mint a token carrying **exactly** the scope it wants to assert against (e.g. `audit-event:read` to prove it must NOT satisfy a route requiring `audit-event:write`). Prefer this over a single static `API_TOKEN` whenever a test needs to distinguish scopes.

## Structure per module

```
resources/<module>.resource   # session/keyword helpers, one file per module
tests/<module>/
  smoke.robot                 # fast, critical-path only — runs on every PR
  authz.robot                 # auth/authz matrix: unauthenticated, wrong scope, correct scope
  <feature>.robot             # additional functional regression, only as needed
```

Don't create a file per HTTP verb or per tiny variation — group related test cases into the smallest number of files that stay readable. `authz.robot` in particular should read as a matrix: one test case per (auth state × scope) combination that matters, not one file per endpoint.

## Tag taxonomy

See `README.md` for the full table. The tags that matter most when writing a new test: `smoke` (PR-gating, keep fast and few), `p0-blocker` (guards a known-critical defect class, never quarantined), `auth`/`tenant-isolation` (authz matrix cases). Every test needs at least one of `smoke` or `regression`.

## Adding a new module

1. Confirm the module has a real OpenAPI spec and check its `AGENTS.md` for base path / port conventions.
2. Add `resources/<module>.resource` following the pattern in `auditflow.resource` or `payment_gateway.resource` (session helpers + one keyword per operation you'll test).
3. Add `tests/<module>/smoke.robot` and `tests/<module>/authz.robot`.
4. Add the module to the CI matrix in `.github/workflows/regression-suite.yml`.
5. Add the module to `README.md`'s repository structure and P0 coverage table if applicable.

## Local-only pod-log corroboration (explicit exception)

`tests/auditflow/authz.robot` has a handful of test cases tagged `local-k8s-only` that
additionally corroborate an HTTP-status assertion against `kubectl logs` (the authproxy's Cedar
decision log, and the AuditFlow backend's delivery log via `correlationId`). This is a
deliberate, narrow exception to "Gateway edge only" above, added because the auth/authz path has
two effects a pure HTTP client can't see: whether the *edge* actually made the decision it
appears to have made, and whether an allowed request was actually *delivered* past the gateway.

Rules for this exception, enforced in `resources/common.resource` / `resources/auditflow.resource`:

- Every such test calls `Skip Unless Local Kubernetes` first, which skips (never fails) unless
  the active kubectl context exactly matches the pinned local k3d dev cluster
  (`k3d-labs64io`) — so CI (no kubectl context) always skips them silently.
- They are corroborating, never primary — the paired HTTP-status test case is still the actual
  contract check; the log assertion adds confidence, it doesn't replace the assertion.
- Don't extend this pattern to ordinary functional tests. It exists only for the auth/authz path,
  where the enforcement point and delivery effect are otherwise invisible to the suite.

## What NOT to do

- Don't hardcode credentials — use `Get OIDC Token`/`Create Session With Scope`, or the `API_TOKEN` env var as a fallback.
- Don't assert against RabbitMQ, kubectl, or any internal infrastructure — API edge only.
- Don't add a query/store test against AuditFlow's own API — it doesn't have one, and never will (settled architecture decision).
- Don't scaffold coverage for every CRUD permutation of every endpoint up front — start with smoke + authz, add functional regression only for flows that have actually broken or are genuinely load-bearing (e.g. the payment-provider lifecycle).
