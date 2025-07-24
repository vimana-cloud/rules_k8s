# Kubernetes Bazel Tools

A Bazel module with tools for working with Kubernetes (K8s).

## Rules

- [`//:test.bzl`](test.bzl):
  * `k8s_cluster_test` - Run a test in the context of a running K8s cluster.

## Binaries

Downloads and makes available
the following pre-built binaries:

- `//:kubectl`
- `//:helm`
- `//:kustomize`
- `//:crictl`
- `//:kops`
- `//:crane`
- `//:minikube-bin` - The [Vimana fork] of [minikube]
  with support for the `workd` container runtime.
- `//:minikube` - Wrapper script around the raw `:minikube-bin` binary
  that makes it invoke `:kubectl` when it searches the `PATH` for "kubectl".

Also provides a custom tool [`//:tls-generate`]
to generate either self-signed CA credentials or TLS certificates
using OpenSSL.

[Vimana fork]: https://github.com/vimana-cloud/minikube
[minikube]: https://minikube.sigs.k8s.io/
[`//:tls-generate`]: tls-generate.sh

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
