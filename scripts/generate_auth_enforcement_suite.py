#!/usr/bin/env python3
"""Generate the gateway-edge auth-enforcement suite from the module OpenAPI specs.

Item 2 of the roadmap: every operation that declares `x-labs64.auth` gets an
automated test that calls it unauthenticated and asserts 401/403. This is the
gateway-edge half — the module-layer half lives in each backend's own
`AuthEnforcementContractTest` (commons `AuthEnforcementContract`). Both must
hold: the module test proves the backend fails closed, this one proves the edge
does, and the edge is where authorization is actually enforced.

The suite is generated rather than hand-written for the same reason the Cerbos
policies and gateway routes are: `x-labs64.auth` is the single source of truth,
and a hand-maintained list is exactly how "phantom auth" got here in the first
place. CI regenerates and diffs, so an operation added without a test fails the
build — silence must not read as success.

Usage:
    scripts/generate_auth_enforcement_suite.py           # write the suite
    scripts/generate_auth_enforcement_suite.py --check   # fail if out of date
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = REPO_ROOT.parent
OUTPUT = REPO_ROOT / "tests" / "common" / "auth_enforcement.robot"

LABS64_EXTENSION = "x-labs64"
AUTH_PROPERTY = "auth"
HTTP_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")

# RequestsLibrary has no keyword for these, and none of them carry auth semantics
# worth asserting at the edge.
UNSUPPORTED_METHODS = ("options", "trace")

TEMPLATE_PARAM = re.compile(r"\{([^/{}]+)\}")
SAMPLE_UUID = "00000000-0000-4000-8000-000000000000"


@dataclass(frozen=True)
class Module:
    """A module's spec and the gateway base-URL variable its requests go through."""

    name: str
    spec: Path
    base_url_var: str
    tag: str


MODULES = (
    Module(
        "auditflow",
        WORKSPACE / "labs64.io-auditflow/auditflow-api/src/main/resources/openapi/openapi-audit-v1.yaml",
        "AUDITFLOW_BASE_URL",
        "auditflow",
    ),
    Module(
        "payment-gateway",
        WORKSPACE / "labs64.io-payment-gateway/payment-gateway-api/src/main/resources/openapi"
        "/openapi-payment-gateway-v1.yaml",
        "PAYMENT_GATEWAY_BASE_URL",
        "payment-gateway",
    ),
    Module(
        "checkout",
        WORKSPACE / "labs64.io-checkout/checkout-be/src/main/resources/openapi/openapi-checkout-v1.yaml",
        "CHECKOUT_BASE_URL",
        "checkout",
    ),
)


@dataclass(frozen=True)
class ProtectedOperation:
    module: Module
    operation_id: str
    method: str
    path_template: str
    sample_path: str
    tenant_required: bool
    scopes: tuple[str, ...]


# --- spec reading -------------------------------------------------------------


def sample_for(schema: dict | None) -> str:
    """A value valid for the parameter's declared type.

    Authentication is decided before path-variable binding, so the value only has
    to parse — never to exist. It does have to route, though: a 404 would be
    reported as an enforcement gap.
    """
    if not isinstance(schema, dict):
        return "sample"
    if schema.get("format") == "uuid":
        return SAMPLE_UUID
    enum_values = schema.get("enum")
    if isinstance(enum_values, list) and enum_values:
        return str(enum_values[0])
    match schema.get("type", "string"):
        case "integer" | "number":
            return "1"
        case "boolean":
            return "true"
        case _:
            return "sample"


def path_parameter_samples(path_item: dict, operation: dict) -> dict[str, str]:
    samples: dict[str, str] = {}
    # Path-level parameters first; the operation may override them.
    for source in (path_item.get("parameters"), operation.get("parameters")):
        if not isinstance(source, list):
            continue
        for parameter in source:
            if isinstance(parameter, dict) and parameter.get("in") == "path" and parameter.get("name"):
                samples[parameter["name"]] = sample_for(parameter.get("schema"))
    return samples


def labs64_auth(source: dict | None) -> dict | None:
    """Return the auth object nested under an OpenAPI ``x-labs64`` extension."""
    if not isinstance(source, dict):
        return None
    labs64 = source.get(LABS64_EXTENSION)
    if not isinstance(labs64, dict):
        return None
    auth = labs64.get(AUTH_PROPERTY)
    return auth if isinstance(auth, dict) else None


def resolve_auth(operation: dict, path_item: dict, spec: dict) -> dict:
    """Effective ``x-labs64.auth``: operation, else path, else spec level.

    Mirrors `AuthPolicy.from` in commons. Keep the two in step — they are the
    same contract read by two languages.
    """
    for source in (operation, path_item, spec):
        candidate = labs64_auth(source)
        if candidate is not None:
            return candidate
    return {}


def protected_operations(module: Module) -> list[ProtectedOperation]:
    if not module.spec.is_file():
        raise FileNotFoundError(
            f"{module.name}: spec not found at {module.spec}. The suite is generated from the "
            f"module repos — check them out as siblings of this one."
        )
    spec = yaml.safe_load(module.spec.read_text()) or {}
    operations: list[ProtectedOperation] = []

    for path_template, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        for method, operation in path_item.items():
            if method.lower() not in HTTP_METHODS or not isinstance(operation, dict):
                continue
            auth = resolve_auth(operation, path_item, spec)
            operation_id = operation.get("operationId") or f"{method}{path_template}"

            if not auth:
                # Operations without auth metadata are public by inference and do
                # not belong in the anonymous-access denial suite.
                continue
            if auth.get("public") is True:
                continue
            if method.lower() in UNSUPPORTED_METHODS:
                continue

            samples = path_parameter_samples(path_item, operation)
            sample_path = TEMPLATE_PARAM.sub(
                lambda m: samples.get(m.group(1), "sample"), path_template
            )
            scopes = auth.get("scopes") or []
            if isinstance(scopes, str):
                scopes = [scopes]
            operations.append(
                ProtectedOperation(
                    module=module,
                    operation_id=operation_id,
                    method=method.upper(),
                    path_template=path_template,
                    sample_path=sample_path,
                    tenant_required=bool(auth.get("tenant")),
                    scopes=tuple(scopes),
                )
            )
    return operations


# --- suite rendering ----------------------------------------------------------


HEADER = """\
*** Settings ***
Documentation    GENERATED — do not edit. Regenerate with
...              ``scripts/generate_auth_enforcement_suite.py`` (CI runs it with ``--check``).
...
...              Roadmap item 2: every operation that declares ``x-labs64.auth`` in a module's
...              OpenAPI spec is called at the gateway edge without credentials and must be
...              refused with 401 or 403. The case list is derived from the same annotation
...              that produces the Cerbos policies and the gateway routes, so the contract and
...              what the edge enforces cannot drift apart silently.
...
...              This is the edge half of item 2. Each backend additionally proves it fails
...              closed on its own, in its ``AuthEnforcementContractTest``. Both layers must
...              hold: the edge is where authorization is enforced, the backend is what
...              survives a misrouted request.
...
...              Operations declaring ``public: true`` are deliberately absent — they are
...              covered by each module's functional suite, not here.
Resource         ../../resources/common.resource
Test Teardown    Delete All Sessions

*** Test Cases ***
"""

CASE = """\
{title}
    [Documentation]    {doc}
    [Tags]    {tags}
    Protected Operation Should Reject Anonymous Access    ${{{base_url_var}}}    {method}    {path}

"""


def render(all_operations: list[ProtectedOperation]) -> str:
    body = [HEADER]
    for operation in all_operations:
        requirement = []
        if operation.tenant_required:
            requirement.append("a tenant")
        if operation.scopes:
            requirement.append("scope(s) " + ", ".join(operation.scopes))
        needs = " and ".join(requirement) if requirement else "authentication"

        body.append(
            CASE.format(
                title=f"{operation.module.name} {operation.method} {operation.path_template} "
                f"rejects anonymous callers",
                doc=f"{operation.operation_id} declares x-labs64.auth requiring {needs}. "
                f"An unauthenticated call must be refused at the edge.",
                # p0-blocker: an endpoint the contract says is protected but the edge
                # serves anonymously is release-blocking by definition, so these gate
                # PRs rather than waiting for the nightly run.
                tags="    ".join(
                    [
                        operation.module.tag,
                        "regression",
                        "auth",
                        "auth-enforcement",
                        "p0-blocker",
                        "generated",
                    ]
                ),
                base_url_var=operation.module.base_url_var,
                method=operation.method,
                path=operation.sample_path,
            )
        )
    return "".join(body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the committed suite differs from what the specs produce",
    )
    args = parser.parse_args()

    all_operations: list[ProtectedOperation] = []
    for module in MODULES:
        try:
            operations = protected_operations(module)
        except (FileNotFoundError, ValueError) as exc:
            print(f"generate_auth_enforcement_suite: {exc}", file=sys.stderr)
            return 2
        if not operations:
            print(
                f"generate_auth_enforcement_suite: {module.name} produced no protected "
                f"operations. Either every operation is public — which needs a deliberate "
                f"review — or the spec failed to parse. An empty suite is not a passing one.",
                file=sys.stderr,
            )
            return 2
        all_operations.extend(operations)

    rendered = render(all_operations)

    if args.check:
        current = OUTPUT.read_text() if OUTPUT.is_file() else ""
        if current != rendered:
            print(
                f"generate_auth_enforcement_suite: {OUTPUT.relative_to(REPO_ROOT)} is out of date "
                f"with the module OpenAPI specs.\nRun scripts/generate_auth_enforcement_suite.py "
                f"and commit the result. An operation that declares x-labs64.auth without a "
                f"generated test is the gap this check exists to catch.",
                file=sys.stderr,
            )
            return 1
        print(
            f"generate_auth_enforcement_suite: up to date — "
            f"{len(all_operations)} protected operation(s) across {len(MODULES)} module(s)."
        )
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered)
    print(
        f"generate_auth_enforcement_suite: wrote {OUTPUT.relative_to(REPO_ROOT)} — "
        f"{len(all_operations)} protected operation(s) across {len(MODULES)} module(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
