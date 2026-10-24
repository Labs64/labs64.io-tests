# Group `psp stub` (docs/justfiles.md in labs64.io-workspace). Imported by the justfile.

# Start a blank host-side WireMock process. Provider suites register their versioned
# mappings through the Admin API, so this also works when Docker cannot mount devcontainer paths.
#
# Start a blank WireMock process on the host for the PSP provider suites
[group('psp stub')]
start-wiremock:
    #!/usr/bin/env bash
    set -euo pipefail
    fixture_dir="../labs64.io-payment-gateway/tests/psp-stub/wiremock/mappings"
    if [ ! -d "$fixture_dir" ]; then
      echo "Payment Gateway PSP fixtures not found at $fixture_dir" >&2
      exit 1
    fi
    stub_port="${PSP_STUB_PORT:-8090}"
    port_owner=$(docker ps --filter "publish=$stub_port" --no-trunc --quiet | head -1)
    current_container=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock)
    if [ -n "$port_owner" ] && [ "$port_owner" != "$current_container" ]; then
      echo "PSP stub port $stub_port is already published by another Docker container:" >&2
      docker ps --filter "id=$port_owner" >&2
      echo "Stop that container before running 'just enable-psp-stub'." >&2
      exit 1
    fi
    docker compose -f {{PSP_STUB_COMPOSE}} up -d
    for attempt in {1..30}; do
      container_id=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock)
      health=$(docker inspect "$container_id" | jq --raw-output '.[0].State.Health.Status // .[0].State.Status')
      if [ "$health" = "healthy" ]; then
        echo "PSP stub is ready (published port: $stub_port)"
        exit 0
      fi
      if [ "$health" = "unhealthy" ] || [ "$health" = "exited" ]; then
        break
      fi
      sleep 1
    done
    docker compose -f {{PSP_STUB_COMPOSE}} logs
    echo "PSP stub container did not become healthy" >&2
    exit 1

# Stop the host-side WireMock process
[group('psp stub')]
stop-wiremock:
    docker compose -f {{PSP_STUB_COMPOSE}} down

# Follow the WireMock logs
[group('psp stub')]
show-wiremock-logs:
    docker compose -f {{PSP_STUB_COMPOSE}} logs -f

# Switch an already-running local k3d Payment Gateway deployment to the PSP-stub endpoint.
# This is optional local orchestration; the Robot scenarios themselves remain environment-agnostic.
#
# Start WireMock and point the local Payment Gateway at it (the PSP stub mode)
[group('psp stub')]
enable-psp-stub:
    #!/usr/bin/env bash
    set -euo pipefail
    node="k3d-labs64io-server-0"
    if ! docker inspect "$node" >/dev/null 2>&1; then
      echo "Local k3d cluster is not running; run 'just up' in labs64.io-helm-charts first" >&2
      exit 1
    fi
    restore_on_error() {
      status="${1:-$?}"
      trap - ERR INT TERM
      echo "PSP test environment setup failed; restoring the normal PG configuration" >&2
      just --justfile {{HELM_JUSTFILE}} disable-payment-gateway-stub || true
      just stop-wiremock || true
      exit "$status"
    }
    trap restore_on_error ERR
    trap 'restore_on_error 130' INT
    trap 'restore_on_error 143' TERM
    just start-wiremock
    stub_port="${PSP_STUB_PORT:-8090}"
    stub_host=""
    stub_ip=$(docker exec "$node" nslookup host.docker.internal 2>/dev/null \
      | awk '$1 == "Name:" && $2 == "host.docker.internal" { found=1; next } found && $1 == "Address:" { print $2; exit }' \
      || true)
    if [[ "$stub_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
      && docker exec "$node" wget -q -O /dev/null "http://host.docker.internal:$stub_port/__admin/health"; then
      stub_host="host.docker.internal"
    else
      stub_ip=$(docker exec "$node" ip route 2>/dev/null \
        | awk '$1 == "default" { print $3; exit }' || true)
      if [[ "$stub_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
        && docker exec "$node" wget -q -O /dev/null "http://$stub_ip:$stub_port/__admin/health"; then
        stub_host="$stub_ip"
      fi
    fi
    if [ -z "$stub_host" ]; then
      echo "The k3d node cannot reach the host-side PSP stub on port $stub_port." >&2
      restore_on_error 1
    fi
    stub_url="http://$stub_host:$stub_port"
    host_cidr="$stub_ip/32"
    echo "PSP stub route from k3d: $stub_url ($host_cidr)"
    just --justfile {{HELM_JUSTFILE}} enable-payment-gateway-stub "$host_cidr" "$stub_url"
    just _payment-gateway-settled
    trap - ERR INT TERM

# `kubectl rollout status` (the enable recipe's gate) answers as soon as the new pod is available
# and the old one is on its way out. The scenarios start right after, and a request that lands in
# that window reaches the superseded pod, or a service that still lists it, and fails as a 500 on
# the first PayPal call. Wait for the state the scenarios assume: exactly one pod, Ready, none
# terminating, and the Service pointing at only that pod.
[private]
_payment-gateway-settled:
    #!/usr/bin/env bash
    set -euo pipefail
    ns="${LABS64IO_K8S_NAMESPACE:-labs64io}"
    release="labs64io-payment-gateway"
    for attempt in $(seq 1 90); do
      pods=$(kubectl -n "$ns" get pods -l "app.kubernetes.io/instance=$release" -o json)
      terminating=$(jq '[.items[] | select(.metadata.deletionTimestamp != null)] | length' <<<"$pods")
      live=$(jq '[.items[] | select(.metadata.deletionTimestamp == null)] | length' <<<"$pods")
      ready=$(jq '[.items[] | select(.metadata.deletionTimestamp == null)
                   | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<<"$pods")
      ready_ips=$(jq -r '[.items[] | select(.metadata.deletionTimestamp == null)
                          | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
                          | .status.podIP] | sort | join(",")' <<<"$pods")
      endpoint_ips=$(kubectl -n "$ns" get endpoints "$release" -o json 2>/dev/null \
        | jq -r '[.subsets[]?.addresses[]?.ip] | sort | join(",")' || true)
      if [ "$terminating" = "0" ] && [ "$live" = "1" ] && [ "$ready" = "1" ] && [ -n "$ready_ips" ] \
         && [ "$ready_ips" = "$endpoint_ips" ]; then
        echo "Payment Gateway settled: one ready pod ($ready_ips), none terminating, Service points at it"
        exit 0
      fi
      sleep 2
    done
    echo "Payment Gateway did not settle after the PSP-stub rollout: live=$live ready=$ready terminating=$terminating ready_pods=[$ready_ips] endpoints=[$endpoint_ips]" >&2
    kubectl -n "$ns" get pods -l "app.kubernetes.io/instance=$release" -o wide >&2 || true
    exit 1

# Point the local Payment Gateway back at the real providers, then stop WireMock
[group('psp stub')]
disable-psp-stub:
    #!/usr/bin/env bash
    set -u
    status=0
    just --justfile {{HELM_JUSTFILE}} disable-payment-gateway-stub || status=$?
    just stop-wiremock || {
      stub_status=$?
      if [ "$status" -eq 0 ]; then status=$stub_status; fi
    }
    exit "$status"

# Show the WireMock and Payment Gateway state of the local PSP test setup
[group('psp stub')]
show-psp-stub:
    #!/usr/bin/env bash
    set -u
    container_id=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock 2>/dev/null || true)
    health=""
    if [ -n "$container_id" ]; then
      health=$(docker inspect "$container_id" 2>/dev/null | jq --raw-output '.[0].State.Health.Status // .[0].State.Status' || true)
    fi
    if [ "$health" = "healthy" ]; then
      echo "PSP stub: ready (published port: ${PSP_STUB_PORT:-8090})"
    else
      echo "PSP stub: stopped or unhealthy"
    fi
    application_config=$(kubectl --namespace labs64io get configmap labs64io-payment-gateway-app-ext \
      --output jsonpath='{.data.application\.yaml}' 2>/dev/null \
      || true)
    if [[ "$application_config" == *"api-base-url:"* ]]; then
      echo "Payment Gateway: PSP-stub configuration enabled"
      sed -n '/payment-provider:/,/spring:/p' <<<"$application_config"
    else
      echo "Payment Gateway: normal provider configuration"
    fi

# PSP integration scenarios. A selected PSP test fails when the stub is absent; it never
# silently skips and turns a broken nightly setup green.
#
# Run the PSP integration scenarios against the stub
[group('psp stub')]
test-psp:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "${PSP_STUB_BASE_URL:-}" ]; then
      if ! curl --fail --silent "$PSP_STUB_BASE_URL/__admin/health" >/dev/null; then
        echo "PSP stub is not reachable at $PSP_STUB_BASE_URL" >&2
        exit 1
      fi
    else
      container_id=$(docker compose -f {{PSP_STUB_COMPOSE}} ps --quiet wiremock)
      health=$(docker inspect "$container_id" | jq --raw-output '.[0].State.Health.Status // .[0].State.Status')
      if [ "$health" != "healthy" ]; then
        echo "Local PSP stub is not healthy; run 'just enable-psp-stub' first" >&2
        exit 1
      fi
      for candidate in \
        "http://localhost:${PSP_STUB_PORT:-8090}" \
        "http://host.docker.internal:${PSP_STUB_PORT:-8090}"; do
        if curl --connect-timeout 2 --max-time 3 --fail --silent "$candidate/__admin/health" >/dev/null; then
          export PSP_STUB_BASE_URL="$candidate"
          break
        fi
      done
      if [ -z "${PSP_STUB_BASE_URL:-}" ]; then
        echo "PSP stub container is healthy, but Robot runner cannot reach its published port" >&2
        exit 1
      fi
    fi
    echo "PSP stub Robot endpoint: $PSP_STUB_BASE_URL"
    just _run --include psp-stub {{ALL_TESTS}}
