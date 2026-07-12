# zdawn

Cross-platform WebGPU lib for Zig built on top of [Dawn](https://github.com/zig-gamedev/dawn) native WebGPU implementation.

Extracted from [zgpu](https://github.com/zig-gamedev/zgpu) and updated to Dawn v20260624.223603

## Getting started

`zig fetch --save git+...`

Example `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{ ... });

    // Adds platform-specific library search paths and links the
    // prebuilt dawn library to the executable.
    @import("zdawn").addLibraryPathsTo(exe);

    const zdawn = b.dependency("zdawn", .{});
    exe.root_module.addImport("zdawn", zdawn.module("webgpu"));

    // Link the zdawn C/C++ wrapper artifact.
    if (target.result.os.tag != .emscripten) {
      exe.linkLibrary(zdawn.artifact("zdawn"));
    }
}
```

## Supported Platforms

- [x] MacOS
- [ ] Windows
- [ ] Linux (untested)
