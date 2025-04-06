""" Rules and macros for running tests in the context of a running K8s cluster. """

load("@bazel_skylib//lib:shell.bzl", "shell")

def _k8s_cluster_test_impl(ctx):
    # Gather all the setup executables and dependencies.
    setup = []
    setup_runfiles = []
    for action in ctx.attr.setup:
        action = action[DefaultInfo]
        setup.append(action.files_to_run.executable.short_path)
        setup_runfiles.append(action.default_runfiles)

    # `kubectl apply` only accepts certain file suffixes.
    objects = [
        object.short_path
        for object in ctx.files.objects
        if object.short_path.endswith(".json") or
           object.short_path.endswith(".yaml") or
           object.short_path.endswith(".yml")
    ]

    # Parameterize the runner by expanding the template.
    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._runner_template,
        output = runner,
        substitutions = {
            "{{KUBECTL}}": shell.quote(ctx.file._kubectl_bin.short_path),
            "{{OBJECTS}}": shell.quote(json.encode(objects)),
            "{{PORT-FORWARD}}": shell.quote(json.encode(ctx.attr.port_forward)),
            "{{HOSTS}}": shell.quote(json.encode(ctx.attr.hosts)),
            "{{TEST}}": shell.quote(ctx.executable.test.short_path),
            "{{SETUP}}": shell.quote(json.encode(setup)),
            "{{CLEANUP}}": str(int(ctx.attr.cleanup)),
        },
        is_executable = True,
    )
    runfiles = \
        ctx.runfiles(files = ctx.files._kubectl_bin + ctx.files.objects) \
            .merge(ctx.attr.test[DefaultInfo].default_runfiles) \
            .merge_all(setup_runfiles)
    return [
        DefaultInfo(executable = runner, runfiles = runfiles),
        # Inherit `KUBECONFIG` and `HOME` from the host environment
        # so kubectl can find a client configuration.
        RunEnvironmentInfo(inherited_environment = ["KUBECONFIG", "HOME"]),
    ]

k8s_cluster_test = rule(
    implementation = _k8s_cluster_test_impl,
    doc = "Run an integration test within an existing Kubernetes cluster.",
    test = True,
    attrs = {
        "test": attr.label(
            doc = "Test executable to run within the Minikube cluster.",
            executable = True,
            allow_files = True,
            cfg = "exec",
        ),
        "objects": attr.label_list(
            doc = "Initial Kubernetes API objects defined in YAML files." +
                  " Each object is created before the test is started.",
            allow_files = [".json", ".yaml"],
        ),
        "port_forward": attr.string_list_dict(
            doc = "Port forwarding to cluster resources." +
                  " Keys are resource names (e.g. 'svc/foo-gateway-istio')" +
                  " and values are lists of colon-separated port pairs (e.g. '61803:443').",
        ),
        "hosts": attr.string_dict(
            doc = "Map from hosts (domain names) to IP addresses." +
                  " The contents of /etc/hosts will be overridden with this configuration" +
                  " for the duration of the test." +
                  " Can be used with `port_forward` to enable TLS-encrypted access to services.",
        ),
        "setup": attr.label_list(
            doc = "Executable targets to run before each test run.",
        ),
        "cleanup": attr.bool(
            doc = "Whether to delete the K8s namespace (and all the resources within it)" +
                  "at the end of the test.",
            default = True,
        ),
        "_runner_template": attr.label(
            default = "//:test-runner.sh",
            allow_single_file = True,
        ),
        "_kubectl_bin": attr.label(
            executable = True,
            default = "//:kubectl",
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
