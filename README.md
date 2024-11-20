# Kubernetes Bazel Tools

A Bazel module with tools for working with Kubernetes (K8s).

## Rules

- [`//:resource.bzl`](resource.bzl):
  * `k8s_secret_tls` - Convert PEM-encoded private key and certificate files
    into a K8s secret resource.
- [`//:test.bzl`](test.bzl):
  * `k8s_cluster_test` - Run a test in the context of a running K8s cluster.

## Caveats

- Currently works only for the following execution platforms
  (due to a dependency on Bash and downloading pre-built binaries):
  * `aarch64-linux`
  * `aarch64-macos`
  * `x86_64-linux`
  * `x86_64-macos`
- Running cluster tests currently works only on Linux
  due to its use of Linux mount namespaces and bind-mounting
  for custom DNS configuration.