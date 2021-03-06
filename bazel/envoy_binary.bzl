load("@rules_cc//cc:defs.bzl", "cc_binary")

# DO NOT LOAD THIS FILE. Load envoy_build_system.bzl instead.
# Envoy binary targets
load(
    ":envoy_internal.bzl",
    "envoy_copts",
    "envoy_external_dep_path",
    "envoy_stdlib_deps",
    "tcmalloc_external_dep",
)

# Envoy C++ binary targets should be specified with this function.
def envoy_cc_binary(
        name,
        srcs = [],
        data = [],
        testonly = 0,
        visibility = None,
        external_deps = [],
        repository = "",
        stamped = False,
        deps = [],
        linkopts = [],
        tags = []):
    if not linkopts:
        linkopts = _envoy_linkopts()
    if stamped:
        linkopts = linkopts + _envoy_stamped_linkopts()
        deps = deps + _envoy_stamped_deps()
    deps = deps + [envoy_external_dep_path(dep) for dep in external_deps] + envoy_stdlib_deps()
    cc_binary(
        name = name,
        srcs = srcs,
        data = data,
        copts = envoy_copts(repository),
        linkopts = linkopts,
        testonly = testonly,
        linkstatic = 1,
        visibility = visibility,
        malloc = tcmalloc_external_dep(repository),
        # FIXME: Solaris ld doesn't support build-ld. Fix more elegantly.
        stamp = 0,
        deps = deps,
        tags = tags,
    )

# Select the given values if exporting is enabled in the current build.
def _envoy_select_exported_symbols(xs):
    return select({
        "@envoy//bazel:enable_exported_symbols": xs,
        "//conditions:default": [],
    })

# Compute the final linkopts based on various options.
def _envoy_linkopts():
    return select({
        # The macOS system library transitively links common libraries (e.g., pthread).
        "@envoy//bazel:apple": [
            # See note here: https://luajit.org/install.html
            "-pagezero_size 10000",
            "-image_base 100000000",
        ],
        "@envoy//bazel:windows_x86_64": [
            "-DEFAULTLIB:advapi32.lib",
            "-DEFAULTLIB:ws2_32.lib",
            "-DEFAULTLIB:iphlpapi.lib",
            "-WX",
        ],
        "//conditions:default": [
            "-pthread",
            "-lrt",
            "-ldl",
	    # The 'relro'flag is not supported by the Illumos linker.
            "-Wl,-z,now",
            # FIXME: GNU LD supports this option but the Illumos linker doesn't.
            #'-Wl,--hash-style=gnu',
        ],
    }) + select({
        "@envoy//bazel:boringssl_fips": [],
        "@envoy//bazel:windows_x86_64": [],
        # FIXME: GCC on Illumos doesn't support position independent executables?
        # "//conditions:default": ["-pie"],
        "//conditions:default": [],
    }) + _envoy_select_exported_symbols(["-Wl,-E"])

def _envoy_stamped_deps():
    return select({
        "@envoy//bazel:windows_x86_64": [],
        "@envoy//bazel:apple": [
            "@envoy//bazel:raw_build_id.ldscript",
        ],
        "//conditions:default": [
            "@envoy//bazel:gnu_build_id.ldscript",
        ],
    })

def _envoy_stamped_linkopts():
    return select({
        # Coverage builds in CI are failing to link when setting a build ID.
        #
        # /usr/bin/ld.gold: internal error in write_build_id, at ../../gold/layout.cc:5419
        "@envoy//bazel:coverage_build": [],
        "@envoy//bazel:windows_x86_64": [],

        # macOS doesn't have an official equivalent to the `.note.gnu.build-id`
        # ELF section, so just stuff the raw ID into a new text section.
        "@envoy//bazel:apple": [
            "-sectcreate __TEXT __build_id",
            "$(location @envoy//bazel:raw_build_id.ldscript)",
        ],

        # Note: assumes GNU GCC (or compatible) handling of `--build-id` flag.
        "//conditions:default": [
            # TODO: Ilumos ld doesn't support build-ld. Fix more elegantly.
            # "-Wl,@$(location @envoy//bazel:gnu_build_id.ldscript)",
        ],
    })
