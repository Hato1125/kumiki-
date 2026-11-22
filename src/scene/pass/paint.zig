const std = @import("std");

const gfx = @import("gfx");
const types = @import("types");

const node_zig = @import("../base/node.zig");
const has = node_zig.has;

/// What a frame is drawn to. `now` is the time of the frame and `again` is
/// when the next one is due at the latest; the scene sets both and reads
/// `again` after the drawing.
pub const Target = struct {
    canvas: *gfx.Canvas,
    now: f64 = 0,
    again: f64 = std.math.inf(f64),
};

pub const Painter = struct {
    canvas: *gfx.Canvas,
    bounds: types.Bounds,
    target: *Target,

    /// The bounds in the form the canvas takes them, for a clip.
    pub fn box(self: Painter) gfx.Bounds {
        return .{
            .x = self.bounds.x,
            .y = self.bounds.y,
            .width = self.bounds.w,
            .height = self.bounds.h,
        };
    }

    fn rect(self: Painter, corners: gfx.Corners) gfx.Rect {
        return .{
            .x = self.bounds.x,
            .y = self.bounds.y,
            .width = self.bounds.w,
            .height = self.bounds.h,
            .corners = corners,
        };
    }

    pub fn fill(
        self: Painter,
        corners: gfx.Corners,
        color: gfx.Color,
    ) void {
        if (color.a == 0) return;

        var shape = self.rect(corners);
        shape.color = color;
        self.canvas.rect(shape);
    }

    /// Fills the bounds with a material of the canvas, from what is drawn
    /// under them so far.
    pub fn material(
        self: Painter,
        corners: gfx.Corners,
        with: gfx.MaterialFill,
    ) void {
        var shape = self.rect(corners);
        shape.material = with;
        self.canvas.rect(shape);
    }

    /// The stroke is kept inside the bounds.
    pub fn stroke(
        self: Painter,
        corners: gfx.Corners,
        width: f32,
        color: gfx.Color,
    ) void {
        if (color.a == 0 or width <= 0) return;

        var shape = self.rect(corners);
        shape.color = .transparent;
        shape.border = .{
            .width = width,
            .color = color,
        };
        self.canvas.rect(shape);
    }

    /// The time of this frame in seconds, on the clock of Context.now.
    pub fn now(self: Painter) f64 {
        return self.target.now;
    }

    /// Asks for another frame at `time`, for a drawing that changes with the
    /// time, such as a blinking caret, without anything being built again.
    pub fn again(self: Painter, time: f64) void {
        self.target.again = @min(self.target.again, time);
    }
};

/// Draws a widget in `paint`, and around its children in `beginPaint` and
/// `endPaint`. What a popup shows is left to `popup.paint`, which draws it
/// after everything else.
pub fn paint(node: anytype, target: *Target) void {
    const Widget = @TypeOf(node.widget);
    const painter: Painter = .{
        .canvas = target.canvas,
        .bounds = node_zig.boundsOf(node),
        .target = target,
    };

    if (comptime has(Widget, "paint")) node.widget.paint(painter);
    if (comptime has(Widget, "beginPaint")) node.widget.beginPaint(painter);

    if (comptime node_zig.isPopup(Widget)) {
        paint(&node.children[0], target);
    } else {
        _ = node_zig.each(node, .shown, paint, .{target});
    }

    if (comptime has(Widget, "endPaint")) node.widget.endPaint(painter);
}
