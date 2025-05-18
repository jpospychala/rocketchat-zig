const std = @import("std");
const testing = std.testing;
const json = std.json;
const websocket = @import("websocket");

const Msg = struct {
    msg: []const u8,
    id: []const u8,
    method: []const u8,
    params: []const LoginMethod,
};

const LoginMethod = struct {
    password: []const u8,
    user: LoginMethodUser,
};

const LoginMethodUser = struct {
    username: ?[]const u8,
    //email: ?[]const u8,
};

pub const RC = struct {
    host: []const u8,
    client: websocket.Client,
    allocator: std.mem.Allocator,
    nextId: usize = 1,
    thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, config: websocket.Client.Config) !RC {
        const client = try websocket.Client.init(allocator, config);

        const this = RC{
            .host = config.host,
            .client = client,
            .allocator = allocator,
        };

        return this;
    }

    pub fn deinit(this: *@This()) void {
        this.client.deinit();
    }

    pub fn connect(this: *@This()) !void {
        const request_path = "/websocket";
        const headers = try std.fmt.allocPrint(this.allocator, "Host: {s}", .{
            this.host,
        });
        defer this.allocator.free(headers);

        try this.client.handshake(request_path, .{
            .timeout_ms = 1000,
            // Raw headers to send, if any.
            // A lot of servers require a Host header.
            // Separate multiple headers using \r\n
            .headers = headers,
        });

        // optional, read will return null after 1 second
        try this.client.readTimeout(std.time.ms_per_s * 1);

        const msg = try this.allocator.dupe(u8, "{\"msg\":\"connect\",\"version\":\"pre2\",\"support\":[\"pre2\"]}");
        defer this.allocator.free(msg);
        try this.client.writeText(msg);
    }

    pub fn startLoop(this: *@This()) !void {
        this.thread = try this.client.readLoopInNewThread(this);
        this.thread.?.detach();
    }

    pub fn join(this: *@This()) void {
        this.thread.?.join();
    }

    pub fn login(this: *@This(), username: []const u8, password: []const u8) !void {
        const id = try std.fmt.allocPrint(this.allocator, "{d}", .{this.nextId});
        defer this.allocator.free(id);
        this.nextId += 1;

        const msg: Msg = .{
            .msg = "method",
            .id = id,
            .method = "login",
            .params = &[_]LoginMethod{
                LoginMethod{
                    .password = password,
                    .user = .{ .username = username },
                },
            },
        };

        const msgStr = try json.stringifyAlloc(this.allocator, msg, .{});
        defer this.allocator.free(msgStr);
        try this.client.writeText(msgStr);
    }

    pub fn serverMessage(_: *@This(), data: []u8) !void {
        std.debug.print("recvd {s}\n", .{data});
    }
};

fn infiniteLoop(_: std.mem.Allocator, client: websocket.Client) void {
    // echo messages back to the server until the connection is closed
    while (true) {

        // since we didn't set a timeout, client.read() will either
        // return a message or an error (i.e. it won't return null)
        const message = (try client.read()) orelse {
            // no message after our 1 second
            std.debug.print(".", .{});
            continue;
        };

        // must be called once you're done processing the request
        defer client.done(message);

        switch (message.type) {
            .text, .binary => {
                std.debug.print("received: {s}\n", .{message.data});
                try client.write(message.data);
            },
            .ping => try client.writePong(message.data),
            .pong => {},
            .close => {
                try client.close(.{});
                break;
            },
        }
    }
}
