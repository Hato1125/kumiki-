const Corners = @import("gfx").Corners;
const types = @import("types");
const Color = types.Color;
const Constraint = types.Constraint;
const Extent = types.Extent;
const scene = @import("scene");
const mod = scene.mod;
const Painter = scene.paint.Painter;

/// The config of a rectangle that fills the space offered. Its settings are
/// methods of the container.
pub const Rect = struct {
    fill_color: Color = .black,
    stroke_color: Color = .transparent,
    stroke_width: f32 = 0,
    corner: Corners = .{},

    pub fn measure(_: Rect, constraint: Constraint) Extent {
        return constraint.biggest();
    }

    pub fn paint(self: Rect, painter: Painter) void {
        painter.fill(self.corner, self.fill_color);
        painter.stroke(self.corner, self.stroke_width, self.stroke_color);
    }
};

pub fn rect() mod.Container(void, Rect) {
    return mod.leaf(Rect{});
}
