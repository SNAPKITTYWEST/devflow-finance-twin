// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: FSL-1.1
// DEED-088: Zig build script for native WASM loader.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the WASM loader as a static C library
    const lib = b.addStaticLibrary(.{
        .name = "loader",
        .root_source_file = b.path("src/native/wasm_loader.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();

    // Install the library artifact
    b.installArtifact(lib);

    // Also create a step to copy the library to a known location for Ada linking
    const copy_step = b.addInstallArtifact(lib, .{
        .dest_dir = .{
            .override = .{ .custom = "../lib" },
        },
    });
    b.getInstallStep().dependOn(&copy_step.step);
}
