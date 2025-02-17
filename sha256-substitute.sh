#!/bin/env bash

input="$1"
output="$2"
shift 2
count=$#  # Substitution count.

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
      echo "--expression='s/~~~~${placeholder}~~~~/$name/g'"
      (( placeholder++ ))
    done
  } | xargs sed "$input" > "$output"
} || {
  # Otherwise, copy input to output unchanged.
  cp "$input" "$output"
}
