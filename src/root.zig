const std = @import("std");
const testing = std.testing;
const json = std.json;
const websocket = @import("websocket");

const comm = @import("./comm.zig");
pub const proto = @import("./proto.zig");

pub const RC = struct {
    host: []const u8,
    client: websocket.Client,
    allocator: std.mem.Allocator,
    nextId: usize = 1,
    thread: ?std.Thread = null,
    awaitList: comm.AwaitList(json.Value),
    messages: comm.Channel(proto.Message),

    pub fn init(allocator: std.mem.Allocator, config: websocket.Client.Config) !@This() {
        return @This(){
            .host = config.host,
            .client = try websocket.Client.init(allocator, config),
            .allocator = allocator,
            .awaitList = comm.AwaitList(json.Value).init(allocator),
            .messages = comm.Channel(proto.Message).init(allocator),
        };
    }

    pub fn deinit(this: *@This()) void {
        this.client.deinit();
        this.messages.deinit();
        this.awaitList.deinit();
    }

    pub fn connect(this: *@This()) !void {
        const request_path = "/websocket";
        const headers = try std.fmt.allocPrint(this.allocator, "Host: {s}", .{
            this.host,
        });
        defer this.allocator.free(headers);

        try this.client.handshake(request_path, .{
            .timeout_ms = 1000,
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
    }

    pub fn join(this: *@This()) void {
        this.thread.?.join();
    }

    pub fn login(this: *@This(), username: []const u8, password: []const u8) !void {
        _ = try this.ddl_method("login", proto.MethodParams{
            .loginParams = &[_]proto.LoginMethodParams{
                proto.LoginMethodParams{
                    .password = password,
                    .user = .{ .username = username },
                },
            },
        });

        try this.ddl_sub("meteor.loginServiceConfiguration", &[_]json.Value{});
    }

    pub fn subscribeToMessages(this: *@This()) !void {
        try this.ddl_sub("stream-room-messages", &[_]json.Value{
            json.Value{ .string = "__my_messages__" },
            json.Value{ .bool = true },
        });
    }

    pub fn joinRoom(this: *@This(), roomId: []const u8) !void {
        _ = try this.ddl_method("joinRoom", proto.MethodParams{
            .params = &[_][]const u8{roomId},
        });
    }

    pub fn getRoomId(this: *@This(), roomName: []const u8) ![]u8 {
        const result = try this.ddl_method("getRoomIdByNameOrId", proto.MethodParams{
            .params = &[_][]const u8{roomName},
        });

        return this.allocator.dupe(u8, result.?.string);
    }

    pub fn getRoomName(this: *@This(), roomId: []const u8) ![]u8 {
        const result = try this.ddl_method("getRoomNameById", proto.MethodParams{
            .params = &[_][]const u8{roomId},
        });

        return this.allocator.dupe(u8, result.?.string);
    }

    pub fn sendToRoomId(this: *@This(), message: []u8, roomId: []u8) !void {
        const id = try std.fmt.allocPrint(this.allocator, "{d}", .{this.nextId});
        defer this.allocator.free(id);
        this.nextId += 1;

        var params = try this.allocator.alloc(proto.NewMessage, 1);
        params[0] = proto.NewMessage{
            .rid = roomId,
            .msg = message,
            //.bot = .{
            //   .i = try this.allocator.dupe(u8, "123"),
            //},
        };
        _ = try this.ddl_method("sendMessage", proto.MethodParams{
            .sendMessage = params,
        });
    }

    pub fn ddl_method(this: *@This(), method: []const u8, params: proto.MethodParams) !?json.Value {
        const id = try std.fmt.allocPrint(this.allocator, "{d}", .{this.nextId});
        defer this.allocator.free(id);
        this.nextId += 1;

        const msg: proto.MethodMsg = .{
            .msg = "method",
            .id = id,
            .method = method,
            .params = params,
        };

        const msgStr = try json.stringifyAlloc(this.allocator, msg, .{
            .emit_null_optional_fields = false,
        });
        defer this.allocator.free(msgStr);
        try this._write(msgStr);

        return try this.awaitList.wait(id);
    }

    pub fn ddl_sub(this: *@This(), topic: []const u8, params: []const json.Value) !void {
        const id = try std.fmt.allocPrint(this.allocator, "{d}", .{this.nextId});
        defer this.allocator.free(id);
        this.nextId += 1;

        const msg: proto.SubMsg = .{
            .id = id,
            .name = topic,
            .params = params,
        };

        const msgStr = try json.stringifyAlloc(this.allocator, msg, .{});
        defer this.allocator.free(msgStr);
        try this._write(msgStr);
    }

    fn _write(this: *@This(), msg: []u8) !void {
        std.log.debug("send {s}", .{msg});
        try this.client.write(msg);
    }

    pub fn serverMessage(this: *@This(), data: []u8) !void {
        std.log.debug("recv {s}", .{data});
        const parsed = json.parseFromSlice(json.Value, this.allocator, data, .{}) catch |ex| {
            std.log.warn("Error parsing serverMessage: {any}", .{ex});
            return;
        };
        const msg = try json.parseFromValue(proto.ServerMessage, this.allocator, parsed.value, .{
            .ignore_unknown_fields = true,
        });

        switch (msg.value.msg) {
            .ping => {
                const pong = try this.allocator.dupe(u8, "{\"msg\": \"pong\"}");
                defer this.allocator.free(pong);
                try this._write(pong);
            },

            .result => { // method result
                this.awaitList.post(msg.value.id.?, msg.value.result);
            },

            .changed => {
                const change = json.parseFromValue(proto.SubscriptionChange, this.allocator, parsed.value, .{
                    .ignore_unknown_fields = true,
                }) catch |ex| {
                    std.log.warn("Error parsing subscription: {any}", .{ex});
                    return;
                };

                if (std.mem.eql(u8, change.value.collection, "stream-room-messages") and std.mem.eql(u8, change.value.fields.eventName, "__my_messages__")) {
                    const message = json.parseFromValue(proto.Message, this.allocator, change.value.fields.args[0], .{
                        .ignore_unknown_fields = true,
                    }) catch |ex| {
                        std.log.warn("Error parsing subscription message: {any}", .{ex});
                        return;
                    };
                    try this.messages.post(message.value);
                }
            },

            else => {},
        }
    }
};
