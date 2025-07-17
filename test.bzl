""" Rules and macros for running tests in the context of a running K8s cluster. """

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//:resource.bzl", "K8sResources", "SetupActions")

_jq_toolchain_type = "@aspect_bazel_lib//lib:jq_toolchain_type"

def _k8s_cluster_test_impl(ctx):
    # Check that none of the declared services are associated with multiple gateways.
    service_gateways = {}
    for gateway, services in ctx.attr.services.items():
        for service in services:
            if service in service_gateways:
                fail(
                    "Service '{}' assigned to conflicting gateways '{}' and '{}'"
                        .format(service, service_gateways[service], gateway),
                )
            service_gateways[service] = gateway

    # Gather all the setup executables and dependencies.
    # If a rule provides an explicit setup actions provider, use that.
    # Otherwise, assume each rule is a simple executable rule.
    setup = []
    setup_runfiles = []
    for action in ctx.attr.setup:
        if SetupActions in action:
            actions = action[SetupActions]
            for executable in actions.executables.to_list():
                setup.append(executable.short_path)
            setup_runfiles.append(actions.runfiles)
        else:
            action = action[DefaultInfo]
            setup.append(action.files_to_run.executable.short_path)
            setup_runfiles.append(action.default_runfiles)

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
            "{{SERVICES}}": shell.quote(json.encode(ctx.attr.services)),
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
            doc = "Test executable to run within the Minikube cluster.",
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
            allow_files = [".json", ".yaml"],
        ),
        "services": attr.string_list_dict(
            doc = "Map gateways names to service domain names." +
                  " Each gateway must have an external IP address. " +
                  " The testing harness will set up transparent DNS and routing for each service.",
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
