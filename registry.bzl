# Rule to push Vimana Wasm "containers" to a container registry.
load(":private.bzl", "bash_quote")

def _vimana_push_impl(ctx):
    runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = runner,
        content = "#!/bin/env bash\n{} {} {} {} {} {} {}".format(
            bash_quote(ctx.file._vimana_push.short_path),
            bash_quote(ctx.attr.registry),
            bash_quote(ctx.attr.domain_id),
            bash_quote(ctx.attr.service),
            bash_quote(ctx.attr.version),
            bash_quote(ctx.file.component.short_path),
            bash_quote(ctx.file.metadata.short_path),
        ),
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        files = [ctx.file._vimana_push, ctx.file.component, ctx.file.metadata],
    )
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

vimana_push = rule(
    executable = True,
    implementation = _vimana_push_impl,
    doc =
        "Push a Vimana container," +
        " consisting of a component module and matching metadata," +
        " to the given OCI container registry.",
    attrs = {
        "component": attr.label(
            doc = "Compiled component module.",
            allow_single_file = [".wasm"],
        ),
        "metadata": attr.label(
            doc = "Serialized metadata.",
            allow_single_file = [".binpb"],
        ),
        "domain_id": attr.string(
            doc = "Domain ID, e.g. `1234567890abcdef1234567890abcdef`.",
        ),
        "service": attr.string(
            doc = "Service name, e.g. `some.package.FooService`.",
        ),
        "version": attr.string(
            doc = "Component version, e.g. `1.0.0-release`.",
        ),
        "registry": attr.string(
            doc = "Image registry root, e.g. `http://localhost:5000`.",
        ),
        "_vimana_push": attr.label(
            default = "//:vimana-push.sh",
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
    },
)
