load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_configuration//:variables.bzl", "telegram_enable_icloud")

swift_library(
    name = "CloudData",
    module_name = "CloudData",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ] + (["-DENABLE_ICLOUD"] if telegram_enable_icloud else []),
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/EncryptionProvider:EncryptionProvider",
    ],
    visibility = [
        "//visibility:public",
    ],
)
