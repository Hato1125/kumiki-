# KUMIKI

> [!WARNING]
> KUMIKI is still in early development. The API may change without notice.

KUMIKI is a small retained-mode UI library for ZIG.  
You write the UI declaratively, and everything that can be decided is decided at compile time.  
It keeps what you need to learn small, aiming for a spec that fits in your head.

## REQUIREMENTS

- ZIG 0.17.0 or later

### OS

- Linux (Wayland)
- Windows (not fully supported)
- macOS (not fully supported)

## INSTALL

```sh
zig fetch --save git+https://github.com/Hato1125/kumiki.git
```

Import the module in `build.zig`.

```zig
const kumiki = b.dependency("kumiki", .{
    .target = target,
    .optimize = optimize,
}).module("kumiki");

exe.root_module.addImport("kumiki", kumiki);
```

## EXAMPLE

```zig
const std = @import("std");
const ui = @import("kumiki");

const Hello = struct {
    pub const view = ui.stack(.{
        ui.rect()
            .fill(.white),
        ui.text("Hello world")
            .size(24),
    });
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    try ui.run(gpa.allocator(), .{
        .title = "Hello",
        .font = "assets/font.ttf",
    }, Hello{});
}
```

<sub>Licensed under the [MPL-2.0](LICENSE).</sub>
