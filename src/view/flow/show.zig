const mod = @import("scene").mod;

/// The config of a `show`, which stands for the view that `view_fn` returns
/// and is replaced by it when the tree is built.
pub fn Show(comptime view_fn: anytype) type {
    return struct {
        pub const func = view_fn;
    };
}

/// Shows the view that `view_fn` returns. `view_fn` runs whenever the view is
/// built, and its parameters are filled in by type, as described at `invoke`
/// in call.zig.
pub fn show(comptime view_fn: anytype) mod.Container(void, Show(view_fn)) {
    return mod.leaf(Show(view_fn){});
}
