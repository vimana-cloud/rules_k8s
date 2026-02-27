""" Rules and macros for running tests in the context of a running K8s cluster. """

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//:resource.bzl", "K8sResources", "SetupActions")

_jq_toolchain_type = "@aspect_bazel_lib//lib:jq_toolchain_type"

def _setup_action(path, env={}, inherited=[]):
    return struct(path=path, env=env, inherited=inherited)

def _k8s_cluster_test_impl(ctx):
    # Check that none of the declared domains are associated with multiple gateways.
    domain_gateways = {}
    for gateway, domains in ctx.attr.gateway_domains.items():
        for domain in domains:
            if domain in domain_gateways:
                fail(
                    "Domain '{}' assigned to conflicting gateways '{}' and '{}'"
                        .format(domain, domain_gateways[domain], gateway),
                )
            domain_gateways[domain] = gateway

    # Gather all the setup executables and dependencies.
    # If a rule provides an explicit setup actions provider, use that.
    # Otherwise, assume each rule is a simple executable rule.
    setup = []
    setup_runfiles = []
    for action in ctx.attr.setup:
        if SetupActions in action:
            actions = action[SetupActions]
            for executable in actions.executables.to_list():
                setup.append(_setup_action(executable.short_path))
            setup_runfiles.append(actions.runfiles)
        else:
            env = {}
            inherited = []
            if RunEnvironmentInfo in action:
                env = action[RunEnvironmentInfo].environment
                inherited = action[RunEnvironmentInfo].inherited_environment
            setup.append(_setup_action(
                path = action[DefaultInfo].files_to_run.executable.short_path,
                env = env,
                inherited = inherited,
            ))
            setup_runfiles.append(action[DefaultInfo].default_runfiles)

    # If a rule provides an explicit K8s resources provider, use that.
    # Otherwise, assume all the default outputs are resource files.
    objects = [
        file.short_path
        for object in ctx.attr.objects
        for file in (
            object[K8sResources].files.to_list() if K8sResources in object else object.files.to_list()
        )
    ]

    jq_toolchain = ctx.toolchains[_jq_toolchain_type]

    # Parameterize the runner by expanding the template.
    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._runner_template,
        output = runner,
        substitutions = {
            "{{TEST}}": shell.quote(ctx.executable.test.short_path),
            "{{SETUP}}": shell.quote(json.encode(setup)),
            "{{OBJECTS}}": shell.quote(json.encode(objects)),
            "{{GATEWAY_DOMAINS}}": shell.quote(json.encode(ctx.attr.gateway_domains)),
            "{{GATEWAY_SERVICE_SELECTORS}}": shell.quote(json.encode(ctx.attr.gateway_service_selectors)),
            "{{CLEANUP}}": str(int(ctx.attr.cleanup)),
            "{{KUBECTL}}": shell.quote(ctx.file._kubectl_bin.short_path),
            "{{JQ}}": shell.quote(jq_toolchain.jqinfo.bin.short_path),
        },
        is_executable = True,
    )
    runfiles = \
        ctx.runfiles(files = ctx.files._kubectl_bin + ctx.files.objects) \
            .merge(ctx.attr.test[DefaultInfo].default_runfiles) \
            .merge_all(setup_runfiles) \
            .merge(jq_toolchain.default.default_runfiles)
    return [
        DefaultInfo(executable = runner, runfiles = runfiles),
        # Inherit `KUBECONFIG` and `HOME` from the host environment so `kubectl` can function.
        RunEnvironmentInfo(inherited_environment = ["KUBECONFIG", "HOME"]),
    ]

k8s_cluster_test = rule(
    implementation = _k8s_cluster_test_impl,
    doc = "Run an integration test within an existing Kubernetes cluster.",
    test = True,
    attrs = {
        "test": attr.label(
            doc = "Test executable to run against the cluster.",
            executable = True,
            allow_files = True,
            cfg = "exec",
        ),
        "setup": attr.label_list(
            doc = "Executable targets to run before creating any objects.",
            # If a rule provides an explicit setup actions provider, use that.
            # Otherwise, assume each rule is a simple executable rule.
            providers = [[SetupActions], []],
        ),
        "objects": attr.label_list(
            doc = "Initial Kubernetes API objects defined in YAML files." +
                  " Each object is created before the test is started.",
            # If a rule provides an explicit K8s resources provider, use that.
            # Otherwise, assume all the default outputs are resource files.
            providers = [[K8sResources], []],
            allow_files = [".json", ".yaml", ".yml"],
            # The platform configuration should not normally affect resources,
            # however, in cases where resources are both non-deterministic
            # (e.g. generated TLS certificates)
            # and read by both the test harness and the test executable
            # (which would happen if e.g. the test executable needs access to a generated root CA),
            # it's important that the objects have the same configuration as the executable.
            cfg = "exec",
        ),
        "gateway_domains": attr.string_list_dict(
            doc = "Map gateways names to domain names." +
                  " Each gateway must have an external IP address." +
                  " The testing harness will set up internal DNS and local routing" +
                  " for each test domain.",
        ),
        "gateway_service_selectors": attr.string_dict(
            doc = "Map each gateway name" +
                  " to the label selector that should be used to look up its proxy service." +
                  " If omitted, the proxy service is assumed to have" +
                  " the same namespace and name as the gateway itself.",
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
    toolchains = [_jq_toolchain_type],
)
