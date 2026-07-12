const std = @import("std");
const log = std.log.scoped(.zgpu);
const wgpu_export_symbols = @import("src/webgpu_export_symbols.zig");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    // const target = b.standardTargetOptions(.{});
    // const target = b.standardTargetOptions(.{});
    // const target: std.Build.ResolvedTarget = .{
    //     .cpu_arch = .x86_64,
    //     .os_tag = .windows,
    //     .abi = .msvc,
    // };
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .msvc,
    });

    // Standalone `webgpu` module: just the hand-written webgpu.h bindings
    // (src/webgpu.zig) + the dawn include path.
    const webgpu_mod = b.addModule("webgpu", .{
        .root_source_file = b.path("src/webgpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDawnPaths(b, webgpu_mod, target.result);

    const zdawn = b.addLibrary(.{
        .name = "zdawn",
        .linkage = .dynamic,
        .use_llvm = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zdawn.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,

        }),
    });
    b.installArtifact(zdawn);
    linkSystemDeps(b, zdawn);
    addDawnPaths(b, zdawn.root_module, zdawn.rootModuleTarget());

    // prebuilt libs from os-specific dependency
    zdawn.root_module.linkSystemLibrary("webgpu_dawn", .{});
    // Embed /ALTERNATENAME linker directives for CRT init stubs (see comment in crt_stubs.c).
    if (zdawn.rootModuleTarget().os.tag == .windows and zdawn.rootModuleTarget().abi == .msvc) {
        zdawn.root_module.addCSourceFile(.{
            .file = b.path("src/crt_stubs.c"),
        });
    }

    // When building zdawn as a shared library on macOS, the linker would
    // otherwise only pull the subset of libwebgpu_dawn.a referenced directly
    // by zdawn.zig. Force all exported wgpu* entry points out of the static
    // archive so libzdawn.dylib can serve as the single shared Dawn runtime
    // for any downstream libs dynamically linked
    forceExportAllDawnWebgpuSymbols(b, zdawn, zdawn.rootModuleTarget());

    // zdawn.root_module.addIncludePath(b.path("src"));
}

// /// Call this for your exe to copy dxcompiler.dll and dxil.dll to your exe's directory from zwindows
// pub fn installDxcFrom(exe: *std.Build.Step.Compile, zwindows_dep_name: []const u8) void {
//     const b = exe.step.owner;
//     exe.step.dependOn(
//         &b.addInstallFileWithDir(
//             .{ .dependency = .{
//                 .dependency = b.dependency(zwindows_dep_name, .{}),
//                 .sub_path = "bin/x64/dxcompiler.dll",
//             } },
//             .bin,
//             "dxcompiler.dll",
//         ).step,
//     );
//     exe.step.dependOn(
//         &b.addInstallFileWithDir(
//             .{ .dependency = .{
//                 .dependency = b.dependency(zwindows_dep_name, .{}),
//                 .sub_path = "bin/x64/dxil.dll",
//             } },
//             .bin,
//             "dxil.dll",
//         ).step,
//     );
// }

pub fn linkSystemDeps(b: *std.Build, compile_step: *std.Build.Step.Compile) void {
    const m = compile_step.root_module;
    switch (compile_step.rootModuleTarget().os.tag) {
        .windows => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                m.addLibraryPath(system_sdk.path("windows/lib/x86_64-windows-gnu"));
            }
            // The standalone Windows SDK places dbghelp.lib under
            // Debuggers\lib\x64\ rather than the standard um\x64\.
            if (compile_step.rootModuleTarget().abi == .msvc) {
                const debuggers_lib_dir: std.Build.LazyPath = .{
                    .cwd_relative = "C:\\Program Files (x86)\\Windows Kits\\10\\Debuggers\\lib\\x64",
                };
                m.addLibraryPath(debuggers_lib_dir);
            }
            m.linkSystemLibrary("ole32", .{});
            m.linkSystemLibrary("oleaut32", .{});
            m.linkSystemLibrary("dxguid", .{});
            m.linkSystemLibrary("dbghelp", .{});
            // CompareObjectHandles (used by Dawn's D3D11/D3D12 backends)
            // is in OneCore.lib, not kernel32.lib.
            if (compile_step.rootModuleTarget().abi == .msvc) {
                m.linkSystemLibrary("OneCore", .{});
            }
        },
        .macos => {
            // NOTE: we intentionally do NOT use system_sdk's macos12 stub
            // frameworks here. The Google dawn prebuilt was built against a
            // recent macOS SDK and references Metal classes introduced in
            // macOS 15.2+ (e.g. MTLLogStateDescriptor), which are absent from
            // the macOS 12 stub Metal.framework. For native builds the host
            // SDK's frameworks are correct and newer, so link directly.
            // CoreFoundation is required by dawn's IOSurfaceUtils/PhysicalDeviceMTL.
            m.linkSystemLibrary("objc", .{});
            m.linkFramework("Metal", .{});
            m.linkFramework("CoreGraphics", .{});
            m.linkFramework("CoreFoundation", .{});
            m.linkFramework("Foundation", .{});
            m.linkFramework("IOKit", .{});
            m.linkFramework("IOSurface", .{});
            m.linkFramework("QuartzCore", .{});
        },
        else => {},
    }
}

/// Force all exported wgpu* entry points out of the static archive so
/// libzdawn can serve as the single shared Dawn runtime for downstream
/// shared libs. On macOS, -u pulls symbols from the archive. On Windows
/// (msvc), lld-link does NOT auto-export, so we use /INCLUDE: (via
/// forceUndefinedSymbol) + a .def file to export them from the DLL.
fn forceExportAllDawnWebgpuSymbols(b: *std.Build, compile: *std.Build.Step.Compile, target: std.Target) void {
    switch (target.os.tag) {
        .macos => {
            for (wgpu_export_symbols.all) |sym| {
                compile.forceUndefinedSymbol(b.fmt("_{s}", .{sym}));
            }
        },
        .windows => {
            if (target.abi != .msvc) return;
            var def_contents: std.ArrayList(u8) = .empty;
            defer def_contents.deinit(b.allocator);
            def_contents.appendSlice(b.allocator, "LIBRARY zdawn\nEXPORTS\n") catch @panic("OOM");
            for (wgpu_export_symbols.all) |sym| {
                compile.forceUndefinedSymbol(sym);
                def_contents.appendSlice(b.allocator, sym) catch @panic("OOM");
                def_contents.append(b.allocator, '\n') catch @panic("OOM");
            }
            const def_file = b.addWriteFiles();
            const def_path = def_file.add("zdawn.def", def_contents.items);
            compile.root_module.addObjectFile(def_path);
        },
        else => {},
    }
}

/// Resolve the os/arch-specific dawn prebuilt dependency for `target` and add
/// both its library path (`lib/` or root) and its header path (`include/`)
/// to `m`. Used by the zgpu `root` module (which @cImports webgpu/webgpu.h)
/// and the `zdawn`/test artifacts.
pub fn addDawnPaths(b: *std.Build, m: *std.Build.Module, target: std.Target) void {
    switch (target.os.tag) {
        .windows => {
            if (b.lazyDependency("dawn_x86_64_windows_msvc", .{})) |dawn_prebuilt| {
                m.addLibraryPath(dawn_prebuilt.path("lib"));
                m.addIncludePath(dawn_prebuilt.path("include"));
            }
        },
        .linux => {
            if (target.cpu.arch.isX86()) {
                if (b.lazyDependency("dawn_x86_64_linux_gnu", .{})) |dawn_prebuilt| {
                    m.addLibraryPath(dawn_prebuilt.path("lib"));
                    m.addIncludePath(dawn_prebuilt.path("include"));
                }
            } else if (target.cpu.arch.isAARCH64()) {
                if (b.lazyDependency("dawn_aarch64_linux_gnu", .{})) |dawn_prebuilt| {
                    m.addLibraryPath(dawn_prebuilt.path("lib"));
                    m.addIncludePath(dawn_prebuilt.path("include"));
                }
            }
        },
        .macos => {
            // Google dawn prebuilt lays out its archive as lib/libwebgpu_dawn.a
            // and ships headers under include/webgpu/webgpu.h (+ dawn/webgpu.h).
            if (target.cpu.arch.isX86()) {
                if (b.lazyDependency("dawn_x86_64_macos", .{})) |dawn_prebuilt| {
                    m.addLibraryPath(dawn_prebuilt.path("lib"));
                    m.addIncludePath(dawn_prebuilt.path("include"));
                }
            } else if (target.cpu.arch.isAARCH64()) {
                if (b.lazyDependency("dawn_aarch64_macos", .{})) |dawn_prebuilt| {
                    m.addLibraryPath(dawn_prebuilt.path("lib"));
                    m.addIncludePath(dawn_prebuilt.path("include"));
                }
            }
        },
        else => {},
    }
}

/// Backwards-compatible wrapper: adds the dawn lib + include paths to a
/// `Compile` step's root module.
pub fn addLibraryPathsTo(compile_step: *std.Build.Step.Compile) void {
    const b = compile_step.step.owner;
    addDawnPaths(b, compile_step.root_module, compile_step.rootModuleTarget());
}

pub fn checkTargetSupported(target: std.Target) bool {
    const supported = switch (target.os.tag) {
        .windows => target.cpu.arch.isX86(), // and target.abi.isGnu(),
        .linux => (target.cpu.arch.isX86() or target.cpu.arch.isAARCH64()) and target.abi.isGnu(),
        .macos => blk: {
            if (!target.cpu.arch.isX86() and !target.cpu.arch.isAARCH64()) break :blk false;

            // If min. target macOS version is lesser than the min version we have available, then
            // our Dawn binary is incompatible with the target.
            if (target.os.version_range.semver.min.order(
                .{ .major = 12, .minor = 0, .patch = 0 },
            ) == .lt) break :blk false;
            break :blk true;
        },
        else => false,
    };
    if (supported == false) {
        log.warn("\n" ++
            \\---------------------------------------------------------------------------
            \\
            \\Dawn/WebGPU binary for this target is not available.
            \\
            \\Following targets are supported:
            \\
            \\x86_64-windows-gnu
            \\x86_64-linux-gnu
            \\x86_64-macos.12.0.0-none
            \\aarch64-linux-gnu
            \\aarch64-macos.12.0.0-none
            \\
            \\---------------------------------------------------------------------------
            \\
        , .{});
    }
    return supported;
}
