# Rules for creating and managing K8s resource objects.

def k8s_secret_tls(name, key, cert):
    """ Convert TLS private key / certificate PEM files into a K8s secret object. """
    key = native.package_relative_label(key)
    cert = native.package_relative_label(cert)
    native.genrule(
        name = name,
        srcs = [key, cert],
        outs = [name + ".yaml"],
        cmd =
            "./$(location {}) create secret tls {} --dry-run=client --key=$(location {}) --cert=$(location {}) --output=yaml > \"$@\""
                .format(Label("//:kubectl"), name, key, cert),
        tools = [Label("//:kubectl"), key, cert],
    )
