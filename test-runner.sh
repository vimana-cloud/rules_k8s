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

if ! which jq > /dev/null
then
  echo >&2 "This test uses 'jq' to parse JSON parameters. Make sure it's installed."
  exit 1
fi

if ! which nc > /dev/null
then
  echo >&2 "This test uses 'nc' (netcat) to verify port bindings. Make sure it's installed."
  exit 1
fi

# Path to kubectl binary.
kubectl='{{KUBECTL}}'
# JSON-encoded array of paths to initial K8s object definitions (YAML files).
objects='{{OBJECTS}}'
# JSON-encoded object mapping resource names to arrays of colon-separated port pairs.
port_forward='{{PORT-FORWARD}}'
# JSON-encoded object mapping host names to IP addresses.
hosts='{{HOSTS}}'
# Path to test executable.
test='{{TEST}}'
# Path to directory where artifacts should be stored.
# https://bazel.build/reference/test-encyclopedia#initial-conditions
artifacts="${TEST_UNDECLARED_OUTPUTS_DIR}"

# kubectl will look for a client config
# based on inherited environment variables `KUBECONFIG` and `HOME`.
# Print which one it will use to help with debugging.
# https://stackoverflow.com/a/13864829/5712883
[ -z "${KUBECONFIG+x}" ] \
  && echo >&2 "Using default kubernetes client config '$HOME/.kube/config'." \
  || echo >&2 "Using inherited \`\$KUBECONFIG\` '$KUBECONFIG'."

# Create a new K8s test namespace with a unique, randomized name.
namespace="test-$(uuidgen)"
"$kubectl" create namespace "$namespace" && {

  # Delete the test namespace on exit.
  function delete-test-namespace {
    "$kubectl" delete namespace "$namespace"
  }
  trap delete-test-namespace EXIT

  # Create the initial objects for this test, if there are any.
  [ "$objects" = '[]' ] && echo >&2 "No initial objects specified." || {
    # Use `jq` to iterate over the JSON-encoded array of objects.
    <<< "$objects" jq --raw-output '.[]' | while read -r object
    do
      "$kubectl" --namespace="$namespace" apply --filename="$object" || {
        echo >&2 "Failed to create initial object '$object'."
        exit 1
      }
    done
  }

  # Print logs from every pod to the test log
  "$kubectl" --namespace="$namespace" get pods --output=name | while read -r pod
  do
    # First wait for each pod to be ready.
    "$kubectl" --namespace="$namespace" wait --for=condition=Ready "$pod"
    # Continuously print logs in the background. It will stop when the namespace is deleted.
    # Store them in the artifacts directory in a text file name after the pod (minus the 'pod/' prefix).
    "$kubectl" --namespace="$namespace" logs --follow --all-containers "$pod" \
      > "${artifacts}/${pod:4}.logs.txt" &
  done

  # Set up port forwarding, if configured.
  [ "$port_forward" = '{}' ] && echo >&2 "No port-forwarding configured." || {
    # Use `jq` to denormalize the JSON-encoded object:
    # each item of each value array is printed on its own line,
    # immediately preceded by its key on the line above
    # (so each key appears as many times as it has items in its value array).
    <<< "$port_forward" jq --raw-output 'to_entries[] | .key as $key | .value[] | "\($key)\n\(.)"' \
      | while read -r resource
    do
      # Keys and values are printed on separate lines,
      # so we know that the total number of lines is a multiple of 2.
      read -r mapping
      # Port-forward in the background. It will stop when the namespace is deleted.
      "$kubectl" --namespace="$namespace" port-forward "$resource" "$mapping" &
    done

    # Port-forwarding can take a bit of time to set up.
    # Use netcat to poll each local port until it becomes available.
    <<< "$port_forward" jq --raw-output 'to_entries[] | .value[] | split(":")[0]' \
      | while read -r port
    do
      until nc --zero localhost "$port"
      do sleep 0.5s
      done
    done
  }

  # Set up the override file for /etc/hosts.
  tmp_hosts="$(mktemp)"
  echo >&2 "Using '$tmp_hosts' as temporary override for '/etc/hosts'."
  # Use `jq` to print each value-key pair on its own line in the override file.
  <<< "$hosts" jq --raw-output 'to_entries[] | "\(.value) \(.key)"' > "$tmp_hosts"

  # Run the test in a new mount namespace, with the override file bind-mounted over /etc/hosts.
  unshare --map-root-user --mount -- \
    bash -c "mount --bind '$tmp_hosts' /etc/hosts && echo >&2 'Running test executable.' && exec '$test'"
  test_result="$?"

  # Might as well clean up the temporary file.
  rm "$tmp_hosts"
  
  exit "$test_result"
}