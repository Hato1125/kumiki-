const std = @import("std");

const types = @import("types");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("scene").layout;

pub const Axis = enum {
    horizontal,
    vertical,
};

pub const MainAlign = enum {
    start,
    center,
    end,
    between,
};

pub const CrossAlign = enum {
    start,
    center,
    end,
    stretch,
};

/// The config of a row or column. Children with a flex factor share the free
/// space in proportion to it. The container spans the whole axis when it has
/// such children or when `main` needs free space to distribute.
pub fn Flex(comptime axis: Axis) type {
    return struct {
        gap: f32 = 0,
        main: MainAlign = .start,
        cross: CrossAlign = .start,

        const Self = @This();

        fn mainOf(size: Extent) f32 {
            return if (axis == .horizontal) size.width else size.height;
        }

        fn crossOf(size: Extent) f32 {
            return if (axis == .horizontal) size.height else size.width;
        }

        fn extent(along: f32, across: f32) Extent {
            return if (axis == .horizontal)
                .{ .width = along, .height = across }
            else
                .{ .width = across, .height = along };
        }

        fn gaps(self: Self, count: usize) f32 {
            return self.gap * @as(f32, @floatFromInt(@max(count, 1) - 1));
        }

        fn measureChild(
            self: Self,
            child: anytype,
            constraint: Constraint,
            min: f32,
            max: f32,
        ) Extent {
            const across = crossOf(constraint.max);
            const stretched = self.cross == .stretch and
                !std.math.isInf(across);

            return pass.measure(child, .{
                .min = extent(min, if (stretched) across else 0),
                .max = extent(max, across),
            });
        }

        pub fn measureAll(
            self: Self,
            children: anytype,
            constraint: Constraint,
        ) Extent {
            const space = mainOf(constraint.max);
            const bounded = !std.math.isInf(space);
            var used = self.gaps(children.len);
            var across: f32 = 0;
            var factors: f32 = 0;

            inline for (0..children.len) |i| {
                const factor = pass.flexOf(&children[i]);

                if (factor > 0) {
                    factors += factor;
                } else {
                    const size = self.measureChild(
                        &children[i],
                        constraint,
                        0,
                        types.inf,
                    );
                    used += mainOf(size);
                    across = @max(across, crossOf(size));
                }
            }

            const free = if (bounded) @max(0, space - used) else 0;

            inline for (0..children.len) |i| {
                const factor = pass.flexOf(&children[i]);

                if (factor > 0) {
                    const share = free * factor / factors;
                    const size = self.measureChild(
                        &children[i],
                        constraint,
                        share,
                        share,
                    );
                    used += mainOf(size);
                    across = @max(across, crossOf(size));
                }
            }

            const limit = crossOf(constraint.max);
            if (self.cross == .stretch and !std.math.isInf(limit))
                across = limit;

            const fills = bounded and (factors > 0 or self.main != .start);
            const along = if (fills) space else used;

            return constraint.constrain(extent(along, across));
        }

        pub fn layoutAll(
            self: Self,
            children: anytype,
            at: Point,
            size: Extent,
        ) void {
            var used = self.gaps(children.len);
            inline for (0..children.len) |i| used += mainOf(children[i].size);

            const extra = @max(0, mainOf(size) - used);
            var along: f32 = switch (self.main) {
                .start, .between => 0,
                .center => extra / 2,
                .end => extra,
            };

            const step = if (self.main == .between and children.len > 1)
                self.gap + extra / @as(f32, @floatFromInt(children.len - 1))
            else
                self.gap;

            inline for (0..children.len) |i| {
                const free = crossOf(size) - crossOf(children[i].size);
                const across: f32 = switch (self.cross) {
                    .start, .stretch => 0,
                    .center => free / 2,
                    .end => free,
                };
                const offset = extent(along, across);

                pass.layout(&children[i], .{
                    .x = at.x + offset.width,
                    .y = at.y + offset.height,
                });
                along += mainOf(children[i].size) + step;
            }
        }
    };
}
