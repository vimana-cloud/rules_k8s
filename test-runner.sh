#!/usr/bin/env bash

# Runner template for `k8s_cluster_test`.
#
# This script is run as a Bazel test.
# information from the analysis phase is injected by template expansion.
# Any identifiers wrapped in {{double curly braces}} should be substituted.
# See `test.bzl`.
#
# These tests must have access to an external K8s cluster,
# which can be configured by setting kubectl's `KUBECONFIG` environment variable.
# Otherwise, kubectl will try `$HOME/.kube/config` by default.

if ! which unshare > /dev/null || [ "$(uname)" != 'Linux' ]
then
  echo >&2 "This test uses Linux mount namespaces and bind-mounting to configure custom DNS."
  echo >&2 "Make sure 'unshare' is installed and you are not on MacOS."
  exit 1
fi

if ! which uuidgen > /dev/null
then
  echo >&2 "This test uses 'uuidgen' to generate a unique K8s namespace name. Make sure it's installed."
  exit 1
fi

# Path to test executable.
test={{TEST}}
# JSON-encoded array of paths to setup executables.
setup={{SETUP}}
# JSON-encoded array of paths to initial K8s resource files.
objects={{OBJECTS}}
# JSON-encoded object mapping gateway names to lists of service names.
services={{SERVICES}}
# Whether to delete the K8s namespace on exit (1 = yes / 0 = no).
cleanup={{CLEANUP}}
# Path to `kubectl` binary.
kubectl={{KUBECTL}}
# Path to `jq` binary.
jq={{JQ}}

# Path to directory where artifacts should be stored.
# https://bazel.build/reference/test-encyclopedia#initial-conditions
artifacts="${TEST_UNDECLARED_OUTPUTS_DIR}"

# Use `jq` to iterate over the JSON-encoded array of setup executables.
# Each executable is represented by an object that looks like:
#     { "path": "../path/to/binary", "env": {"VARNAME": "value"}, "inherited": ["HOME"]}
<<< "$setup" "$jq" --raw-output '
  .[] |
  .path,
  ( .env | to_entries | map("\(.key | @sh)=\(.value | @sh)") | join(" ") ),
  ( .inherited | map(@sh) | join(" ") )
' | while read -r action
do
  read -r env
  read -r inherited
  for key in "${inherited[@]}"
  do
    env+=("$(printf '%q' "$key")=$(printf '%q' "${!key}")")
  done
  ( [ -z "$env" ] || eval "export $env"; "$action" ) || {
    echo >&2 "Failed while running test setup action '$action'"
    exit 2
  }
done || exit $?  # Propagate any error from the piped subshell.

# kubectl will look for a client config
# based on inherited environment variables `KUBECONFIG` and `HOME`.
# Print which one it will use to help with debugging.
# https://stackoverflow.com/a/13864829/5712883
[ -z "${KUBECONFIG+x}" ] \
  && echo >&2 "Using default kubernetes client config '$HOME/.kube/config'." \
  || echo >&2 "Inheriting KUBECONFIG='$KUBECONFIG'."

# Create a new K8s test namespace with a unique, randomized name.
namespace="test-$(uuidgen)"
"$kubectl" create namespace "$namespace" || {
  echo >&2 "Failed to create namespace '$namespace'."
  echo >&2 'Is the cluster running?'
  exit 3
}

# Clean up after the test.
# Can either be called automatically via `trap` if something fails,
# or explicitly at the end if everything (including the test itself) succeeds.
# In the former case, this function is best-effort (we already have an error status).
# In the latter, the cleanup function can cause the test to fail.
function delete-test-namespace {
  local start_time=$(date +%s)
  # When Envoy Gateway is running in Gateway Namespace mode,
  # The time required to delete the test namespace completely dominates the overall test runtime.
  # TODO: See if this can somehow be sped up.
  if "$kubectl" delete namespace "$namespace" --timeout=240s
  then
    local end_time=$(date +%s)
    echo >&2 "Successfully cleaned up the test namespace in $(( end_time - start_time )) seconds."
  else
    echo >&2 "The pods are probably struggling to shut down."
    false  # Indicate cleanup failed.
  fi
}

# If cleanup is enabled, delete the test namespace automatically on early exit.
if (( cleanup ))
then trap delete-test-namespace EXIT
fi

# Create the initial objects for this test, if there are any.
[ "$objects" = '[]' ] && echo >&2 "No initial objects specified." || {
  # Use `jq` to iterate over the JSON-encoded array of objects.
  <<< "$objects" "$jq" --raw-output '.[]' | while read -r object
  do
    "$kubectl" --namespace="$namespace" apply --filename="$object" || {
      echo >&2 "Failed to create initial object '$object'."
      exit 4
    }
  done || exit $?  # Propagate any error from the piped subshell.
}
creation_time=$(date +%s)

# Look up the value of a field of a service by name and JSON field path.
# Retry for up to 15 seconds
# since it may take a few seconds to become available after the service is created.
function lookup-service-field {
  local service="$1"
  local jsonpath="$2"
  local start_time=$(date +%s)
  # Emulate a do-while loop by putting the body logic as a prelude to the condition.
  while
    local value="$(
      "$kubectl" get service "$service" \
        --namespace="$namespace" \
        --output=jsonpath="$jsonpath"
    )"
    [[ $? != 0 ]] && {
      echo >&2 "Declared service '$service' does not exist in the test namespace."
      return 7
    }
    [ -n "$value" ] && {
      echo "$value"
      return 0
    }
    local end_time=$(date +%s)
    local elapsed_time=$(( end_time - start_time ))
    (( elapsed_time < 15 ))
  do
    sleep 0.5
  done
  echo >&2 "Service '$service' lacks field '$jsonpath' after ${elapsed_time} seconds."
  echo >&2 "If this is a Kind cluster, make sure 'cloud-provider-kind' is running."
  return 8
}

# Add entries mapping test domains to gateway cluster IPs
# to the internal CoreDNS instance.
# This enables cert-manager's ACME HTTP-01 self-check to reach solver pods
# so the gateway can be programmed with its TLS certificates.
[ "$services" = '{}' ] || {
  mapfile -t domains < <(<<< "$services" "$jq" --raw-output '.[] | .[]')
  echo >&2 "Adding DNSEntries for domains: ${domains[@]}"

  <<< "$services" "$jq" --raw-output \
    'to_entries[] | "\(.key)\n\(.value | map(@sh) | join(" "))"' \
    | while read -r gateway
  do
    address="$(lookup-service-field "$gateway" '{.spec.clusterIP}')" || exit $?
    read -r domain_names
    eval "domain_names=($domain_names)"
    for domain_name in "${domain_names[@]}"
    do
      echo """---
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: targets
spec:
  endpoints:
  - dnsName: '${domain_name}'
    recordTTL: 300
    recordType: A
    targets:
    - '${address}'
"""
    done
  done \
    | "$kubectl" --namespace="$namespace" apply --filename='-' \
    || exit $?
}

# Print logs from every pod to the test log
"$kubectl" --namespace="$namespace" get pods --output=name \
  | while read -r pod
    do
      # First wait for each pod to be ready.
      "$kubectl" --namespace="$namespace" \
        wait --for=condition=Ready --timeout=30s "$pod" \
          || exit 5
      # Continuously print logs in the background. It will stop when the namespace is deleted.
      # Store them in the artifacts directory in a text file named after the pod
      # (minus the 'pod/' prefix).
      "$kubectl" --namespace="$namespace" logs --follow --all-containers "$pod" \
        > "${artifacts}/${pod:4}.logs.txt" &
    done || exit $?  # Propagate any error from the piped subshell.
ready_time=$(date +%s)
echo >&2 "All pods are ready $(( ready_time - creation_time )) seconds after creation."

# Set up the override file for /etc/hosts, used to configure service routing.
tmp_hosts="$(mktemp)"
[ "$services" = '{}' ] && echo >&2 "No service routing configured." || {
  # Use `jq` to print each key (gateway name) on its own line,
  # followed by the values (service names, concatenated with spaces) on the line below.
  <<< "$services" "$jq" --raw-output 'to_entries[] | "\(.key)\n\(.value | join(" "))"' \
    | while read -r gateway
  do
    "$kubectl" --namespace="$namespace" \
      wait --for=condition=Programmed gateway/"$gateway" --timeout=15s \
        || exit 6
    address="$(lookup-service-field "$gateway" '{.status.loadBalancer.ingress[0].ip}')"
    status=$?
    [[ $status != 0 ]] && exit $status  # Propagate any error from the function call.
    # Keys and values are printed on separate lines,
    # so we know that the total number of lines is a multiple of 2.
    read -r services
    echo "$address $services"
  done || exit $?  # Propagate any error from the piped subshell.
} > "$tmp_hosts"
addressable_time=$(date +%s)
echo >&2 "All gateways have external addresses" \
  "$(( addressable_time - ready_time )) seconds after pods ready."

# Run the test in a new mount namespace, with the override file bind-mounted over /etc/hosts.
echo >&2 "Using '$tmp_hosts' to override '/etc/hosts'."
cmd="mount --bind '$tmp_hosts' /etc/hosts && echo >&2 'Running test...' && exec '$test'"
unshare --map-root-user --mount -- bash -c "$cmd"
test_result=$?

# Might as well clean up the temporary file.
rm "$tmp_hosts"

# If the test failed, return its exit status.
# The cleanup function may run but its success / error status is ignored.
if (( test_result ))
then exit $test_result
fi

# If the test succeeded, and cleanup is enabled,
# run the cleanup function explicitly and fail if cleanup fails.
if (( cleanup ))
then
  # Disable automatic cleanup, because we're calling it explicitly instead.
  trap - EXIT
  delete-test-namespace || exit 9
fi

exit 0
