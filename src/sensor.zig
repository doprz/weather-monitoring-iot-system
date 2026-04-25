const std = @import("std");
const log = std.log.scoped(.sensor);

/// Simulation parameters that can be patched at runtime via POST /config.
/// All fields are optional in the JSON body; omitted fields keep their current
/// value (requires .ignore_unknown_fields = true during parse).
pub const Config = struct {
    /// Milliseconds between sensor ticks.
    update_interval_ms: u64 = 1000,
    /// Peak random-walk magnitude for temperature (deg C per tick).
    temperature_variance: f64 = 0.75,
    /// Peak random-walk magnitude for humidity (% per tick).
    humidity_variance: f64 = 1.0,
    /// Peak random-walk magnitude for pressure (hPa per tick).
    pressure_variance: f64 = 0.25,
};

/// A consistent snapshot of all three simulated sensors.
pub const SensorData = struct {
    /// Temperature in deg C, clamped to [-50, 100].
    temperature: f64 = 25.0,
    /// Relative humidity %, clamped to [0, 100].
    humidity: f64 = 55.0,
    /// Atmospheric pressure hPa, clamped to [850, 1080].
    pressure: f64 = 1010.0,
};

pub const State = struct {
    config: Config = .{},
    sensors: SensorData = .{},
    prng: std.Random.DefaultPrng,

    pub fn init() State {
        // TODO: Use a different seed
        return .{ .prng = std.Random.DefaultPrng.init(100) };
    }

    pub fn getConfig(self: *State) Config {
        return self.config;
    }

    pub fn setConfig(self: *State, c: Config) void {
        self.config = c;
    }

    pub fn snapshot(self: *State) SensorData {
        return self.sensors;
    }

    pub fn tick(self: *State) void {
        const r = self.prng.random();
        const conf = self.config;

        self.sensors.temperature = std.math.clamp(
            self.sensors.temperature + randomStep(r, conf.temperature_variance),
            -50.0,
            100.0,
        );
        self.sensors.humidity = std.math.clamp(
            self.sensors.humidity + randomStep(r, conf.humidity_variance),
            0.0,
            100.0,
        );
        self.sensors.pressure = std.math.clamp(
            self.sensors.pressure + randomStep(r, conf.pressure_variance),
            850.0,
            1080.0,
        );
    }
};

pub fn randomStep(r: std.Random, variance: f64) f64 {
    return (r.float(f64) * 2.0 - 1.0) * variance;
}
