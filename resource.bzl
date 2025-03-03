load(":private.bzl", "format_placeholder", "write_with_sha256_substitution")

# Rules for creating and managing K8s resource objects.
load(":registry.bzl", "vimana_push")

# gRPC services should always use this port number (which is virtual anyway).
_GRPC_CONTAINER_PORT = 443

def k8s_vimana_domain(name, registry, id, aliases = None, services = None, reflection = False, cluster_registry = None):
    """
    Statically build, push and deploy an entire Vimana domain.
    Used to bootstrap a cluster with the API and any other pre-existing services.

    Defines an executable "push" rule for each component
    that pushes its module and metadata as a container
    to an image registry based at `registry`.
    Also defines a single buildable rule
    for the K8s resources of the entire domain.

    Parameters:
        name (str): Name for the build rule of domain's K8s resources.
        registry (str): Container image registry URL root, e.g. `http://localhost:5000`.
        id (str): Canonical domain ID, e.g. `0123456789abcdef0123456789abcdef`.
        aliases ([str]): List of domain aliases, e.g. `[example.com, example.net]`.
        services ({str: [component]}):
            Map from service names to lists of component objects,
            where each component object is defined using the `component` constructor.
        reflection (bool): Whether to enable reflection on every service in the domain.
        cluster_registry (str): Registry URL to use from within the cluster;
                                default is to use the same value as `registry`.
    """
    aliases = aliases or []
    services = services or {}
    cluster_registry = cluster_registry or registry

    rules = []
    placeholder = 0
    names = []
    resources = []
    for service_name, components in services.items():
        backends = []
        for component in components:
            # One executable push action per component.
            vimana_push(
                name = component.name,
                component = component.module,
                metadata = component.metadata,
                domain_id = id,
                service = service_name,
                version = component.version,
                registry = registry,
            )

            # Metadata common to all component-specific resources.
            component_labels = {
                "vimana.host/domain": id,
                "vimana.host/service": service_name,
                "vimana.host/version": component.version,
            }

            # The canonical component name cannot be used for `metadata.name` as-is
            # because it's not a valid DNS fragment.
            # Instead, keep track of the name and leave a placeholder
            # so we can substitute in a real hash value in the execution phase.
            component_metadata = {
                "name": format_placeholder(placeholder),
                "labels": component_labels,
            }
            names.append("{}:{}@{}".format(id, service_name, component.version))
            placeholder += 1

            # It's called a 'Service' resource but it represents a Vimana component.
            # https://kubespec.dev/v1/Service
            resources.append({
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": component_metadata,
                "spec": {
                    # Every component serves cleartext HTTP/2 (gRPC) traffic.
                    # Public TLS termination and JSON transcoding happens at the Gateway,
                    # and mTLS for mesh traffic is provided transparently by Ztunnel.
                    "ports": [{
                        "name": "grpc",
                        "port": _GRPC_CONTAINER_PORT,
                        "appProtocol": "kubernetes.io/h2c",
                    }],
                    "selector": component_labels,
                },
            })

            # One deployment resource per component as well.
            # https://kubespec.dev/apps/v1/Deployment
            resources.append({
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": component_metadata,
                "spec": {
                    "replicas": 1,
                    "selector": {"matchLabels": component_labels},
                    "template": {
                        "metadata": {"labels": component_labels},
                        "spec": {
                            "runtimeClassName": "workd-runtime-class",
                            "serviceAccountName": component.service_account,
                            # Workd pods have a single container, called 'app'.
                            "containers": [{
                                "name": "app",
                                "image": "{}/{}/{}:{}".format(
                                    cluster_registry,
                                    id,
                                    _hexify(service_name),
                                    component.version,
                                ),
                                # TODO: Determine testability implications of image pull policy.
                                # "imagePullPolicy": "Always",
                                "ports": [{"containerPort": _GRPC_CONTAINER_PORT}],
                                "env": component.environment,
                            }],
                        },
                    },
                },
            })

            # One (weighted) backend per component.
            # https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.GRPCBackendRef
            backends.append({
                "name": component.version,
                "port": _GRPC_CONTAINER_PORT,
                "weight": component.weight,
            })

        # One rule per service for the domain-specific route.
        # https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.GRPCRouteRule
        rules.append({
            "matches": [{"method": {"type": "Exact", "service": service_name}}],
            "backendRefs": backends,
        })

    resources.append({
        # One route per domain.
        # https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.GRPCRoute
        "apiVersion": "gateway.networking.k8s.io/v1",
        "kind": "GRPCRoute",
        "metadata": {
            "name": id,
            "labels": {
                "vimana.host/domain": id,
            },
        },
        "spec": {
            # All routes are parented by the global gateway.
            "parentRefs": [{"name": "vimana-gateway"}],
            # One hostname for the canonical domain and one for each alias.
            "hostnames": ["{}.app.vimana.host".format(id)] + aliases,
            "rules": rules,
        },
    })

    # One buildable K8s resource file for the overall domain.
    write_with_sha256_substitution(
        name = name,
        out = name + ".json",
        # Print one JSON resource per line.
        content = [json.encode(resource) for resource in resources],
        # Forward canonical component names to the execution phase
        # so they can be hashed with SHA-256.
        # See `sha256-substitute.sh`.
        substitutes = names,
    )

def k8s_vimana_component(name, version, weight, module, metadata, environment = None, service_account = ""):
    """
    Return a component object that can be used with `k8s_vimana_domain`.
    `environment` should be a list of objects returned by `env_from_field_ref` or similar functions.
    """

    # Just save all the info. It's processed in `k8s_vimana_domain`.
    return struct(
        name = name,
        version = version,
        weight = weight,
        module = module,
        metadata = metadata,
        environment = environment or [],
        service_account = service_account,
    )

def env_from_field_ref(name, field_path):
    """ Return an EnvVar object loading the value from a field reference. """

    # https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#envvar-v1-core
    return {
        "name": name,
        "valueFrom": {
            "fieldRef": {
                "fieldPath": field_path,
            },
        },
    }

def k8s_secret_tls(name, key, cert):
    """ Convert TLS private key / certificate PEM files into a YAML-encoded K8s secret object. """
    key = native.package_relative_label(key)
    cert = native.package_relative_label(cert)
    _kubectl_create(
        name = name,
        cmd =
            "secret tls {} --dry-run=client --key=$(location {}) --cert=$(location {})"
                .format(name, key, cert),
        srcs = [key, cert],
    )

def _kubectl_create(name, cmd, srcs = None):
    """ Convenience method for generating a JSON resource with `kubectl create`. """
    srcs = srcs or []
    native.genrule(
        name = name,
        srcs = srcs,
        outs = [name + ".yaml"],
        cmd = "./$(location {}) create {} --output=yaml > \"$@\"".format(Label("//:kubectl"), cmd),
        tools = [Label("//:kubectl")],
    )

_hex_digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]

def _hexify(name):
    """ Convert a string to nibble-wise little-endian hexadecimal. """
    hex = []
    for character in name.elems():
        # Bazel doesn't have Python's `ord`,
        # but `hash` returns the same result for all single ASCII characters:
        # https://bazel.build/rules/lib/globals/all#hash.
        point = hash(character)
        if point > 127:
            fail("Hexification only supports ASCII strings")
        hex.append(_hex_digits[point % 16])
        hex.append(_hex_digits[point // 16])
    return "".join(hex)
