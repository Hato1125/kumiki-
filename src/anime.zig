const std = @import("std");

pub const Curve = union(enum) {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
    bezier: [4]f32,
    spring: Spring,

    /// Beziers and springs may overshoot [0, 1].
    pub fn apply(self: Curve, progress: f32) f32 {
        return switch (self) {
            .linear => progress,
            .ease_in => progress * progress * progress,
            .ease_out => 1 - std.math.pow(f32, 1 - progress, 3),
            .ease_in_out => if (progress < 0.5)
                4 * progress * progress * progress
            else
                1 - std.math.pow(f32, 2 - 2 * progress, 3) / 2,
            .bezier => |points| bezierAt(points, progress),
            .spring => |spring| if (progress >= 1)
                1
            else
                spring.position(progress * spring.settleTime()),
        };
    }
};

fn bezierCoordinate(first: f32, second: f32, along: f32) f32 {
    const rest = 1 - along;

    return 3 * rest * rest * along * first +
        3 * rest * along * along * second +
        along * along * along;
}

// x grows with the curve parameter, so bisection finds where x equals
// `target`.
fn bezierAt(points: [4]f32, target: f32) f32 {
    if (target <= 0) return 0;
    if (target >= 1) return 1;

    var low: f32 = 0;
    var high: f32 = 1;
    for (0..24) |_| {
        const middle = (low + high) / 2;
        if (bezierCoordinate(points[0], points[2], middle) < target) {
            low = middle;
        } else {
            high = middle;
        }
    }

    return bezierCoordinate(points[1], points[3], (low + high) / 2);
}

/// A unit mass on a spring, released at rest one unit away from where it
/// settles. `damping` is the damping ratio: below 1 the mass bounces.
pub const Spring = struct {
    damping: f32 = 1,
    stiffness: f32,

    const tolerance = 0.001;

    /// How far the mass has come after `time` seconds: 0 at the start, 1 at
    /// rest.
    pub fn position(self: Spring, time: f32) f32 {
        const frequency = @sqrt(self.stiffness);
        const ratio = self.damping;
        const decay = ratio * frequency;

        if (ratio < 1) {
            const damped = frequency * @sqrt(1 - ratio * ratio);
            const cosine = @cos(damped * time);
            const sine = @sin(damped * time);

            return 1 - @exp(-decay * time) * (cosine + decay / damped * sine);
        }

        if (ratio == 1)
            return 1 - @exp(-frequency * time) * (1 + frequency * time);

        const root = frequency * @sqrt(ratio * ratio - 1);
        const slow = root - decay;
        const fast = -root - decay;
        const mixed = fast * @exp(slow * time) - slow * @exp(fast * time);

        return 1 - mixed / (fast - slow);
    }

    /// Seconds until the mass stays within `tolerance` of rest. At critical
    /// damping, (1 + x) * exp(-x) falls below the tolerance at x = 9.2334.
    pub fn settleTime(self: Spring) f32 {
        const frequency = @sqrt(self.stiffness);
        const ratio = self.damping;
        const decades = -@log(@as(f32, tolerance));

        if (ratio < 1) return decades / (ratio * frequency);
        if (ratio == 1) return 9.2334 / frequency;

        return decades / (frequency * (ratio - @sqrt(ratio * ratio - 1)));
    }
};

pub const Animation = struct {
    duration: f32 = 0.25,
    curve: Curve = .ease_in_out,

    pub fn spring(damping: f32, stiffness: f32) Animation {
        const physics: Spring = .{
            .damping = damping,
            .stiffness = stiffness,
        };

        return .{
            .duration = physics.settleTime(),
            .curve = .{ .spring = physics },
        };
    }

    /// `points` are the x1, y1, x2, y2 of a CSS cubic-bezier().
    pub fn bezier(duration: f32, points: [4]f32) Animation {
        return .{
            .duration = duration,
            .curve = .{ .bezier = points },
        };
    }
};

pub fn Tween(comptime T: type) type {
    return struct {
        from: T,
        to: T,
        start: f64 = 0,
        running: bool = false,

        const Self = @This();

        pub fn init(value: T) Self {
            return .{
                .from = value,
                .to = value,
            };
        }

        /// Starts moving from the currently shown value toward `next`. An
        /// equal target is taken too, because it may hold newer strings.
        pub fn retarget(
            self: *Self,
            spec: Animation,
            next: T,
            now: f64,
        ) void {
            if (!same(T, next, self.to)) {
                self.from = self.at(spec, now);
                self.start = now;
                self.running = true;
            }

            self.to = next;
        }

        pub fn at(self: *const Self, spec: Animation, now: f64) T {
            if (!self.running) return self.to;

            const elapsed: f32 = @floatCast(now - self.start);
            const progress = if (spec.duration <= 0)
                1
            else
                std.math.clamp(elapsed / spec.duration, 0, 1);

            return lerp(T, self.from, self.to, spec.curve.apply(progress));
        }

        pub fn finish(self: *Self, spec: Animation, now: f64) void {
            const elapsed: f32 = @floatCast(now - self.start);
            if (elapsed >= spec.duration) self.running = false;
        }
    };
}

/// Compares slices by content, so a string that was formatted again into a
/// new buffer does not restart an animation.
pub fn same(comptime T: type, first: T, second: T) bool {
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (pointer.size != .slice) return std.meta.eql(first, second);
            if (first.len != second.len) return false;

            for (first, second) |first_item, second_item|
                if (!same(pointer.child, first_item, second_item)) return false;

            return true;
        },
        .@"struct" => |info| {
            inline for (
                info.field_names,
                info.field_types,
                info.field_attrs,
            ) |name, Field, attrs| {
                if (attrs.@"comptime") continue;

                const left = @field(first, name);
                const right = @field(second, name);
                if (!same(Field, left, right)) return false;
            }

            return true;
        },
        .optional => |optional| {
            if (first) |first_value|
                if (second) |second_value|
                    return same(optional.child, first_value, second_value);

            return first == null and second == null;
        },
        .array => |array| {
            for (first, second) |first_item, second_item|
                if (!same(array.child, first_item, second_item)) return false;

            return true;
        },
        else => return std.meta.eql(first, second),
    }
}

/// Values that cannot be interpolated, such as slices and enums, switch to
/// `second` at once. `progress` may leave [0, 1]; integers then stop at the
/// ends of their range. They go through f64, which holds every 32-bit
/// integer exactly. A struct that declares `lerp(first, second, progress)` is
/// interpolated by it instead of field by field.
pub fn lerp(comptime T: type, first: T, second: T, progress: f32) T {
    const custom = comptime @typeInfo(T) == .@"struct" and
        @hasDecl(T, "lerp");
    if (custom) return T.lerp(first, second, progress);

    switch (@typeInfo(T)) {
        .float => {
            return first + (second - first) * @as(T, @floatCast(progress));
        },
        .int => {
            if (first == second) return first;

            const from: f64 = @floatFromInt(first);
            const to: f64 = @floatFromInt(second);

            return std.math.lossyCast(T, @round(from + (to - from) * progress));
        },
        .@"struct" => |info| {
            var result: T = second;
            inline for (
                info.field_names,
                info.field_types,
                info.field_attrs,
            ) |name, Field, attrs| {
                if (attrs.@"comptime") continue;

                const left = @field(first, name);
                const right = @field(second, name);
                @field(result, name) = lerp(Field, left, right, progress);
            }

            return result;
        },
        .optional => |optional| {
            if (first) |first_value|
                if (second) |second_value|
                    return lerp(
                        optional.child,
                        first_value,
                        second_value,
                        progress,
                    );

            return second;
        },
        .array => |array| {
            var result: T = second;
            for (&result, first, second) |*item, first_item, second_item|
                item.* = lerp(array.child, first_item, second_item, progress);

            return result;
        },
        else => return second,
    }
}
