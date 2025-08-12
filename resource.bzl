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

def _kubectl_apply_impl(ctx):
    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = runner,
        content = "#!/usr/bin/env bash\nexec {} apply{}\n".format(
            shell.quote(ctx.file._kubectl_bin.short_path),
            "".join([" -f {}".format(shell.quote(src.short_path)) for src in ctx.files.srcs]),
        ),
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [ctx.file._kubectl_bin] + ctx.files.srcs)
    return [
        DefaultInfo(executable = runner, runfiles = runfiles),
        # Inherit `KUBECONFIG` and `HOME` from the host environment so `kubectl` can function.
        RunEnvironmentInfo(inherited_environment = ["KUBECONFIG", "HOME"]),
    ]


kubectl_apply = rule(
    executable = True,
    implementation = _kubectl_apply_impl,
    doc = "Apply a configuration to a resource(s) based on a YAML file.",
    attrs = {
        "srcs": attr.label_list(
            doc = "",
            allow_files = [".json", ".yaml", ".yml"],
        ),
        "_kubectl_bin": attr.label(
            default = ":kubectl",
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
    },
)
