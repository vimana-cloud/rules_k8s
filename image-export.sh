#!/usr/bin/env bash

# Given an input directory in `ocidir` layout representing an image,
# populate an output directory with the contents of the image layer.

set -eo pipefail

input="$1"
output="$2"
jq="$3"
tar="$4"
shift 4

manifest="${input}/manifest.json"

{
  "$jq" --raw-output \
    'if (. | length) == 1 then .[].Layers[] else halt_error(1) end' \
    "$manifest" || {
      manifest_count="$("$jq" --raw-output '. | length')"
      echo >&2 "Expected '${manifest}' to contain exactly 1 manifest: found ${manifest_count}"
      exit 1
    }
} | {
  while read layer
  do
    "$tar" -xzf "${input}/${layer}" -C "$output" \
      || echo >&2 "Error processing '${layer}'"
  done
}
