#!/usr/bin/env bash
#
# Mirror the ecosystem's :edge images into a local (k3d) registry.
#
#   scripts/mirror_edge_images.sh [registry]        # default: localhost:5005
#
# Every module publishes <image>:edge to Docker Hub after a green master build (the
# `edge-image` jobs in each repo's CI workflow, via labs64.io-workspace's reusable
# docker-publish.yml). That is the artifact the nightly regression deploys: today's
# master, already built and already proven green by its own module's suite — instead
# of rebuilding the whole ecosystem from source on every run.
#
# The Helmfile local profile pins every module image to <registry>/<name>:latest
# (labs64.io-helm-charts/overrides/*/values.local.yaml), so each edge image is
# re-tagged to exactly that name. The local registry's `latest` therefore means
# "current edge", and no chart or override has to know where the image came from.
#
# Also useful on a developer machine: it fills the same registry `just build` fills,
# without a full Maven/npm build, when you want to run the stack rather than change it.
set -uo pipefail

REGISTRY="${1:-localhost:5005}"

# Local registry name == Docker Hub repository name for every module image, so one
# list drives both sides. Keep in sync with the image references in
# labs64.io-helm-charts/overrides/*/values.local.yaml.
IMAGES="
auditflow
auditflow-transformer
auditflow-sink
traefik-authproxy
payment-gateway
customer-portal-ui
"

# Which CI workflow publishes each image, so a missing tag names its own fix.
publisher() {
  case "$1" in
    auditflow|auditflow-transformer|auditflow-sink) echo "labs64.io-auditflow/.github/workflows/labs64io-ci.yml" ;;
    traefik-authproxy)   echo "labs64.io-authproxy/.github/workflows/labs64io-ci.yml" ;;
    payment-gateway)     echo "labs64.io-payment-gateway/.github/workflows/labs64io-be-ci.yml" ;;
    checkout)            echo "labs64.io-checkout/.github/workflows/labs64io-be-ci.yml" ;;
    checkout-ui)         echo "labs64.io-checkout/.github/workflows/labs64io-fe-ci.yml" ;;
    customer-portal-ui)  echo "labs64.io-customer-portal/.github/workflows/labs64io-fe-ci.yml" ;;
    *)                   echo "(unknown)" ;;
  esac
}

missing=""
for image in $IMAGES; do
  echo "=== pulling labs64/${image}:edge ==="
  # Pull everything before pushing anything: a half-mirrored registry deploys a
  # mixed-vintage stack, which is worse to debug than not deploying at all.
  docker pull "labs64/${image}:edge" || missing="${missing} ${image}"
done

if [ -n "$missing" ]; then
  echo "::error::No :edge image published for:${missing}"
  echo
  echo "An :edge tag appears the first time that module's CI runs green on master."
  echo "If one is missing, either that workflow has never run since its edge-image job"
  echo "was added, or its last master build failed. Publishers:"
  for image in $missing; do
    printf '  labs64/%-22s <- %s\n' "${image}:edge" "$(publisher "$image")"
  done
  exit 1
fi

# Record exactly which build each image came from. When a nightly goes red, the
# first question is "against what?" — this answers it without guessing from
# timestamps, since :edge moves on every master push.
summary_rows=""
for image in $IMAGES; do
  target="${REGISTRY}/${image}:latest"
  digest="$(docker inspect --format '{{index .RepoDigests 0}}' "labs64/${image}:edge" 2>/dev/null || echo 'labs64/'"${image}"'@unknown')"
  echo "=== ${digest} -> ${target} ==="
  docker tag "labs64/${image}:edge" "$target" || exit 1
  docker push "$target" || exit 1
  summary_rows="${summary_rows}| \`${image}\` | \`${digest#*@}\` |
"
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Edge images under test"
    echo
    echo "Mirrored from Docker Hub \`:edge\` into \`${REGISTRY}\` as \`:latest\`."
    echo
    echo "| Image | Source digest |"
    echo "| --- | --- |"
    printf '%s' "$summary_rows"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "=== registry catalog ==="
curl -fsS "http://${REGISTRY}/v2/_catalog" || true
echo
