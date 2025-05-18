# Rocket Chat Zig client

Chat library for Rocket-Chat

## Example

Sample app that says "yes sir" to any questions asked in room "testtesttest"

```zig
const rocketchat = @import("rocketchat");

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
```

## Install

Fetch
```
$ zig fetch --save git+https://github.com/jpospychala/rocket-chat-zig.git
```

Add dependency to build.zig (to exe in following example)
```
exe.root_module.addImport("rocketchat", b.dependency("rocketchat_zig", .{}).module("rocketchat"));
```

