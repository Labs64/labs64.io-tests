#!/usr/bin/env bash
#
# Wait until every pod in a namespace is Ready, failing fast on the states that never
# recover on their own.
#
#   scripts/wait_for_pods.sh <namespace> [timeout-seconds]
#
# `helmfile apply` returns as soon as manifests are applied, not once anything is
# serving, so CI has to gate on readiness itself or the whole test suite fails with
# connection errors that say nothing about the real problem. The point of this script
# is the failure output: an unreachable stack should be diagnosable from the job log
# alone (which pod, which state, which events, which log lines) without re-running
# anything or downloading an artifact.
set -uo pipefail

NAMESPACE="${1:?usage: wait_for_pods.sh <namespace> [timeout-seconds]}"
TIMEOUT="${2:-600}"

# States a wait can never resolve: the image does not exist, or the pod cannot be
# configured. Retrying past these only burns the job's timeout.
FATAL='ImagePullBackOff|ErrImagePull|InvalidImageName|CreateContainerConfigError|CreateContainerError'
# A crash loop CAN be transient while a dependency comes up, so it is judged by
# restart count rather than treated as immediately fatal.
MAX_RESTARTS=5

deadline=$(( $(date +%s) + TIMEOUT ))

diagnose() {
  echo "--- pods ---"
  kubectl -n "$NAMESPACE" get pods -o wide || true
  echo "--- recent events ---"
  kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
  # Logs only for pods that are not Ready — a healthy pod's logs are noise here.
  for pod in $(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null \
                 | awk '$3 == "Completed" || $3 == "Succeeded" { next }
                        { split($2, r, "/"); if (r[1] != r[2]) print $1 }'); do
    echo "--- $pod (last 40 lines, all containers) ---"
    kubectl -n "$NAMESPACE" logs "$pod" --all-containers --tail=40 2>&1 | tail -40 || true
    kubectl -n "$NAMESPACE" describe pod "$pod" 2>/dev/null | sed -n '/Events:/,$p' | tail -20 || true
  done
}

while :; do
  pods="$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null)"

  if [ -n "$pods" ]; then
    if echo "$pods" | grep -Eq "$FATAL"; then
      echo "::error::Pods in '$NAMESPACE' are in an unrecoverable state — the environment is broken, not the tests."
      diagnose
      exit 1
    fi

    stuck="$(echo "$pods" | awk -v max="$MAX_RESTARTS" '$3 == "CrashLoopBackOff" && $4 + 0 >= max')"
    if [ -n "$stuck" ]; then
      echo "::error::Pods in '$NAMESPACE' have crash-looped more than $MAX_RESTARTS times:"
      echo "$stuck"
      diagnose
      exit 1
    fi

    # Ready when the READY column reads n/n. Completed/Succeeded pods (helm hooks,
    # jobs) report 0/1 forever and are excluded by their STATUS.
    pending="$(echo "$pods" | awk '
      $3 == "Completed" || $3 == "Succeeded" { next }
      { split($2, r, "/"); if (r[1] != r[2]) print }
    ')"
    if [ -z "$pending" ]; then
      echo "All pods in '$NAMESPACE' are ready."
      kubectl -n "$NAMESPACE" get pods
      exit 0
    fi
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "::error::Timed out after ${TIMEOUT}s waiting for pods in '$NAMESPACE' to become ready."
    diagnose
    exit 1
  fi

  sleep 10
done
