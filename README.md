# Labs64.IO :: Tests

**A black-box regression suite for the Labs64.IO platform, run through the gateway edge.**
*Part of the [Labs64.IO Ecosystem](https://labs64.io): the cross-module safety net: every test exercises the gateway, never a backend port.*

[![Regression Suite](https://github.com/Labs64/labs64.io-tests/actions/workflows/labs64io-regression-suite.yml/badge.svg)](https://github.com/Labs64/labs64.io-tests/actions/workflows/labs64io-regression-suite.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![📖 Documentation](https://img.shields.io/badge/📖-Documentation-AB6543.svg)](https://labs64.io/docs/development/contributing.html)

<p align="center"><img src="docs/assets/tests-hero.svg" alt="Tests: A route-by-caller matrix of expected status codes: the Robot Framework suite calls every route through the gateway with real tokens and checks that each 2xx, 401 and 403 matches, 36 of 36." width="880"></p>

[Why Tests?](#why-tests) · [Documentation](https://labs64.io/docs/development/regression-tests.html) · [Build and test](#build-and-test) · [Ecosystem](#the-labs64io-ecosystem) · [labs64.io](https://labs64.io)

> [!NOTE]
> The suite needs a running Labs64.IO stack reachable through its gateway edge. By default it expects the local k3d addresses (`http://gateway.localhost`); override them with environment variables for any other address.

## Why Tests?

A change in one module can break another, and the break shows up at the edge: a wrong scope, a missing route, a payment that never reaches the audit log. This suite checks the platform the way a real client sees it, so you find out before your users do.

1. **Edge only.** Every test goes through Traefik and the auth proxy, so authentication and authorization are always part of what is tested.
2. **Real tokens.** Tokens are minted with exact scopes from the mock identity provider or Keycloak.
3. **Tagged and filterable.** `smoke`, `regression`, `auth` and module tags let you run exactly the slice you need.

**A good fit if**

- You change a Labs64.IO module and want to know whether the platform as a whole still behaves.
- You deploy the platform and want a regression gate (smoke on every pull request, deeper runs nightly).
- You want proof that authorization is enforced for every route and scope.

**Probably not what you need if**

- You need unit tests for a module: those live in each module's repository.
- You have no running stack: the suite exercises a live gateway, so it needs one.

## Documentation

Install, configure and operate Tests in the **[Tests documentation](https://labs64.io/docs/development/regression-tests.html)**.

[What it covers](https://labs64.io/docs/development/regression-tests.html#what-it-covers) · [Run the suite](https://labs64.io/docs/development/regression-tests.html#run-the-suite) · [Add a test](https://labs64.io/docs/development/regression-tests.html#add-a-test)

New to Labs64.IO? The [Quickstart](https://labs64.io/docs/getting-started/quickstart.html) puts the platform on any Kubernetes cluster in about five minutes.

## Build and test

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

just ci          # static checks and a Robot dry run: no cluster needed
just smoke       # the fast gate, against a running stack
```

Needs Python 3.14. [`docs/reference.md`](docs/reference.md) lists every command, tag and environment variable. Working on the code with an AI agent? [`AGENTS.md`](AGENTS.md) and [`CLAUDE.md`](CLAUDE.md) describe the layout, conventions and checks.

## The Labs64.IO Ecosystem

This repository is part of the [Labs64.IO Ecosystem](https://labs64.io): open-source building blocks for secure commerce platforms. Every module is documented at [labs64.io/docs](https://labs64.io/docs/).

| Module | What it does |
|---|---|
| [**AuditFlow**](https://github.com/Labs64/labs64.io-auditflow) | Publish once, route anywhere, lose nothing |
| [**Auth Gateway**](https://github.com/Labs64/labs64.io-authproxy) | One authenticated edge for every module |
| [**Payment Gateway**](https://github.com/Labs64/labs64.io-payment-gateway) | One API across multiple payment providers |
| [**Checkout**](https://github.com/Labs64/labs64.io-checkout) | Whitelabel checkout and order workflow |
| [**Customer Portal**](https://github.com/Labs64/labs64.io-customer-portal) | Self-service portal for your customers |

Built on [Commons](https://github.com/Labs64/labs64.io-commons), deployed with [Helm Charts](https://github.com/Labs64/labs64.io-helm-charts), developed in the [Workspace](https://github.com/Labs64/labs64.io-workspace), verified by [Tests](https://github.com/Labs64/labs64.io-tests) and documented in [Docs](https://github.com/Labs64/labs64.io-docs). Also from Labs64: [NetLicensing](https://netlicensing.io) for licensing-as-a-service and [GuideChimp](https://www.labs64.com/guidechimp/) for guided product tours.

## Contributing

We would love your help. New scenarios are the most useful contribution, especially for a module that has none yet. Fork the repository, make your change on a branch, run the checks described in [`AGENTS.md`](AGENTS.md) and open a pull request. Not sure whether an idea fits? Open an issue first.

## License

Open source under the [Apache License 2.0](LICENSE): use it, change it and ship it commercially.

---

<p align="center">
  <a href="https://labs64.io"><img alt="Labs64.IO" src="https://labs64.io/docs/assets/images/labs64-logo.png" width="110"></a><br>
  <sub>Made by the <a href="https://labs64.io">Labs64</a> team and community.</sub>
</p>
