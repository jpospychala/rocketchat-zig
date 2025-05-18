const std = @import("std");
const rocketchat = @import("rocket_chat_zig_lib");

pub const std_options = std.Options{
    .log_level = .debug,
};

// Sample app that says "yes sir" to any questions asked in room "testtesttest"
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const host = try getEnv(allocator, "RC_HOST");
    const username = try getEnv(allocator, "RC_USER");
    const password = try getEnv(allocator, "RC_PASSWORD");

    var client = try rocketchat.RC.init(allocator, .{
        .port = 443, // 3000,
        .host = host,
        .tls = true,
    });
    defer client.deinit();

    try client.connect();
    try client.startLoop();

    try client.login(username, password);
    try client.subscribeToMessages();
    const roomName = "testtesttest";
    const roomId = try client.getRoomId(roomName);
    try client.joinRoom(roomId);

    while (true) {
        const message = client.messages.wait();
        const room = try client.getRoomName(message.rid);
        std.debug.print("{s} {s}: {s}\n", .{ room, message.u.?.username, message.msg });

        if (!std.mem.eql(u8, message.rid, roomId)) {
            return;
        }

        if (std.mem.indexOfScalar(u8, message.msg, '?')) |_| {
            const response = try client.allocator.dupe(u8, "yes sir");
            try client.sendToRoomId(response, roomId);
        }
    }
}

fn getEnv(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| {
        std.debug.panic("env var {s} must be set", .{name});
        return err;
    };
}
