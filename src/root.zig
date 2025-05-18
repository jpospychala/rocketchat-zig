const std = @import("std");
const testing = std.testing;
const json = std.json;
const websocket = @import("websocket");

const MethodMsg = struct {
    msg: []const u8,
    id: []const u8,
    method: []const u8,
    params: MethodParams,
};

const MethodParamsTg = enum {
    loginParams,
    params,
};

const MethodParams = union(MethodParamsTg) {
    loginParams: []const LoginMethodParams,
    params: []const []const u8,

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        switch (self) {
            .loginParams => |loginParams| {
                try jws.write(loginParams);
            },
            .params => |p| {
                try jws.write(p);
            },
        }
    }
};

const SubMsg = struct {
    msg: []const u8,
    id: []const u8,
    name: []const u8,
    params: []const json.Value,
};

const LoginMethodParams = struct {
    password: []const u8,
    user: LoginMethodUser,
};

const LoginMethodUser = struct {
    username: ?[]const u8,
    //email: ?[]const u8,
};

pub const RcMsg = struct {
    rid: []u8, // room id
    u_id: []u8, // user id
    msg: []u8, // msg
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
        try this._write(msg);
    }

    pub fn startLoop(this: *@This()) !void {
        this.thread = try this.client.readLoopInNewThread(this);
        this.thread.?.detach();
    }

    pub fn join(this: *@This()) void {
        this.thread.?.join();
    }

    pub fn login(this: *@This(), username: []const u8, password: []const u8) !void {
        try this.ddl_method("login", MethodParams{
            .loginParams = &[_]LoginMethodParams{
                LoginMethodParams{
                    .password = password,
                    .user = .{ .username = username },
                },
            },
        });

        try this.ddl_sub("meteor.loginServiceConfiguration", &[_]json.Value{});
    }

    pub fn reactToMessages(_: *@This(), _: fn (*@This(), RcMsg) void) !void {
        // this.msgHandler = handler;
        // todo: subscibeToMessages if not subscribed already
    }

    pub fn subscribeToMessages(this: *@This()) !void {
        try this.ddl_sub("stream-room-messages", &[_]json.Value{
            json.Value{ .string = "__my_messages__" },
            json.Value{ .bool = true },
        });
    }

    pub fn joinRooms(this: *@This(), roomId: []const u8) !void {
        try this.ddl_method("joinRoom", MethodParams{
            .params = &[_][]const u8{roomId},
        });
    }

    pub fn getRoomIdByNameOrId(this: *@This(), roomName: []const u8) !void {
        try this.ddl_method("getRoomIdByNameOrId", MethodParams{
            .params = &[_][]const u8{roomName},
        });
    }

    pub fn ddl_method(this: *@This(), method: []const u8, params: MethodParams) !void {
        const id = try std.fmt.allocPrint(this.allocator, "{d}", .{this.nextId});
        defer this.allocator.free(id);
        this.nextId += 1;

        const msg: MethodMsg = .{
            .msg = "method",
            .id = id,
            .method = method,
            .params = params,
        };

        const msgStr = try json.stringifyAlloc(this.allocator, msg, .{});
        defer this.allocator.free(msgStr);
        try this._write(msgStr);
    }

    pub fn ddl_sub(this: *@This(), topic: []const u8, params: []const json.Value) !void {
        const id = try std.fmt.allocPrint(this.allocator, "{d}", .{this.nextId});
        defer this.allocator.free(id);
        this.nextId += 1;

        const msg: SubMsg = .{
            .msg = "sub",
            .id = id,
            .name = topic,
            .params = params,
        };

        const msgStr = try json.stringifyAlloc(this.allocator, msg, .{});
        defer this.allocator.free(msgStr);
        try this._write(msgStr);
    }

    fn _write(this: *@This(), msg: []u8) !void {
        std.debug.print("snd {s}\n", .{msg});
        try this.client.write(msg);
    }

    pub fn serverMessage(_: *@This(), data: []u8) !void {
        std.debug.print("recvd {s}\n", .{data});
    }
};
