const types = @import("types");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const scene = @import("scene");
const pass = scene.layout;
const mod = scene.mod;

/// The config of a `when`: shows the first child while `cond_fn` returns true
/// and the second otherwise. Both are kept, so switching back and forth keeps
/// their state.
pub fn When(comptime cond_fn: anytype) type {
    return struct {
        active: bool = true,

        const Self = @This();

        pub const cond = cond_fn;

        pub fn shows(self: Self, comptime child: usize) bool {
            return (child == 0) == self.active;
        }

        pub fn measureAll(
            self: Self,
            children: anytype,
            constraint: Constraint,
        ) Extent {
            if (self.active) return pass.measure(&children[0], constraint);

            return pass.measure(&children[1], constraint);
        }

        pub fn layoutAll(
            self: Self,
            children: anytype,
            at: Point,
            _: Extent,
        ) void {
            if (self.active) {
                pass.layout(&children[0], at);
            } else {
                pass.layout(&children[1], at);
            }
        }
    };
}

/// Shows `first` while `cond` returns true and `second` otherwise. The
/// parameters of `cond` are filled in by type like those of `ui.show`.
pub fn when(
    comptime cond: anytype,
    first: anytype,
    second: anytype,
) mod.Container(struct {
    @TypeOf(first),
    @TypeOf(second),
}, When(cond)) {
    return .{
        .children = .{
            first,
            second,
        },
        .config = .{},
    };
}
