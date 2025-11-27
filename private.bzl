# TODO: Figure out how to dedupe this list with `MODULE.bazel`.
execution_platforms = [
    "aarch64-linux",
    "aarch64-macos",
    "x86_64-linux",
    "x86_64-macos",
]

def format_platform(template):
    """ Format a template string with the current execution platform. """
    return select(
        {
            "//:exe-" + platform: template.format(platform)
            for platform in execution_platforms
        },
        no_match_error = "Only (Linux | MacOS) & (Arm64 | x86-64) currently supported",
    )

_tar_toolchain_type = "@aspect_bazel_lib//lib:tar_toolchain_type"
_jq_toolchain_type = "@aspect_bazel_lib//lib:jq_toolchain_type"

def _image_export_impl(ctx):
    tar_toolchain = ctx.toolchains[_tar_toolchain_type]
    jq_toolchain = ctx.toolchains[_jq_toolchain_type]

    ocidir = ctx.actions.declare_directory("{}.ocidir".format(ctx.label.name))
    ctx.actions.run(
        inputs = [ctx.file.ocitar],
        outputs = [ocidir],
        executable = tar_toolchain.tarinfo.binary,
        arguments = [
            "-xf",
            ctx.file.ocitar.path,
            "-C",
            ocidir.path,
        ],
    )

    output = ctx.actions.declare_directory(ctx.label.name)
    ctx.actions.run(
        inputs = [ocidir],
        outputs = [output],
        executable = ctx.executable._image_export_bin,
        arguments = [
            ocidir.path,
            output.path,
            jq_toolchain.jqinfo.bin.path,
            tar_toolchain.tarinfo.binary.path,
        ],
        tools = [
            jq_toolchain.jqinfo.bin,
            tar_toolchain.tarinfo.binary,
        ],
    )

    return [DefaultInfo(files = depset([output]))]

image_export = rule(
    implementation = _image_export_impl,
    doc = "Export the contents of a single-layer OCI TAR archive.",
    attrs = {
        "ocitar": attr.label(
            doc = "A TAR file containing an image in the OCI layout.",
            allow_single_file = True,
        ),
        "_image_export_bin": attr.label(
            default = ":image-export",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [
        _tar_toolchain_type,
        _jq_toolchain_type,
    ],
)
