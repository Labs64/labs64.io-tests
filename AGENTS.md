# AGENTS.md — Labs64.IO :: Tests

Guidance for AI agents working in this repository. Read this before making changes.

## What this is

Black-box, API-edge integration & regression suite for the Labs64.IO ecosystem, built with Robot Framework. It is deliberately slim: one `resources/<module>.resource` + `tests/<module>/` pair per covered module, no test framework abstraction beyond what Robot Framework itself provides. Don't add a plugin system, a DSL, or a generic "test runner" layer — this suite grows by adding another module folder, not by adding infrastructure.

## Contract-first, always

Every test must map to an operation that actually exists in the module's OpenAPI spec (e.g. `labs64.io-auditflow/auditflow-api/src/main/resources/openapi/openapi-audit-v1.yaml`). Before writing or updating a test:

1. Read the module's OpenAPI spec — its `paths` are the only endpoints that exist. Do not guess at conventional-sounding endpoints (`/health`, `/events`) that "should" exist — this suite previously drifted this way (auditflow tests targeted a `GET /events` query endpoint that was never in the contract; AuditFlow is a router with no query API by design, see its `AGENTS.md`).
2. Read each operation's `x-labs64-auth` annotation (`public: true`, or `tenant: true` + `scopes: [...]`) — this is the same annotation the authproxy's cerbos policy generation reads, and it is the source of truth for what the auth/authz matrix in `authz.robot` should assert.
3. Use the `test-suite-steward` skill (workspace-level `.agents/skills/test-suite-steward/`) to diff existing tests against the current spec and scaffold the matrix — it automates steps 1–2, and also covers running and auditing the suite more broadly.

## Generated auth-enforcement suite (do not hand-edit)

`tests/common/auth_enforcement.robot` is **generated** by `scripts/generate_auth_enforcement_suite.py`
from every module's `x-labs64-auth`, one case per protected operation, each calling the operation at
the gateway edge with no credentials and asserting 401/403. Regenerate and commit after any spec
change; CI runs the generator with `--check` and fails when the committed suite has drifted — an
operation that declares `x-labs64-auth` without a generated test is precisely the gap this catches.

This is the edge half of the guarantee. Each backend separately proves it fails closed in its own
`AuthEnforcementContractTest` (built on `AuthEnforcementContract` + `ModulePepHarness` in commons).
Both layers must hold: the edge is where authorization is enforced, the backend is what survives a
misrouted request. Don't hand-write edge cases that duplicate the generated ones — extend the
generator, or add the *scope*-level cases (wrong scope, right scope) that it deliberately leaves to
each module's `authz.robot`.

## Running tests

`just` wraps the `robot` invocations documented in `README.md` (venv setup, tag filters, output
to `results/`) — `just --list` for the full set, `just smoke` / `just regression` / `just
test-module <name>` / `just log` for the common ones. It's a thin wrapper, not a framework layer:
every recipe still shells out to plain `robot` — see "What NOT to do" below.

Run `just dryrun` before claiming a suite change works. It is `robot --dryrun` over every
suite: no cluster, no requests, seconds — and it resolves every keyword and `Resource` import,
which is the check that catches a test calling a keyword no resource file defines. That has
shipped here before (`payment_flow.robot` against `resources/payment_gateway.resource`) and
cost a full nightly provision to discover, as two failures indistinguishable from real ones.
CI runs the same check as its `static-checks` job.

## Gateway edge only

All base URLs point at the Traefik/authproxy gateway (`http://gateway.localhost/<module>/api/v1`), never a backend port directly. Cerbos authorization is enforced at the gateway; backends trust gateway-supplied `X-Auth-*` headers and in the `local` profile may even fall back to a default tenant. Hitting a backend directly makes an authz test meaningless — it would pass or fail regardless of the token.

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

Tag every case for a module whose images have never been published `not-ga` (currently Checkout — see `README.md`'s Tag Taxonomy note), so `smoke`/`p0`/`regression` can `--exclude not-ga` instead of gating on a 503 that no fix can turn green. For the generated `tests/common/auth_enforcement.robot`, set `not_ga=True` on the module's entry in `scripts/generate_auth_enforcement_suite.py` and regenerate — don't hand-edit the generated file.

## Adding a new module

1. Confirm the module has a real OpenAPI spec and check its `AGENTS.md` for base path / port conventions.
2. Add `resources/<module>.resource` following the pattern in `auditflow.resource` or `payment_gateway.resource` (session helpers + one keyword per operation you'll test).
3. Add `tests/<module>/smoke.robot` and `tests/<module>/authz.robot`.
4. Add `../labs64.io-<module>/tests/e2e/` to the robot data sources in every job of
   `.github/workflows/labs64io-regression-suite.yml` and to `ALL_TESTS` in the `justfile`
   (there is no build matrix — each job passes the suite paths to one `robot` call). If
   the module ships a container image, add it to `scripts/mirror_edge_images.sh` and give
   its CI an `edge-image` job (`mode: edge`, gated on a green master build) — the nightly
   job deploys `:edge` images and builds nothing.
5. Add the module to `README.md`'s repository structure and P0 coverage table if applicable.

## Local-only pod-log corroboration (explicit exception)

Tests tagged `local-k8s-only` may corroborate an HTTP assertion against `kubectl logs` in two
narrow cases: auth/authz enforcement, and a cross-service delivery probe where the receiving
service deliberately has no read API. Current examples are the authproxy's cerbos decision log
and AuditFlow delivery identified by a caller-supplied `correlationId`. This is an explicit
exception to "Gateway edge only" above for effects a pure HTTP client cannot observe.

Rules for this exception, enforced in `resources/common.resource` / `resources/auditflow.resource`:

- Every such test calls `Skip Unless Local Kubernetes` first, which skips (never fails) unless
  the active kubectl context exactly matches the pinned local k3d dev cluster
  (`k3d-labs64io`) — so CI (no kubectl context) always skips them silently.
- They are corroborating, never primary — the paired HTTP-status test case is still the actual
  contract check; the log assertion adds confidence, it doesn't replace the assertion.
- A cross-service delivery probe must use a unique correlation identifier and polling, remain
  `local-k8s-only`, and assert only the receiving service's processing log. It must not inspect
  RabbitMQ, a database, or another implementation detail.
- Don't extend this pattern to ordinary functional tests. It exists only where a load-bearing
  enforcement or delivery effect is otherwise invisible to a black-box client.

## What NOT to do

- Don't hardcode credentials — use `Get OIDC Token`/`Create Session With Scope`, or the `API_TOKEN` env var as a fallback.
- Don't assert against RabbitMQ, a database, or internal infrastructure. The only exception is
  the narrowly scoped `local-k8s-only` log corroboration described above.
- Don't add a query/store test against AuditFlow's own API — it doesn't have one, and never will (settled architecture decision).
- Don't scaffold coverage for every CRUD permutation of every endpoint up front — start with smoke + authz, add functional regression only for flows that have actually broken or are genuinely load-bearing (e.g. the payment-provider lifecycle).
