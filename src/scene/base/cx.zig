//! A function receives this by declaring a parameter of this type. It
//! describes the nearest component around the place the function is given.

const std = @import("std");
const types = @import("types");

const node_zig = @import("node.zig");
const contains = node_zig.contains;
const keyOf = @import("task.zig").keyOf;

const Context = @This();

id: node_zig.NodeId,
state: *const node_zig.State,
arena: *std.heap.ArenaAllocator.State,
/// The allocator given to the Scene.
gpa: std.mem.Allocator,
/// The size of this component at the last layout: zero before the first.
size: types.Extent,

/// The focus, the pointer and the pressed tap count when they are on this
/// component or inside it. Nothing has the focus while the keyboard is with
/// another window.
pub fn focused(self: Context) bool {
    return self.state.active and contains(self.state.focus, self.id);
}

/// A component shows its focus only after the keyboard was used, so that a
/// click leaves no mark.
pub fn focusVisible(self: Context) bool {
    return self.state.keyboard and self.focused();
}

/// Moves the focus to the first view in this component that can take it,
/// once the tree is built with what the function that runs changed, so that a
/// view it brings up can take it. Nothing happens when the component shows
/// none.
pub fn focus(self: Context) void {
    self.state.wanted.* = self.id;
}

/// Closes the scene: the frame in which the function runs is the last one,
/// and `ui.run` returns after it. The `closing` of the root is not asked.
pub fn close(self: Context) void {
    self.state.closed.* = true;
}

/// Makes the scene wait for the display to show each frame, from the next
/// frame on. It does from the start.
pub fn vsync(self: Context, on: bool) void {
    self.state.vsync.* = on;
}

/// Makes the scene draw at most `max` frames in a second, which is
/// positive, from the next frame on. Null, as at the start, sets no limit.
pub fn limit(self: Context, max: ?f64) void {
    std.debug.assert(max orelse 1 > 0);
    self.state.limit.* = max;
}

pub fn hovered(self: Context) bool {
    return contains(self.state.hover, self.id);
}

pub fn pressed(self: Context) bool {
    return contains(self.state.press, self.id);
}

/// Runs `work(args...)` on a thread of its own, where it must not touch the
/// components, and hands what it returns to `done` on the thread of the
/// scene. `done` is one of the functions that this component, or one around
/// it, lists in `pub const later = .{ ... }`: its parameters are filled in by
/// type, and the one that nothing fills in takes the result. The result is
/// dropped when this component is gone by then.
pub fn spawn(
    self: Context,
    comptime work: anytype,
    args: std.meta.ArgsTuple(@TypeOf(work)),
    comptime done: anytype,
) void {
    comptime {
        const Result = node_zig.ReturnOf(work);
        const params = @typeInfo(@TypeOf(done)).@"fn".param_types;
        const takes = for (params) |param_type| {
            if (param_type == Result) break true;
        } else false;

        if (Result != void and !takes) {
            @compileError(
                "the function given to spawn takes no " ++ @typeName(Result),
            );
        }
    }

    self.state.tasks.spawn(self.id, work, args, keyOf(done));
}

/// Calls `func` once `seconds` have passed. `func` is one of the functions
/// that this component, or one around it, lists in
/// `pub const later = .{ ... }`, and its parameters are filled in by type. A
/// call of `func` that this component still waits for gives way, so asking
/// again puts the moment off. `func` runs on a frame of its own, never within
/// the function that asks for it, and not at all when this component is gone
/// by then.
pub fn after(self: Context, seconds: f64, comptime func: anytype) void {
    const due = self.state.now + @max(0, seconds);
    self.state.tasks.after(self.id, due, keyOf(func));
}

/// The text in the clipboard, or null when it holds none. Like the strings of
/// `print`, it stays valid until this component is built again.
pub fn paste(self: Context) ?[]const u8 {
    var arena = self.arena.promote(self.gpa);
    defer self.arena.* = arena.state;

    return self.state.host.paste(self.state.host.impl, arena.allocator());
}

/// Returns whether the clipboard took the text.
pub fn copy(self: Context, text: []const u8) bool {
    return self.state.host.copy(self.state.host.impl, text);
}

/// The time in seconds of the event being handled, or else of this build. It
/// only serves to compare with other times of this clock.
pub fn now(self: Context) f64 {
    return self.state.now;
}

/// The string stays valid until this component is built again. It is empty
/// when memory runs out.
pub fn print(
    self: Context,
    comptime fmt: []const u8,
    args: anytype,
) []const u8 {
    var arena = self.arena.promote(self.gpa);
    defer self.arena.* = arena.state;

    return std.fmt.allocPrint(arena.allocator(), fmt, args) catch "";
}
