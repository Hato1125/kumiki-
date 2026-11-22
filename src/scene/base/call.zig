const std = @import("std");

const types = @import("types");
const Constraint = types.Constraint;

const Context = @import("cx.zig");
const node_zig = @import("node.zig");
const ReturnOf = node_zig.ReturnOf;
const State = node_zig.State;
const each = node_zig.each;
const isComponent = node_zig.isComponent;

/// Where a value lives among the owners: in a field of an owner, as what the
/// owner provides, or as the owner itself.
pub const Source = struct {
    owner: usize,
    field: ?[]const u8 = null,
    given: bool = false,
};

pub fn Pointee(comptime Param: type) type {
    return switch (@typeInfo(Param)) {
        .pointer => |pointer| pointer.child,
        else => Param,
    };
}

fn WidgetOf(comptime Owner: type) type {
    return @FieldType(@typeInfo(Owner).pointer.child, "widget");
}

/// `Owners` holds pointers to the nodes of the enclosing components, the
/// outermost first. The nearest component of type `Param`, or pointed to by
/// `Param`, wins. When there is none, the value comes from the nearest
/// component that shares a field of that type with
/// `pub const shares = .field_name` or provides that type, which lets
/// components share a value, such as a theme, without knowing who holds it.
pub fn find(comptime Owners: type, comptime Param: type) ?Source {
    const T = Pointee(Param);
    const owners = @typeInfo(Owners).@"struct".field_types;

    var i = owners.len;
    while (i > 0) {
        i -= 1;
        if (WidgetOf(owners[i]) == T) return .{ .owner = i };
    }

    i = owners.len;
    while (i > 0) {
        i -= 1;
        const Widget = WidgetOf(owners[i]);
        if (@hasDecl(Widget, "shares")) {
            const name = @tagName(Widget.shares);

            if (@FieldType(Widget, name) == T) {
                return .{
                    .owner = i,
                    .field = name,
                };
            }
        }

        if (node_zig.provides(Widget) and node_zig.Provided(Widget) == T) {
            return .{
                .owner = i,
                .given = true,
            };
        }
    }

    return null;
}

pub fn source(comptime Owners: type, comptime Param: type) Source {
    return find(Owners, Param) orelse
        @compileError("no enclosing component is, shares or provides a " ++
            @typeName(Pointee(Param)) ++ " for this parameter");
}

/// Whether a parameter of type `Param` is filled in from the owners. One that
/// is not stands for the event.
pub fn fills(comptime Owners: type, comptime Param: type) bool {
    if (Param == Context or Param == Constraint) return true;

    return isCallback(Param) or find(Owners, Param) != null;
}

/// A function that a component is given when it is written in a view, for the
/// component to call later: `func` is a function, or `{}` for none. A function
/// of the component receives it by declaring a parameter of this type and
/// runs it with `call`. The parameters of `func` are filled in by type as if
/// it were given to a modifier at the place of the component, and the
/// components it receives as mutable pointers are built again.
pub fn Callback(comptime func: anytype) type {
    return struct {
        owners: *const anyopaque = undefined,
        state: *const State = undefined,
        run: *const fn (*const anyopaque, *const State) void = undefined,

        pub const callee = func;

        pub fn call(given: @This()) void {
            if (@TypeOf(func) != void) given.run(given.owners, given.state);
        }
    };
}

fn isCallback(comptime Param: type) bool {
    return @typeInfo(Param) == .@"struct" and @hasDecl(Param, "callee");
}

fn Outer(comptime Owners: type) type {
    const field_types = @typeInfo(Owners).@"struct".field_types;

    return @Tuple(field_types[0 .. field_types.len - 1]);
}

/// The owners of what is inside `node`: a component joins those around it.
pub fn ownersIn(
    node: anytype,
    owners: anytype,
) OwnersIn(@TypeOf(node), @TypeOf(owners)) {
    if (comptime !isComponent(@TypeOf(node.widget))) return owners;

    return owners ++ .{node};
}

fn OwnersIn(comptime NodePtr: type, comptime Owners: type) type {
    if (!isComponent(WidgetOf(NodePtr))) return Owners;

    return @Tuple(@typeInfo(Owners).@"struct".field_types ++ .{NodePtr});
}

fn bind(comptime Param: type, owners: anytype, state: *const State) Param {
    if (@TypeOf(Param.callee) == void) return .{};

    const Owners = @TypeOf(owners.*);

    return .{
        .owners = owners,
        .state = state,
        .run = struct {
            fn run(erased: *const anyopaque, shared: *const State) void {
                const inner: *const Owners = @ptrCast(@alignCast(erased));
                var outer: Outer(Owners) = undefined;
                inline for (0..outer.len) |i| outer[i] = inner.*[i];

                invoke(Param.callee, outer, shared, {});
                markTargets(Param.callee, outer);
            }
        }.run,
    };
}

fn argument(
    comptime Param: type,
    owners: anytype,
    state: *const State,
    event: anytype,
) Param {
    if (Param == Context) {
        if (owners.len == 0)
            @compileError("ui.Context is only available inside a component");

        const node = owners.*[owners.len - 1];

        return .{
            .id = node.id,
            .state = state,
            .arena = &node.arena,
            .gpa = state.gpa,
            .size = node.size,
        };
    }
    if (Param == Constraint) {
        if (owners.len == 0) {
            @compileError(
                "ui.Constraint is only available inside a component",
            );
        }

        const node = owners.*[owners.len - 1];
        node.read = node.constraint;

        return node.constraint;
    }

    if (Param == @TypeOf(event)) return event;
    if (comptime isCallback(Param)) return bind(Param, owners, state);

    const from = comptime source(@TypeOf(owners.*), Param);
    const pointer = comptime @typeInfo(Param) == .pointer;

    if (comptime from.given) {
        if (comptime pointer and !@typeInfo(Param).pointer.attrs.@"const") {
            @compileError(
                "a " ++ @typeName(Pointee(Param)) ++ " is provided, " ++
                    "so it is received by value or as a const pointer",
            );
        }

        const given = &owners.*[from.owner].given;

        return if (pointer) given else given.*;
    }

    const widget = &owners.*[from.owner].widget;
    const value = if (comptime from.field) |name|
        &@field(widget, name)
    else
        widget;

    return if (pointer) value else value.*;
}

/// Calls `func`, filling each parameter by its type: a component type, or a
/// pointer to one, receives the nearest enclosing component of that type, any
/// other type receives what the nearest component that shares or provides one
/// has of it, ui.Context receives the Context of the nearest component,
/// ui.Constraint what that component was last measured with, and the type of
/// `event` receives the event being handled. A component whose functions
/// receive ui.Constraint is built again when it is measured with another.
pub fn invoke(
    comptime func: anytype,
    owners: anytype,
    state: *const State,
    event: anytype,
) ReturnOf(func) {
    var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
    const params = @typeInfo(@TypeOf(func)).@"fn".param_types;

    inline for (params, 0..) |param_type, i| {
        const Param = param_type orelse
            @compileError("parameters must have concrete types");
        args[i] = argument(Param, &owners, state, event);
    }

    return @call(.auto, func, args);
}

/// A component received as a mutable pointer may have been changed, so it and
/// everything inside it are built again. The same goes for the component
/// sharing a field received as a mutable pointer. A pointer that no owner
/// fills in is the event, such as the result of a background function.
pub fn markTargets(comptime func: anytype, owners: anytype) void {
    inline for (@typeInfo(@TypeOf(func)).@"fn".param_types) |param_type| {
        const Param = param_type.?;
        const info = @typeInfo(Param);

        if (comptime info == .pointer and !info.pointer.attrs.@"const") {
            if (comptime find(@TypeOf(owners), Param)) |from|
                markAll(owners[from.owner]);
        }
    }
}

pub fn markAll(node: anytype) void {
    if (comptime isComponent(@TypeOf(node.widget))) node.dirty = true;
    _ = each(node, .all, markAll, .{});
}
