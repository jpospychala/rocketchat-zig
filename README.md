## Rocket Chat Zig client

Usage

```zig
const rocketchat = @import("rocket_chat_zig_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var client = try rocketchat.RC.init(allocator, .{
        .port = 443,
        .host = "chat.example.com",
        .tls = true,
    });
    defer client.deinit();

    try client.connect();
    try client.startLoop();

    try client.login("joe", "password");

    client.join();
    //    client.joinRooms();
}
```
