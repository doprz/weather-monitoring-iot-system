const std = @import("std");
const log = std.log.scoped(.server);
const sensor = @import("sensor.zig");

// pub const LISTEN_ADDR = "127.0.0.1";
pub const LISTEN_ADDR = "0.0.0.0"; // Bind to all interfaces
pub const LISTEN_PORT = 8000;

pub fn serveConfigGet(allocator: std.mem.Allocator, req: *std.http.Server.Request, state: *sensor.State) !void {
    var json_string: std.Io.Writer.Allocating = .init(allocator);
    defer json_string.deinit();
    try json_string.writer.print("{f}", .{std.json.fmt(state.getConfig(), .{})});

    const output = json_string.written();
    log.info("json output: {s}", .{output});

    try req.respond(output, .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }} });
}

pub fn serveMetrics(allocator: std.mem.Allocator, req: *std.http.Server.Request, state: *sensor.State) !void {
    const s = state.snapshot();

    // INFO: https://prometheus.io/docs/instrumenting/exposition_formats/
    // INFO: https://prometheus.io/docs/specs/om/open_metrics_spec/
    const body = try std.fmt.allocPrint(allocator,
        \\# HELP sensor_temperature Current temperature in degrees Celsius.
        \\# TYPE sensor_temperature gauge
        \\sensor_temperature {d:.4}
        \\# HELP sensor_humidity Current relative humidity in percent.
        \\# TYPE sensor_humidity gauge
        \\sensor_humidity {d:.4}
        \\# HELP sensor_pressure Current atmospheric pressure in hPa.
        \\# TYPE sensor_pressure gauge
        \\sensor_pressure {d:.4}
        \\# EOF\n
    , .{ s.temperature, s.humidity, s.pressure });

    try req.respond(body, .{ .extra_headers = &.{.{
        .name = "Content-Type",
        .value = "application/openmetrics-text; version=1.0.0; charset=utf-8",
    }} });
}

pub fn startServer(allocator: std.mem.Allocator, io: std.Io) !void {
    log.info("Listening on http://{s}:{d}", .{ LISTEN_ADDR, LISTEN_PORT });
    const addr = std.Io.net.IpAddress.parseIp4(LISTEN_ADDR, LISTEN_PORT) catch unreachable;

    // TCP layer: bind the port and accept the raw stream
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    while (true) {
        log.info("Waiting for connection...", .{});
        var stream = try server.accept(io);
        defer stream.close(io);
        log.info("TCP connection established", .{});

        // Wrap the raw stream in buffered Io.Reader / Io.Writer
        var read_buffer: [1024]u8 = undefined;
        var write_buffer: [1024]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var writer = stream.writer(io, &write_buffer);

        // HTTP layer: parse the byte stream at HTTP/1.1
        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var req = try http_server.receiveHead();

        const method = req.head.method;
        const route = std.mem.sliceTo(req.head.target, '?');
        log.info("{s} {s}", .{ @tagName(method), req.head.target });

        // TODO: tmp
        var state = sensor.State.init();
        log.info("config: {}", .{state.getConfig()});

        if (std.mem.eql(u8, route, "/config")) {
            switch (method) {
                .GET => serveConfigGet(allocator, &req, &state) catch |err| {
                    log.err("config GET: {}", .{err});
                },
                // TODO: POST
                else => req.respond("405 Method Not Allowed\n", .{ .status = .method_not_allowed }) catch |err| {
                    log.err("Failed to send response: {}", .{err});
                },
            }
        } else if (std.mem.eql(u8, route, "/metrics")) {
            serveMetrics(allocator, &req, &state) catch |err| {
                log.err("metrics: {}", .{err});
            };
        } else {
            try req.respond("404 Not Found\n", .{ .status = .not_found });
        }
    }
}
