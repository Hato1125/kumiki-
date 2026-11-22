pub fn Each(
    comptime count: usize,
    comptime Component: anytype,
    comptime args: anytype,
) type {
    var element_types: [count]type = undefined;
    for (0..count) |i|
        element_types[i] = @call(.auto, Component, args ++ .{i});

    return @Tuple(&element_types);
}

/// Places `count` components as the children of a container. `Component` is a
/// function that returns the type of a component: it is called once for each
/// child with `args` followed by the index of the child, whose fields start
/// at their default values.
pub fn each(
    comptime count: usize,
    comptime Component: anytype,
    comptime args: anytype,
) Each(count, Component, args) {
    var components: Each(count, Component, args) = undefined;
    inline for (0..count) |i| components[i] = .{};

    return components;
}
