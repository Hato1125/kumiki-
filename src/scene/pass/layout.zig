const types = @import("types");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;

const node_zig = @import("../base/node.zig");
const each = node_zig.each;
const has = node_zig.has;

/// Measures `node` and everything inside it, and returns its size, which also
/// stays in `node.size`. A config measures all of its children in
/// `measureAll`, or the one child of a modifier in `measure`.
pub fn measure(node: anytype, constraint: Constraint) Extent {
    const Widget = @TypeOf(node.widget);
    const children = &node.children;

    if (comptime node_zig.isComponent(Widget)) node.constraint = constraint;

    node.size = if (comptime @TypeOf(children.*) == void)
        (if (comptime has(Widget, "measure"))
            node.widget.measure(constraint)
        else
            constraint.min)
    else if (comptime has(Widget, "measureAll"))
        node.widget.measureAll(children, constraint)
    else if (comptime has(Widget, "measure"))
        node.widget.measure(&children[children.len - 1], constraint)
    else
        measureLast(children, constraint);

    return node.size;
}

fn measureLast(children: anytype, constraint: Constraint) Extent {
    const size = measure(&children[children.len - 1], constraint);

    inline for (0..children.len - 1) |i|
        _ = measure(&children[i], .tight(size));

    return size;
}

/// Places `node`, which was measured before, and everything inside it. A
/// config that declares `place(config, at) Point` moves the node from `at` to
/// where that returns.
pub fn layout(node: anytype, given: Point) void {
    const Widget = @TypeOf(node.widget);
    const children = &node.children;
    const at = if (comptime has(Widget, "place"))
        node.widget.place(given)
    else
        given;

    if (comptime @TypeOf(node.offset) != void) node.offset = at;
    if (comptime @TypeOf(children.*) == void) return;

    if (comptime has(Widget, "layoutAll"))
        return node.widget.layoutAll(children, at, node.size);

    if (comptime has(Widget, "layout")) {
        return node.widget.layout(
            &children[children.len - 1],
            at,
            node.size,
        );
    }

    _ = each(node, .all, layout, .{at});
}

/// The share of the free space that a row or column gives this child, seen
/// through components.
pub fn flexOf(node: anytype) f32 {
    const Widget = @TypeOf(node.widget);
    if (comptime node_zig.isComponent(Widget))
        return flexOf(&node.children[0]);

    return if (comptime @hasField(Widget, "flex")) node.widget.flex else 0;
}
