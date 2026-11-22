const std = @import("std");
const types = @import("types");
const Extent = types.Extent;
const Point = types.Point;
const text_zig = @import("text");

const call = @import("base/call.zig");
const invoke = call.invoke;
const node_zig = @import("base/node.zig");
const NodeId = node_zig.NodeId;
const Tasks = @import("base/task.zig").Tasks;
const input = @import("pass/input.zig");
const keys = input.keys;
const pass = @import("pass/layout.zig");
const painter = @import("pass/paint.zig");
const paint = painter.paint;
const popup = @import("pass/popup.zig");
const tree = @import("pass/tree.zig");

/// A tree of views with its focus and pointer. `Impl` hands over the events
/// and receives the drawing: `next(wait)` returns the next event or null, and
/// waits up to `wait` seconds for one to arrive, not at all for 0 and without
/// end for infinity; `size()` and `now()`, in seconds, are read on every
/// frame; `begin()` returns the canvas to draw to, or null to skip the
/// drawing, and `end()` shows it; `wake()` makes a waiting `next`, or else
/// the next one that waits, return, and is called from other threads;
/// `input(area)` starts the typing of text at `area`, or stops it when the
/// area is null, which also ends what an input method is composing;
/// `copy(text)` puts text into the clipboard and returns whether it took it,
/// and `paste(allocator)` returns a copy of what it holds, or null.
///
/// An implementation may declare `scale()`, how many pixels make up one unit
/// of the sizes. It is read on every frame too: a text is as wide as the
/// scale it is drawn at makes it, so the scene tells the scale before it
/// measures, and lays everything out again when the scale changes. It may
/// also declare `vsync(on)`, which the scene calls when a function asks for
/// another.
///
/// The root may declare `pub fn closing`, which returns whether the scene
/// closes when the implementation reports a close, and without which it
/// does. Its parameters are filled in by type, as described at `invoke` in
/// base/call.zig, and the components it receives as mutable pointers are
/// built again, so that it can bring up a view that asks first.
pub fn Scene(comptime Impl: type, comptime Root: type) type {
    if (!node_zig.isComponent(Root))
        @compileError("the root must be a component with a view");

    inline for (.{
        "Options",
        "init",
        "deinit",
        "next",
        "size",
        "now",
        "begin",
        "end",
        "wake",
        "input",
        "copy",
        "paste",
    }) |name| {
        if (!@hasDecl(Impl, name)) {
            @compileError(
                @typeName(Impl) ++ " is no implementation: it lacks " ++ name,
            );
        }
    }

    return struct {
        impl: Impl,
        state: node_zig.State,
        root: node_zig.Node(Root),
        size: Extent = .{},
        scale: f32 = 1,
        pointer: ?Point = null,
        pending: bool = true,

        /// Where the focus, the pointer and the pressed tap are. The state
        /// shows them to the functions.
        focus: Path = .{},
        hover: Path = .{},
        press: Path = .{},

        /// The node that holds the pointer and the button it holds it with,
        /// and where the pointer was seen last, which is kept while it is
        /// outside the window.
        held: ?NodeId = null,
        held_by: input.MouseButton = .left,
        last: Point = .{},

        /// What the views that watch the pointer were told last: the path
        /// it was over, and where it was.
        told: Path = .{},
        told_at: Point = .{},

        /// The node that takes the typed text.
        typing: ?NodeId = null,

        /// The component that asked for the focus since the last build.
        wanted: ?NodeId = null,

        /// Whether a function asked to close the scene.
        closed: bool = false,

        /// When the last drawing asked for the next one.
        again: f64 = std.math.inf(f64),

        /// How the scene draws, which a function may change through its
        /// Context: `limit` is the most frames in a second.
        vsync: bool = true,
        limit: ?f64 = null,

        /// The vsync the implementation was told last.
        synced: ?bool = null,

        /// When the last drawing was made, and whether one waits for the
        /// next that `limit` allows.
        drawn: f64 = -std.math.inf(f64),
        owed: bool = false,

        /// Whether something was built or laid out since the last drawing.
        changed: bool = true,

        const Self = @This();
        const Path = node_zig.Path(node_zig.depthOf(node_zig.Node(Root)));

        // A view whose constraint follows what it builds may never settle.
        const max_rounds = 4;

        /// The scene keeps the only copy of `root` that stays up to date, so
        /// what the root allocates is freed by its `unmount`, not by the
        /// caller.
        pub fn init(
            gpa: std.mem.Allocator,
            options: Impl.Options,
            root: Root,
        ) !Self {
            const tasks = try gpa.create(Tasks);
            errdefer gpa.destroy(tasks);

            tasks.* = .{
                .gpa = gpa,
                .wake = wake,
            };

            var self: Self = .{
                .impl = try Impl.init(gpa, options),
                .state = .{
                    .gpa = gpa,
                    .tasks = tasks,
                    .wanted = undefined,
                    .closed = undefined,
                    .vsync = undefined,
                    .limit = undefined,
                    .host = .{
                        .impl = undefined,
                        .paste = paste,
                        .copy = copy,
                    },
                },
                .root = undefined,
            };
            self.settle();
            self.state.now = self.impl.now();
            tree.mount(&self.root, root, &self.state, .{});

            return self;
        }

        /// Waits for the functions that still run in the background. The
        /// tree goes first, because an `unmount` may spawn one more.
        pub fn deinit(self: *Self) void {
            self.settle();
            tree.destroy(&self.root, &self.state, .{});

            self.state.tasks.deinit();
            self.impl.deinit();
            self.state.gpa.destroy(self.state.tasks);
        }

        // The scene may have been moved since it was last used, and its paths
        // change, so what the state points at inside the scene is set anew.
        fn settle(self: *Self) void {
            self.state.host.impl = &self.impl;
            self.state.wanted = &self.wanted;
            self.state.closed = &self.closed;
            self.state.vsync = &self.vsync;
            self.state.limit = &self.limit;
            self.state.focus = self.focus.slice();
            self.state.hover = self.hover.slice();
            self.state.press = self.press.slice();
        }

        fn wake(impl: *anyopaque) void {
            Impl.wake(@ptrCast(@alignCast(impl)));
        }

        fn paste(impl: *anyopaque, into: std.mem.Allocator) ?[]const u8 {
            return Impl.paste(@ptrCast(@alignCast(impl)), into);
        }

        fn copy(impl: *anyopaque, text: []const u8) bool {
            return Impl.copy(@ptrCast(@alignCast(impl)), text);
        }

        pub fn run(self: *Self) !void {
            while (try self.frame()) {}
        }

        /// Whether the next frame is needed without waiting for input.
        pub fn busy(self: *const Self) bool {
            return self.pending or
                self.state.animating or
                self.owed or
                self.strays();
        }

        fn strays(self: *const Self) bool {
            const held = self.held orelse return false;

            return !node_zig.contains(self.hover.slice(), held);
        }

        /// Returns false once the implementation reports a close that the
        /// root lets through, or a function closed the scene through its
        /// Context. The scene must stay where it is from its first frame on,
        /// because a function in the background wakes the implementation
        /// where the last frame found it.
        pub fn frame(self: *Self) !bool {
            self.settle();
            self.state.tasks.waker.store(&self.impl, .release);

            const due = @min(self.again, self.state.tasks.due(), self.ready());
            const idle = !self.pending and !self.strays();
            var wait = if (idle) @max(0, due - self.impl.now()) else 0;

            // The frame after an animation ended shows where it ended.
            const moving = self.state.animating;

            var seen = false;
            var redraw = false;
            while (self.impl.next(wait)) |event| : (wait = 0) {
                seen = true;
                self.state.now = self.impl.now();

                switch (event) {
                    .pointer_move => |at| {
                        self.hoverAt(at);
                        self.hold(.move);
                    },
                    .pointer_leave => self.hoverAt(null),
                    .button => |button| self.pressButton(button),
                    .wheel => |wheel| {
                        self.offerAt(wheel.at, .{ .wheel = wheel });
                    },
                    .drop => |drop| {
                        const at: Point = .{
                            .x = drop.x,
                            .y = drop.y,
                        };
                        self.offerAt(at, .{ .drop = drop });
                    },
                    .key => |press| self.pressKey(press),
                    .text => |text| {
                        _ = self.offer(self.focus.id(), .{ .text = text });
                    },
                    .active => |active| self.activate(active),
                    .redraw => redraw = true,
                    .close => if (self.mayClose()) return false,
                }
            }

            self.state.now = self.impl.now();
            if (self.strays()) self.hold(.move);

            self.receive();
            self.update();
            if (self.closed) return false;

            // Events that change nothing leave the last drawing as it is. A
            // wake without an event draws, and so does the time a drawing
            // asked for.
            const still = seen and
                !redraw and
                !self.changed and
                !moving and
                !self.state.animating and
                !self.owed;
            if (still and self.state.now < self.again) return true;

            if (self.state.now < self.slot()) {
                self.owed = true;
                return true;
            }

            try self.draw();

            return true;
        }

        fn draw(self: *Self) !void {
            self.again = std.math.inf(f64);
            self.owed = false;
            self.drawn = self.state.now;

            if (comptime @hasDecl(Impl, "vsync")) {
                if (self.synced != self.vsync) {
                    self.impl.vsync(self.vsync);
                    self.synced = self.vsync;
                }
            }

            const canvas = try self.impl.begin() orelse return;
            self.changed = false;

            var target: painter.Target = .{
                .canvas = canvas,
                .now = self.state.now,
                .again = self.again,
            };
            paint(&self.root, &target);
            popup.paint(&self.root, &target);
            self.again = target.again;

            try self.impl.end();
        }

        fn slot(self: *const Self) f64 {
            const max = self.limit orelse return -std.math.inf(f64);

            return self.drawn + 1 / max;
        }

        // When the scene has to wake for a drawing that changes on its own,
        // or one that waits for its slot. Input is taken at once, and only
        // its drawing waits.
        fn ready(self: *const Self) f64 {
            if (self.state.animating or self.owed) return self.slot();

            return std.math.inf(f64);
        }

        fn receive(self: *Self) void {
            while (self.state.tasks.take(self.state.now)) |task| {
                var handled = false;
                const found = input.deliver(
                    &self.root,
                    task.tag,
                    task,
                    .{},
                    &self.state,
                    &handled,
                );
                if (found and !handled) {
                    @panic(
                        "no component lists the function given to spawn " ++
                            "or after in its `later`",
                    );
                }

                if (handled) self.pending = true;

                task.destroy(task, self.state.gpa);
            }
        }

        fn update(self: *Self) void {
            const size = self.impl.size();
            const scale: f32 = if (comptime @hasDecl(Impl, "scale"))
                self.impl.scale()
            else
                self.scale;

            // Before anything is built: an animation measures its view on
            // its own.
            if (comptime @hasDecl(Impl, "scale")) text_zig.setScale(scale);

            self.pending = false;

            for (0..max_rounds) |_|
                if (!self.round(size, scale)) break;

            if (self.state.inputs != 0 or self.typing != null) self.retype();
        }

        fn round(self: *Self, size: Extent, scale: f32) bool {
            const state = &self.state;
            state.animating = false;
            state.built = false;
            state.stale = false;

            tree.rebuild(&self.root, state, .{});
            popup.advance(&self.root, state);

            if (state.stale) self.refreshPaths();

            if (self.wanted) |wanted| {
                var walk: input.FocusWalk = .{ .current = null };
                _ = input.walkFocusIn(&self.root, wanted, &walk);
                self.wanted = null;

                if (walk.first) |first|
                    self.move(&self.focus, self.pathTo(first));
            }

            const measured = state.built or
                !std.meta.eql(size, self.size) or
                scale != self.scale;
            if (measured) {
                self.changed = true;
                self.size = size;
                self.scale = scale;

                _ = pass.measure(&self.root, .tight(size));
                pass.layout(&self.root, .{});
                popup.place(&self.root, size);

                // A new layout may have moved something under a still
                // pointer.
                if (self.pointer) |at| self.hoverAt(at);
            }

            // A running animation measured its view while it was built.
            if (!measured and !state.animating) return false;

            var marked = false;
            tree.markResized(&self.root, &marked);

            return marked;
        }

        fn refreshPaths(self: *Self) void {
            var focus = self.pathTo(self.focus.id());

            if (focus.id() == null) {
                var anchor: ?NodeId = null;
                _ = popup.anchorOf(&self.root, self.focus.slice(), &anchor);
                focus = self.pathTo(anchor);
            }
            self.move(&self.focus, focus);

            inline for (.{
                &self.hover,
                &self.press,
            }) |path|
                self.move(path, self.pathTo(path.id()));

            if (self.pathTo(self.held).id() == null) self.held = null;
        }

        fn retype(self: *Self) void {
            var found: input.Typing = .{};
            if (self.state.active) {
                if (self.focus.id()) |focus|
                    _ = input.typingArea(&self.root, focus, &found);
            }

            // The input that the typing leaves is offered an empty
            // composition, and the implementation is stopped, so that a
            // composition under way ends on both sides.
            if (self.typing) |typing| {
                if (found.target != typing) {
                    _ = self.offer(typing, .{
                        .text = .{
                            .text = "",
                            .composing = true,
                        },
                    });
                    if (self.state.typing != null) self.impl.input(null);
                    self.state.typing = null;
                }
            }
            self.typing = found.target;

            if (std.meta.eql(found.area, self.state.typing)) return;

            self.state.typing = found.area;
            self.impl.input(found.area);
        }

        fn pathTo(self: *Self, id: ?NodeId) Path {
            var path: Path = .{};
            if (id) |target| _ = input.findPath(&self.root, target, &path);

            return path;
        }

        fn move(self: *Self, path: *Path, next: Path) void {
            if (next.id() == path.id()) return;

            tree.markChanged(&self.root, path.slice(), next.slice());
            path.* = next;
            self.settle();
            self.pending = true;
        }

        // The components around the focus show it differently, so they are
        // built again when the kind of input changes.
        fn setKeyboard(self: *Self, keyboard: bool) void {
            if (keyboard == self.state.keyboard) return;

            self.state.keyboard = keyboard;
            tree.markChanged(&self.root, self.focus.slice(), &.{});
            self.pending = true;
        }

        fn hoverAt(self: *Self, at: ?Point) void {
            self.pointer = at;

            var path: Path = .{};
            if (at) |point| {
                self.last = point;

                var open = false;
                const in_popup = popup.hit(&self.root, point, &path, &open);
                if (!in_popup and !open)
                    _ = input.hit(&self.root, point, &path);
            }

            self.move(&self.hover, path);
            self.watch();
        }

        fn watch(self: *Self) void {
            if (comptime !input.watches(@TypeOf(self.root))) return;

            const hover = &self.hover;
            const moved = !std.meta.eql(self.last, self.told_at);
            if (!moved and hover.id() == self.told.id()) return;

            var told = false;
            input.watch(&self.root, .{
                .was = self.told.slice(),
                .is = hover.slice(),
                .moved = moved,
                .at = self.last,
            }, .{}, &self.state, &told);

            self.told = hover.*;
            self.told_at = self.last;
            if (told) self.pending = true;
        }

        fn mayClose(self: *Self) bool {
            if (comptime !@hasDecl(Root, "closing")) return true;
            if (comptime node_zig.ReturnOf(Root.closing) != bool) {
                @compileError(
                    "the closing of " ++ @typeName(Root) ++
                        " must return a bool",
                );
            }

            const owners = .{&self.root};
            if (invoke(Root.closing, owners, &self.state, {})) return true;

            call.markTargets(Root.closing, owners);
            self.pending = true;

            return false;
        }

        fn dismiss(self: *Self) bool {
            var told = false;
            popup.dismiss(&self.root, .{}, &self.state, &told);
            if (told) self.pending = true;

            return told;
        }

        fn hold(self: *Self, phase: @FieldType(input.Pointer, "phase")) void {
            const held = self.held orelse return;

            _ = self.offer(held, .{ .pointer = .{
                .phase = phase,
                .button = self.held_by,
                .x = self.last.x,
                .y = self.last.y,
            } });
        }

        fn activate(self: *Self, active: bool) void {
            if (active == self.state.active) return;

            // Without the keyboard nothing has the focus, so what shows the
            // focus is built again.
            self.state.active = active;
            tree.markChanged(&self.root, self.focus.slice(), &.{});
            self.pending = true;
            if (active) return;

            // A pointer that is held is let go, because its release may
            // never arrive.
            self.hold(.cancel);
            self.held = null;
            self.move(&self.press, .{});
        }

        fn pressButton(self: *Self, button: input.MouseButtonEvent) void {
            self.hoverAt(.{
                .x = button.x,
                .y = button.y,
            });

            if (button.down) self.buttonDown(button) else self.buttonUp(button);
        }

        fn buttonDown(self: *Self, button: input.MouseButtonEvent) void {
            if (self.held != null) return;

            const left = button.button == .left;

            // A press outside the open popups dismisses them. The left
            // button does nothing else then, so that the view of a popup
            // does not open it again.
            if (self.hover.id() == null and self.dismiss()) {
                if (left) return;

                // Another button goes on to what lies there once the popups
                // are gone, so that a menu can open again where it is asked
                // for.
                self.update();
                self.hoverAt(.{
                    .x = button.x,
                    .y = button.y,
                });
            }

            var found: input.Nearest = .{};
            if (left) {
                self.setKeyboard(false);
                if (self.hover.id()) |over|
                    _ = input.nearest(&self.root, over, &found);
                if (found.focusable) |focusable|
                    self.move(&self.focus, self.hover.from(focusable));
            }

            self.held = self.offer(self.hover.id(), .{ .pointer = .{
                .phase = .down,
                .button = button.button,
                .x = button.x,
                .y = button.y,
                .clicks = button.clicks,
                .mod = button.mod,
            } });
            self.held_by = button.button;

            if (self.held != null) {
                self.move(&self.press, .{});
            } else if (left) {
                const pressed: Path = if (found.tap) |tap|
                    self.hover.from(tap)
                else
                    .{};
                self.move(&self.press, pressed);
            }
        }

        fn buttonUp(self: *Self, button: input.MouseButtonEvent) void {
            if (self.held != null) {
                if (button.button != self.held_by) return;

                self.hold(.up);
                self.held = null;
                return;
            }
            if (button.button != .left) return;

            const target = self.press.id() orelse return;
            self.move(&self.press, .{});
            if (node_zig.contains(self.hover.slice(), target))
                _ = self.offer(target, .click);
        }

        fn pressKey(self: *Self, press: input.KeyPress) void {
            if (press.down and !press.isModifier()) self.setKeyboard(true);

            if (self.offer(self.focus.id(), .{ .key = press }) != null) return;
            if (!press.down) return;
            if (self.shortcut(press)) return;

            if (press.key == keys.escape) {
                if (!self.dismiss()) self.move(&self.focus, .{});
                return;
            }

            const tab = press.key == keys.tab;
            const arrow = press.key == keys.up or press.key == keys.down;
            if (!tab and !arrow) return;

            var walk: input.FocusWalk = .{ .current = self.focus.id() };
            const in_popup = popup.walkFocus(&self.root, &walk);
            if (!in_popup and !tab) return;
            if (!in_popup) input.walkFocus(&self.root, &walk);

            const backward = if (tab) press.shift() else press.key == keys.up;
            self.move(&self.focus, self.pathTo(walk.result(backward)));
        }

        fn shortcut(self: *Self, press: input.KeyPress) bool {
            if (comptime !input.binds(@TypeOf(self.root))) return false;

            var by: ?NodeId = null;
            if (!popup.shortcut(&self.root, press, .{}, &self.state, &by))
                input.shortcut(&self.root, press, .{}, &self.state, &by);
            if (by != null) self.pending = true;

            return by != null;
        }

        fn offerAt(self: *Self, at: Point, what: input.Offer) void {
            self.hoverAt(at);
            _ = self.offer(self.hover.id(), what);
        }

        fn offer(self: *Self, target: ?NodeId, what: input.Offer) ?NodeId {
            const to = target orelse return null;

            var by: ?NodeId = null;
            _ = input.bubble(&self.root, to, what, .{}, &self.state, &by);
            if (by != null) self.pending = true;

            return by;
        }
    };
}
