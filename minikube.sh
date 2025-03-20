#!/usr/bin/env bash

# Minikube invokes kubectl.
# Run minikube through this wrapper script
# to set up a temporary `PATH` entry
# to find the pre-built kubectl binary.

minikube="$1"
kubectl="$2"
shift 2

# Create a temporary directory and link the dependency executable(s) into it.
tmp_path="$(mktemp -d)"

# Clean up the temporary directory on exit.
function remove-tmp-directory {
  rm -r "$tmp_path"
}
trap remove-tmp-directory EXIT

# Would be simpler to copy the binary, but kubectl is ~90MB :(.
# Linking (symbolic and physical) is broken in various ways.
# This Bash script functions like a symlink.
function make-alias {
  name="$1"
  path="$2"
  echo -e "#!/usr/bin/env bash\nexec $(printf "%q" "$path") \"\$@\"" \
    > "$tmp_path/$name"
  chmod +x "$tmp_path/$name"
}

make-alias kubectl "$kubectl"

# Append to `PATH` safely: https://unix.stackexchange.com/a/415028.
# Also, can't use `exec` or the `trap` would not run.
PATH="${tmp_path}${PATH:+:${PATH}}" "$minikube" "$@"
