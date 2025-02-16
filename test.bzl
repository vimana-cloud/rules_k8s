# Rules and macros for running tests in the context of a running K8s cluster.

def _k8s_cluster_test_impl(ctx):
    # Gather all the setup executables and dependencies.
    setup = []
    setup_runfiles = []
    for action in ctx.attr.setup:
        action = action[DefaultInfo]
        setup.append(action.files_to_run.executable.short_path)
        setup_runfiles.append(action.default_runfiles)

    # Parameterize the runner by expanding the template.
    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._runner_template,
        output = runner,
        substitutions = {
            "{{KUBECTL}}": ctx.file._kubectl_bin.short_path,
            "{{OBJECTS}}": json.encode([object.short_path for object in ctx.files.objects]),
            "{{PORT-FORWARD}}": json.encode(ctx.attr.port_forward),
            "{{HOSTS}}": json.encode(ctx.attr.hosts),
            "{{TEST}}": ctx.executable.test.short_path,
            "{{SETUP}}": json.encode(setup),
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
            allow_files = [".yaml"],
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
