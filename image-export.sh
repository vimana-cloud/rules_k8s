#!/usr/bin/env bash

# Given an input directory in `ocidir` layout
# representing an image consisting of a single layer,
# populate an output directory with the contents of the image layer.

set -eo pipefail

input="$1"
output="$2"
jq="$3"
tar="$4"
shift 4

manifest="${input}/manifest.json"

"$jq" --raw-output \
  'if (. | length) == 1 and (.[].Layers | length) == 1 then .[].Layers[] else halt_error(1) end' \
  "$manifest" \
  | {
      read layer
      "$tar" -xzf "${input}/${layer}" -C "$output"
    } || {
      layer_count="$("$jq" --raw-output '.[].Layers | length')"
      echo >&2 "Expected '${manifest}' to contain exactly 1 layer: found ${layer_count}"
      exit 1
    }
