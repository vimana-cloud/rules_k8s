#!/usr/bin/env bash

# Push an arbitrary file to an OCI repository using ORAS.

set -eo pipefail

# Convert the arguments into an array so we can slice it.
args=("$@")
# Path to `oras` binary.
oras="${args[0]}"
# Path to payload file to push.
src="${args[1]}"
# OCI repository name.
repository="${args[2]}"
# OCI repository name.
artifact_type="${args[3]}"
# Number of tags.
tag_count="${args[4]}"
# Array of tags.
tags="${args[@]:5:$tag_count}"
shift $(( 5 + tag_count ))

# Additional arguments for `oras push`.
options=()

while (( $# > 0 )); do
  case $1 in
    -t|--tag)
      tags+=( "$2" )
      shift
      ;;
    --tag=*)
      tags+=( "${1#--tag=}" )
      ;;
    -r|--repository)
      repository="$2"
      shift
      ;;
    --repository=*)
      repository="${1#--repository=}"
      ;;
    *)
      options+=( "$1" )
      ;;
  esac
  shift
done

if [[ -z "${repository}" ]]; then
  echo >&2 '[ERROR] Repository not set: pass `--repository` flag'
  exit 1
fi

exec "$oras" push --artifact-type="$artifact_type" "${options[@]}" "$repository:$(IFS=,; echo "${tags[*]}")" "$src"
