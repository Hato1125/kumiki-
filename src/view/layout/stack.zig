const types = @import("types");
const Alignment = types.Alignment;
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const scene = @import("scene");
const pass = scene.layout;
const mod = scene.mod;

/// The config of a stack: children lie on top of each other, later ones in
/// front, and the stack is as large as its largest child.
pub const Stack = struct {
    alignment: Alignment = .center,

    pub fn measureAll(
        _: Stack,
        children: anytype,
        constraint: Constraint,
    ) Extent {
        var size: Extent = .{};

        inline for (0..children.len) |i| {
            const child = pass.measure(&children[i], constraint.loosen());
            size = .{
                .width = @max(size.width, child.width),
                .height = @max(size.height, child.height),
            };
        }

        return constraint.constrain(size);
    }

    pub fn layoutAll(
        self: Stack,
        children: anytype,
        at: Point,
        size: Extent,
    ) void {
        inline for (0..children.len) |i| {
            const child = &children[i];
            pass.layout(child, self.alignment.place(at, size, child.size));
        }
    }
};

pub fn stack(children: anytype) mod.Container(mod.Runtime(@TypeOf(children)), Stack) {
    return .{
        .children = children,
        .config = .{},
    };
}
