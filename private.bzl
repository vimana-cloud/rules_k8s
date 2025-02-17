# TODO: Figure out how to dedupe this list with `MODULE.bazel`.
x86_64_platforms = [
    "x86_64-linux",
    "x86_64-macos",
]
aarch64_platforms = [
    "aarch64-linux",
    "aarch64-macos",
]
execution_platforms = x86_64_platforms + aarch64_platforms

def format_platform(template):
    """ Format a template string with the current execution platform. """
    return select(
        {
            "//:exe-" + platform: template.format(platform)
            for platform in execution_platforms
        },
        no_match_error = "Only (Linux | MacOS) & (Arm64 | x86-64) currently supported",
    )

def format_platform_x86(template):
    """
    Format a template string with the current execution platform,
    only supporting the x86-64 architecture.
    """
    return select(
        {
            "//:exe-" + platform: template.format(platform)
            for platform in x86_64_platforms
        },
        no_match_error = "Only (Linux | MacOS) on x86-64 currently supported",
    )

def format_placeholder(number):
    """ Return a deterministic string based on `number` that is somewhat collision-resistant. """

    # This is pretty hacky,
    # but Starlark doesn't make it easy to pass rich information
    # from the analysis phase to the execution phase.
    # Just rely on the improbability of many tildes appearing naturally in the wild.
    return "~~~~{}~~~~".format(number)

def _write_with_sha256_substitution_impl(ctx):
    # Start by writing the raw content to a file.
    raw_file = ctx.actions.declare_file(ctx.label.name + ".raw")
    ctx.actions.write(
        output = raw_file,
        content = "\n".join(ctx.attr.content) if ctx.attr.content else "",
    )

    # Then pass it through the hashing substituter.
    ctx.actions.run(
        inputs = [raw_file],
        outputs = [ctx.outputs.out],
        executable = ctx.executable._sha256_subtitute_bin,
        arguments = [raw_file.path, ctx.outputs.out.path] + ctx.attr.substitutes,
    )
    files = depset([ctx.outputs.out])
    runfiles = ctx.runfiles(files = [ctx.outputs.out])
    return [DefaultInfo(files = files, data_runfiles = runfiles)]

write_with_sha256_substitution = rule(
    implementation = _write_with_sha256_substitution_impl,
    doc = "Like skylib's write_file, " +
          "but substitutes hashed values in for placeholder codes.",
    attrs = {
        "out": attr.output(mandatory = True),
        "content": attr.string_list(allow_empty = True),
        "substitutes": attr.string_list(allow_empty = True),
        "_sha256_subtitute_bin": attr.label(
            default = ":sha256-substitute.sh",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
    },
)
