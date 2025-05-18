// Rocket-chat protocol Types
const std = @import("std");
const json = std.json;

pub const MethodMsg = struct {
    msg: []const u8,
    id: []const u8,
    method: []const u8,
    params: MethodParams,
};

const MethodParamsTg = enum {
    loginParams,
    params,
    sendMessage,
};

pub const MethodParams = union(MethodParamsTg) {
    loginParams: []const LoginMethodParams,
    params: []const []const u8,
    sendMessage: []NewMessage,

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        switch (self) {
            .loginParams => |loginParams| {
                try jws.write(loginParams);
            },
            .params => |p| {
                try jws.write(p);
            },
            .sendMessage => |p| {
                try jws.write(p);
            },
        }
    }
};

pub const LoginMethodParams = struct {
    password: []const u8,
    user: LoginMethodUser,
};

const LoginMethodUser = struct {
    username: ?[]const u8,
    //email: ?[]const u8,
};

pub const SubMsg = struct {
    msg: []const u8 = "sub",
    id: []const u8,
    name: []const u8,
    params: []const json.Value,
};

// messages from Server

pub const ServerMessage = struct {
    msg: ServerMessageMsg,
    id: ?[]u8 = null,
    result: ?json.Value = null,
};

const ServerMessageMsg = enum {
    added,
    changed,
    connected,
    ping,
    ready,
    result,
    updated,
};

const ServerMessageChanged = struct {
    msg: ServerMessageMsg,
    collection: []u8,
    id: []u8,
    fields: ServerMessageChangedFields,
};

const ServerMessageChangedFields = struct {
    eventName: []u8,
    args: Message,
};

pub const NewMessage = struct {
    rid: []u8, // room id
    msg: []u8,
    bot: ?bool = null,
};

pub const Message = struct {
    _id: []u8,
    alias: ?[]u8 = null,
    rid: []u8, // room id
    msg: []u8,
    //bot: ?{ i: []u8},
    // ts: usize, // actual format is { "$date": number }
    u: ?User = null,
    // _updatedAt: usize, // actual format is { "$date": number }
    //attachments: []Attachment
    //parseUrls: bool
    //urls: [][]u8,
    //mentions: [][]u8,
    //md: Markdown,
};

const User = struct {
    _id: []u8,
    username: []u8,
    name: []u8,
};

pub const SubscriptionChange = struct {
    collection: []u8,
    id: []u8,
    fields: struct {
        eventName: []u8,
        args: []json.Value,
    },
};
