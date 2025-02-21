#!/usr/bin/env bash

# Copy a file template from the input file to the output file,
# Replacing occurrences of the form `{~N~}`
# with something odd:
# a UUID derived from the SHA-256 hash of the 2+Nth argument.
# That's because this action is called at the end of the `k8s_vimana_domain` process
# to do one thing that's apparently impossible in Starlark: SHA-256.
# If we could do that in `resource.bzl`, this wouldn't exist.
#
# This hexadecimal UUID can be used for e.g. `metadata.name` on Services and Deployments,
# which has strict format requirements that preclude using the canonical component name.
# So, instead, we just hash the component name and use that as the UUID
# (the "substitution" arguments should all be component names).

input="$1"   # Input file path.
output="$2"  # Output file path.
shift 2
# The rest of the arguments are "substitutions".
count=$#     # Substitution count.

(( count > 0 )) && {
  # If there are substitutions,
  # run `sed` with one expression for each substitution
  # (collected with `xargs`).
  {
    placeholder=0
    for substitute in "$@"
    do
      # The substitute is hashed, hex-formatted, prefixed with 'f',
      # and limited to 56 characters total
      # so it will always be a valid K8s `metadata.name` (RFC 1035),
      # deterministic and reasonably unique.
      # https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#rfc-1035-label-names
      name="f$(echo -n "$substitute" | sha256sum | head --bytes=55)"
      echo "--expression='s/{~${placeholder}~}/$name/g'"
      (( placeholder++ ))
    done
  } | xargs sed "$input" > "$output"
} || {
  # Otherwise, copy input to output unchanged.
  cp "$input" "$output"
}
