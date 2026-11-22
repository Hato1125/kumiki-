const std = @import("std");

const gfx = @import("gfx");
const Image = @import("image").Image;
const types = @import("types");
const Constraint = types.Constraint;
const Extent = types.Extent;
const scene = @import("scene");
const mod = scene.mod;
const Painter = scene.paint.Painter;

/// How an image goes into a box of another shape: stretched over it, as
/// large as fits inside, or as small as covers it with the rest cut off.
pub const Fit = gfx.Fit;

/// The config of an image at its own size, or smaller with the same shape
/// where space is short. With a fit it takes the space offered instead, like
/// a rect. Its settings are methods of the container.
pub const Picture = struct {
    source: ?Image,
    fitting: ?Fit = null,

    pub fn measure(self: Picture, constraint: Constraint) Extent {
        const max = constraint.max;
        const natural: Extent = if (self.source) |source|
            source.size()
        else
            .{};

        if (self.fitting != null) {
            return constraint.constrain(.{
                .width = if (std.math.isInf(max.width)) natural.width else max.width,
                .height = if (std.math.isInf(max.height)) natural.height else max.height,
            });
        }

        if (natural.width <= 0 or natural.height <= 0) return constraint.min;

        const scale = @min(
            1,
            max.width / natural.width,
            max.height / natural.height,
        );

        return constraint.constrain(.{
            .width = natural.width * scale,
            .height = natural.height * scale,
        });
    }

    pub fn paint(self: Picture, painter: Painter) void {
        const source = self.source orelse return;
        const uploaded = source.on(painter.canvas) orelse return;

        painter.canvas.image(.{
            .image = uploaded,
            .x = painter.bounds.x,
            .y = painter.bounds.y,
            .width = painter.bounds.w,
            .height = painter.bounds.h,
            .fit = self.fitting orelse .contain,
        });
    }
};

/// Shows `source`, or nothing while it is null.
pub fn image(source: ?Image) mod.Container(void, Picture) {
    return mod.leaf(Picture{ .source = source });
}
