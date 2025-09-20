load("@bazel_skylib//lib:shell.bzl", "shell")

K8sResources = provider(
    "A collection of Kubernetes resources defined by a set of JSON or YAML files.",
    fields = {
        "files": "Dependency set of file objects representing the resources.",
    },
)

SetupActions = provider(
    "A collection of executable actions and their associated runfiles." +
    " These actions are intended to run while setting up a cluster.",
    fields = {
        "executables": "Dependency set of executable file objects.",
        "runfiles": "Merged runfiles of all the executables.",
    },
)

_kubectl_attrs = {
    "srcs": attr.label_list(
        doc = "Kubernetes resources YAML or JSON files.",
        # If a rule provides an explicit K8s resources provider, use that.
        # Otherwise, assume all the default outputs are resource files.
        providers = [[K8sResources], []],
        allow_files = [".json", ".yaml", ".yml"],
    ),
    "_kubectl_bin": attr.label(
        default = ":kubectl",
        executable = True,
        cfg = "exec",
        allow_single_file = True,
    ),
}

def _kubectl_boilerplate(ctx, subcommand):
    """Logic common to both `kubectl_apply` and `kubectl_delete`."""
    # If a rule provides an explicit K8s resources provider, use that.
    # Otherwise, assume all the default outputs are resource files.
    srcs = [
        file
        for src in ctx.attr.srcs
        for file in (
            src[K8sResources].files.to_list() if K8sResources in src else src.files.to_list()
        )
    ]

    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = runner,
        content = "#!/usr/bin/env bash\nexec {} {}{}\n".format(
            shell.quote(ctx.file._kubectl_bin.short_path),
            subcommand,
            "".join([" -f {}".format(shell.quote(src.short_path)) for src in srcs]),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [ctx.file._kubectl_bin] + srcs)
    return [
        DefaultInfo(executable = runner, runfiles = runfiles),
        # Inherit `KUBECONFIG` and `HOME` from the host environment so `kubectl` can function.
        RunEnvironmentInfo(inherited_environment = ["KUBECONFIG", "HOME"]),
    ]

def _kubectl_apply_impl(ctx):
    return _kubectl_boilerplate(ctx, "apply")

kubectl_apply = rule(
    executable = True,
    implementation = _kubectl_apply_impl,
    doc = "Apply a configuration to resource(s) based on a YAML file.",
    attrs = _kubectl_attrs,
)

def _kubectl_delete_impl(ctx):
    return _kubectl_boilerplate(ctx, "delete")

kubectl_delete = rule(
    executable = True,
    implementation = _kubectl_delete_impl,
    doc = "Delete resource(s) from a YAML file.",
    attrs = _kubectl_attrs,
)
