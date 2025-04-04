# Kubernetes Bazel Tools

A Bazel module with tools for working with Kubernetes (K8s).

## Rules

- [`//:test.bzl`](test.bzl):
  * `k8s_cluster_test` - Run a test in the context of a running K8s cluster.

## Binaries

Provides a custom tool [`//:tls-generate`](tls-generate.sh)
to generate either self-signed CA credentials or TLS certificates
using OpenSSL.

Automatically downloads and makes available
the following pre-built binaries:

- `//:kubectl`
- `//:kustomize`
- `//:crictl`
- `//:minikube-bin` (x86-64 only) - The [Vimana fork] of [Minikube]
  with support for the `workd` container runtime.
- `//:minikube` - Wrapper script around the raw `:minikube-bin` binary
  that makes it invoke `:kubectl` when it searches the `PATH` for "kubectl".

[Vimana fork]: https://github.com/vimana-cloud/minikube
[Minikube]: https://minikube.sigs.k8s.io/

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
