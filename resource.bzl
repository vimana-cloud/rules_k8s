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
            shell.quote(ctx.executable._kubectl_bin.short_path),
            subcommand,
            "".join([" -f {}".format(shell.quote(src.short_path)) for src in srcs]),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [ctx.executable._kubectl_bin] + srcs)
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
    doc = "Apply a configuration to resource(s) in a cluster, based on a YAML file.",
    attrs = _kubectl_attrs,
)

def _kubectl_delete_impl(ctx):
    return _kubectl_boilerplate(ctx, "delete")

kubectl_delete = rule(
    executable = True,
    implementation = _kubectl_delete_impl,
    doc = "Delete resource(s) from a cluster, based on a YAML file.",
    attrs = _kubectl_attrs,
)

def _oras_push_impl(ctx):
    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = runner,
        content = "#!/usr/bin/env bash\nexec {} {} {} {} {} {}{} \"$@\"\n".format(
            shell.quote(ctx.executable._oras_push_bin.short_path),
            shell.quote(ctx.executable._oras_bin.short_path),
            shell.quote(ctx.file.src.short_path),
            shell.quote(ctx.attr.repository),
            shell.quote(ctx.attr.artifact_type),
            str(len(ctx.attr.remote_tags)),
            "".join([" {}".format(shell.quote(tag)) for tag in ctx.attr.remote_tags]),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            ctx.executable._oras_push_bin,
            ctx.executable._oras_bin,
            ctx.file.src,
        ],
    )
    return [
        DefaultInfo(executable = runner, runfiles = runfiles),
        # Inherit the environment variables used to load Docker credential helpers.
        # ORAS should know what to do with these.
        # https://docs.docker.com/reference/cli/docker/#environment-variables
        # https://github.com/docker/cli/pull/6008
        RunEnvironmentInfo(
            inherited_environment = ["DOCKER_CONFIG", "DOCKER_AUTH_CONFIG", "HOME"],
        ),
    ]

oras_push = rule(
    executable = True,
    implementation = _oras_push_impl,
    doc = "Push an arbitrary file to an OCI registry using ORAS.",
    attrs = {
        "src": attr.label(
            doc = "File to push.",
            allow_single_file = True,
        ),
        "repository": attr.string(
            doc = "Repository URL where the image will be signed at," +
                  " e.g. `index.docker.io/<user>/image`." +
                  " Digests and tags are not allowed." +
                  " If this attribute is not set," +
                  " the repository must be passed at runtime via the `--repository` flag.",
        ),
        "remote_tags": attr.string_list(
            doc = "A list of tags to apply to the image after pushing.",
        ),
        "artifact_type": attr.string(
            doc = "Artifact type for the manifest.",
            default = "application/vnd.unknown.artifact.v1",
        ),
        # The ORAS CLI binary.
        "_oras_bin": attr.label(
            default = ":oras",
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
        # A wrapper script to process command-line arguments before invoking the ORAS binary.
        "_oras_push_bin": attr.label(
            default = ":oras-push.sh",
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
    },
)
