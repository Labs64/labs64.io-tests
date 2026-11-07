# Tests reference

Long-form reference that used to live in the repository README. The [README](../README.md) is the
short entry point; the published documentation is at [labs64.io/docs](https://labs64.io/docs/).
For everything else, see the [regression tests page in the docs](https://labs64.io/docs/development/regression-tests.html).

### PSP stub tests

The ordinary local regression assumes a normal Payment Gateway deployment and excludes
`psp-stub` cases:

```bash
cd ../labs64.io-helm-charts
just up

cd ../labs64.io-tests
just test
```

To switch the existing local Payment Gateway deployment to the host-side WireMock endpoint,
run the targeted suite, and then restore the normal provider endpoint:

```bash
just enable-psp-stub
just show-psp-stub
just test-psp
just disable-psp-stub
```

To run the complete local gate in one command, including both the normal regression and the
PSP-stub scenarios, use:

```bash
just test
```

It runs the ordinary regression before changing PG, enables the stub only for the PSP phase,
and restores the normal deployment even when setup or tests fail. Phase reports are written to
`results/regression/` and `results/psp/`; the merged report remains at `results/report.html`.
A final summary repeats every phase result and report path at the bottom of the terminal output,
including `NOT RUN` for a phase that setup prevented from starting.

`enable-psp-stub` does not rebuild an image or recreate the cluster. It starts WireMock and applies a
small Helm override that rolls only Payment Gateway. `disable-psp-stub` reapplies the ordinary local
values before stopping WireMock. The Robot tests are not Kubernetes-specific: `just test-psp`
can target any already-prepared environment through the usual base URL variables.

Provider-specific Robot scenarios and WireMock mappings remain in the provider module repository;
this repository owns only the reusable WireMock process and test-environment lifecycle. `enable-psp-stub`
probes a host address from the k3d node itself and restricts PG egress to that single `/32` plus
WireMock port 8090, so it does not depend on a particular k3d hosts-file layout and works in
Docker Desktop/devcontainers and Linux CI.

## Adding, running, or auditing tests

See the `test-suite-steward` skill (workspace-level `.agents/skills/test-suite-steward/`) — it covers where a new test belongs, the authz matrix driven by the OpenAPI `auth` blocks, how to run and interpret results, and a periodic suite-health audit (drift, coverage gaps, duplication, flaky handling).
