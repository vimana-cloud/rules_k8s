#!/usr/bin/env bash

set -eo pipefail

envoy_gateway_helm_export="$1"
shift 1

# Just make sure the exported chart has the `Chart.yaml` file in the expected place.
chart_metadata="${envoy_gateway_helm_export}/gateway-helm/Chart.yaml"
[ -f "$chart_metadata" ] || {
  echo >&2 "Expected to find missing file ${chart_metadata}"
  exit 1
}
