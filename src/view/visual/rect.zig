const Corners = @import("gfx").Corners;
const types = @import("types");
const Color = types.Color;
const Constraint = types.Constraint;
const Extent = types.Extent;
const mod = @import("scene").mod;
const Painter = @import("scene").paint.Painter;

/// The config of a rectangle that fills the space offered. Its settings are
/// methods of the container.
pub const Rect = struct {
    fill_color: Color = .black,
    stroke_color: Color = .transparent,
    stroke_width: f32 = 0,
    corner: Corners = .{},

    pub fn measure(_: Rect, c: Constraint) Extent {
        return c.biggest();
    }

    pub fn paint(self: Rect, p: Painter) void {
        p.fill(self.corner, self.fill_color);
        p.stroke(self.corner, self.stroke_width, self.stroke_color);
    }
};

pub fn rect() mod.Container(void, Rect) {
    return mod.leaf(Rect{});
}
