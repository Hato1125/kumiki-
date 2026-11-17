const anim = @import("anime");
const gfx = @import("gfx");
const image_zig = @import("image");
const text_zig = @import("text");
const types = @import("types");
const scene = @import("scene");
const input = scene.input;
const mod = scene.mod;
const pass = scene.layout;
const window = @import("host");
const view = @import("view");

test {
    @import("std").testing.refAllDecls(@This());
}

pub const run = window.run;
pub const Window = window.Window;

pub const Scene = scene.Scene;
pub const Event = input.Event;
pub const MouseButton = input.MouseButton;
pub const MouseButtonEvent = input.MouseButtonEvent;
pub const Pointer = input.Pointer;
pub const Wheel = input.Wheel;
pub const Hover = input.Hover;
pub const Drop = input.Drop;
pub const KeyPress = input.KeyPress;
pub const Chord = input.Chord;
pub const TextInput = input.TextInput;
pub const keys = input.keys;
pub const startup = text_zig.startup;
pub const addFont = text_zig.addFont;
pub const textSystem = text_zig.system;
pub const setTextScale = text_zig.setScale;
pub const releaseImages = image_zig.release;

/// Lets go of the fonts and the images. The canvas that drew them has to
/// be gone by then.
pub fn shutdown() void {
    image_zig.shutdown();
    text_zig.shutdown();
}

pub const Color = types.Color;
pub const Point = types.Point;
pub const Extent = types.Extent;
pub const Size = types.Size;
pub const Bounds = types.Bounds;
pub const Range = types.Range;
pub const Constraint = types.Constraint;
pub const inf = types.inf;
pub const Alignment = types.Alignment;
pub const Placement = scene.popup.Placement;
pub const Transition = scene.popup.Transition;
pub const Animation = anim.Animation;
pub const Context = scene.Context;
pub const Callback = scene.call.Callback;

pub const measure = pass.measure;
pub const layout = pass.layout;
pub const offsetOf = scene.node.offsetOf;
pub const Painter = scene.paint.Painter;
pub const Canvas = gfx.Canvas;
pub const Layer = gfx.Layer;
pub const Corners = gfx.Corners;
pub const Material = gfx.Material;
pub const MaterialSource = gfx.MaterialSource;
pub const MaterialFill = gfx.MaterialFill;
pub const Insets = mod.Insets;

pub const Text = mod.Container(void, view.Text);
pub const Rect = mod.Container(void, view.Rect);
pub const Picture = mod.Container(void, view.Picture);
pub const Image = image_zig.Image;

pub const show = view.show;
pub const wrap = mod.wrap;

pub const text = view.text;
pub const rect = view.rect;
pub const image = view.image;
pub const spacer = view.spacer;
pub const row = view.row;
pub const column = view.column;
pub const stack = view.stack;
pub const list = view.list;
pub const when = view.when;
pub const select = view.select;
pub const each = view.each;
pub const Each = view.Each;
