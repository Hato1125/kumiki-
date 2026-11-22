const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gfx = b.dependency("gfx", .{
        .target = target,
        .optimize = optimize,
    }).module("gfx");

    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    }).artifact("SDL3");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/host/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(sdl.getEmittedIncludeTree());

    // Each directory is a module of its own, because a module cannot import
    // a file outside its directory: the imports below are the only paths
    // between the layers.
    const types = b.createModule(.{
        .root_source_file = b.path("src/types.zig"),
        .imports = &.{.{ .name = "gfx", .module = gfx }},
    });
    const anime = b.createModule(.{
        .root_source_file = b.path("src/anime.zig"),
    });
    const text = b.createModule(.{
        .root_source_file = b.path("src/text.zig"),
        .link_libc = true,
        .imports = &.{
            .{ .name = "gfx", .module = gfx },
            .{ .name = "types", .module = types },
        },
    });
    const image = b.createModule(.{
        .root_source_file = b.path("src/image.zig"),
        .link_libc = true,
        .imports = &.{
            .{ .name = "gfx", .module = gfx },
            .{ .name = "types", .module = types },
        },
    });
    const scene = b.createModule(.{
        .root_source_file = b.path("src/scene/root.zig"),
        .imports = &.{
            .{ .name = "gfx", .module = gfx },
            .{ .name = "types", .module = types },
            .{ .name = "anime", .module = anime },
            .{ .name = "text", .module = text },
        },
    });
    const view = b.createModule(.{
        .root_source_file = b.path("src/view/root.zig"),
        .imports = &.{
            .{ .name = "gfx", .module = gfx },
            .{ .name = "types", .module = types },
            .{ .name = "text", .module = text },
            .{ .name = "image", .module = image },
            .{ .name = "scene", .module = scene },
        },
    });
    const host = b.createModule(.{
        .root_source_file = b.path("src/host/window.zig"),
        .link_libc = true,
        .imports = &.{
            .{ .name = "c", .module = translate_c.createModule() },
            .{ .name = "gfx", .module = gfx },
            .{ .name = "types", .module = types },
            .{ .name = "text", .module = text },
            .{ .name = "image", .module = image },
            .{ .name = "scene", .module = scene },
        },
    });
    host.linkLibrary(sdl);

    const kumiki = b.addModule("kumiki", .{
        .root_source_file = b.path("src/kumiki.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "gfx", .module = gfx },
            .{ .name = "types", .module = types },
            .{ .name = "anime", .module = anime },
            .{ .name = "text", .module = text },
            .{ .name = "image", .module = image },
            .{ .name = "scene", .module = scene },
            .{ .name = "view", .module = view },
            .{ .name = "host", .module = host },
        },
    });

    // Wuffs reads the image files. It is optimized whatever the rest is
    // built as: unoptimized, it takes several times as long to decode.
    kumiki.addIncludePath(b.dependency("wuffs", .{}).path("release/c"));
    kumiki.addCSourceFile(.{
        .file = b.path("src/image.c"),
        .flags = &.{ "-O2", "-fno-sanitize=undefined" },
    });

    const check = b.addTest(.{ .root_module = kumiki });
    b.default_step.dependOn(&check.step);
}
