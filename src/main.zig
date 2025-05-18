const std = @import("std");
const rocketchat = @import("rocket_chat_zig_lib");

const App = struct {
    client: rocketchat.RC,

    fn init() @This() {}
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const host = try getEnv(allocator, "RC_HOST");
    const username = try getEnv(allocator, "RC_USER");
    const password = try getEnv(allocator, "RC_PASSWORD");

    var client = try rocketchat.RC.init(allocator, .{
        .port = 443,
        .host = host,
        .tls = true,
    });
    defer client.deinit();

    try client.connect();
    try client.startLoop();

    try client.login(username, password);

    client.join();
    //    client.joinRooms();
}

fn getEnv(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| {
        std.debug.panic("env var {s} must be set", .{name});
        return err;
    };
}
