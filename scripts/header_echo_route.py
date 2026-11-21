#!/usr/bin/env python3
"""Turn a real module HTTPRoute into the route of the header-echo fixture.

Reads the module's HTTPRoute (JSON, `kubectl get httproute <name> -o json`) on stdin and prints
an HTTPRoute that keeps the first protected rule exactly as the chart rendered it (path match
and the whole filter chain: X-Auth-* strip, ForwardAuth, rate limit, ...) and changes only what
makes it a fixture: its name and label, its host, and its backend (the echo Service).

The Auth Gateway decides per path, so the echo has to answer the module's real path; the host is
what keeps it apart from the module. A rule is "protected" when a filter references a Middleware
whose name ends in `-auth` (chart-libs `gateway-routes` emits it only for non-public routes).

Usage: header_echo_route.py <name> <host> <label key=value> < route.json
"""

from __future__ import annotations

import json
import sys


def is_protected(rule: dict) -> bool:
    return any(
        f.get("type") == "ExtensionRef" and f["extensionRef"]["name"].endswith("-auth")
        for f in rule.get("filters", [])
    )


def echo_route(source: dict, name: str, host: str, label: str) -> dict:
    rules = [r for r in source["spec"]["rules"] if is_protected(r)]
    if not rules:
        raise SystemExit(f"{source['metadata']['name']}: no protected rule (none references a -auth Middleware)")
    key, _, value = label.partition("=")
    rule = {k: v for k, v in rules[0].items() if k != "backendRefs"}
    rule["backendRefs"] = [{"name": name, "port": 8080}]
    return {
        "apiVersion": source["apiVersion"],
        "kind": "HTTPRoute",
        "metadata": {"name": name, "namespace": source["metadata"]["namespace"], "labels": {key: value}},
        "spec": {"parentRefs": source["spec"]["parentRefs"], "hostnames": [host], "rules": [rule]},
    }


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    json.dump(echo_route(json.load(sys.stdin), *sys.argv[1:]), sys.stdout)
