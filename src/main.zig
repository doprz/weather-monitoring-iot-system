const std = @import("std");
const log = std.log.scoped(.server);

const server = @import("server.zig");
const sensor = @import("sensor.zig");

pub fn main(init: std.process.Init) !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    var i: u32 = 0;
    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    while (args.next()) |arg| : (i += 1) {
        log.debug("arg[{d}]={s}", .{ i, arg });
    }

    var state = sensor.State.init();

    log.info("Starting server", .{});
    // try server.startServer(gpa, init.io);

    log.info("Listening on http://{s}:{d}", .{ server.LISTEN_ADDR, server.LISTEN_PORT });
    const addr = std.Io.net.IpAddress.parseIp4(server.LISTEN_ADDR, server.LISTEN_PORT) catch unreachable;

    // TCP layer: bind the port and accept the raw stream
    var tcp_server = try addr.listen(init.io, .{ .reuse_address = true });
    defer tcp_server.deinit(init.io);

    // Main event loop
    while (true) {
        // Sensor
        const duration = std.Io.Duration.fromMilliseconds(1000);
        try std.Io.sleep(init.io, duration, .real);
        state.tick();

        // Server
        log.info("Waiting for connection...", .{});
        var stream = try tcp_server.accept(init.io);
        defer stream.close(init.io);
        log.info("TCP connection established", .{});

        // Wrap the raw stream in buffered Io.Reader / Io.Writer
        var read_buffer: [1024]u8 = undefined;
        var write_buffer: [1024]u8 = undefined;
        var reader = stream.reader(init.io, &read_buffer);
        var writer = stream.writer(init.io, &write_buffer);

        // HTTP layer: parse the byte stream at HTTP/1.1
        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var req = try http_server.receiveHead();

        const method = req.head.method;
        const route = std.mem.sliceTo(req.head.target, '?');
        log.info("{s} {s}", .{ @tagName(method), req.head.target });

        if (std.mem.eql(u8, route, "/config")) {
            switch (method) {
                .GET => server.serveConfigGet(gpa, &req, &state) catch |err| {
                    log.err("config GET: {}", .{err});
                },
                // TODO: POST
                else => req.respond("405 Method Not Allowed\n", .{ .status = .method_not_allowed }) catch |err| {
                    log.err("Failed to send response: {}", .{err});
                },
            }
        } else if (std.mem.eql(u8, route, "/metrics")) {
            server.serveMetrics(gpa, &req, &state) catch |err| {
                log.err("metrics: {}", .{err});
            };
        } else {
            try req.respond("404 Not Found\n", .{ .status = .not_found });
        }
    }
}
