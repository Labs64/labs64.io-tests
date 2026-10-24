# Group `setup` (docs/justfiles.md in labs64.io-workspace). Imported by the justfile.

# Create the virtualenv (if missing) and install/refresh dependencies
[group('setup')]
install-venv:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d .venv ]; then
        python3 -m venv .venv
    fi
    .venv/bin/pip install -q -r requirements.txt

# The suites run in a virtualenv (`just install-venv`, done by every test recipe); the PSP stub needs Docker and jq,
# the local-cluster recipes kubectl.
#
# Check the tools this repository's recipes use
[group('setup')]
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    missing=0
    check() { # name, command, version command...
        local name=$1 cmd=$2 have
        if ! command -v "$cmd" >/dev/null 2>&1; then echo "❌ $name: not installed"; missing=$((missing + 1)); return; fi
        have="$("${@:3}" 2>&1 || true)"; have="${have%%$'\n'*}"
        echo "✅ $name: $have"
    }
    check python3 python3 python3 --version
    check docker  docker  docker --version
    check jq      jq      jq --version
    check kubectl kubectl kubectl version --client
    check curl    curl    curl --version
    for repo in labs64.io-auditflow labs64.io-payment-gateway; do
        if [ -d "../$repo/tests/e2e" ]; then echo "✅ ../$repo/tests/e2e"; else echo "❌ ../$repo/tests/e2e: clone $repo next to this repository (the workspace's just clone)"; missing=$((missing + 1)); fi
    done
    if [ -x .venv/bin/robot ]; then echo "✅ .venv: $(.venv/bin/robot --version 2>&1 | head -1)"; else echo "➖ .venv not created yet: just install-venv (every test recipe does it)"; fi
    [ "$missing" -eq 0 ]
