// This file contains primitves for inter-thread communication
const std = @import("std");

// Channel allows one thread to read on messages from other thread in a blocking fasion. Messages are of type T.
// Messages are being stacked in a dynamic fifo.
pub fn Channel(T: type) type {
    return struct {
        fifo: std.fifo.LinearFifo(T, .Dynamic),
        sem: std.Thread.Semaphore,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .fifo = std.fifo.LinearFifo(T, .Dynamic).init(allocator),
                .sem = std.Thread.Semaphore{},
            };
        }

        pub fn deinit(this: *@This()) void {
            this.fifo.deinit();
        }

        pub fn wait(this: *@This()) T {
            this.sem.wait();
            return this.fifo.readItem().?;
        }

        pub fn post(this: *@This(), msg: T) !void {
            try this.fifo.writeItem(msg);
            this.sem.post();
        }
    };
}

// AwaitList allows many threads to wait on one-time results produced by other threads in a blocking fashion.
// When a thread waits on result it needs to identify expected result by id.
// When other thread posts the results it references the result by id.
pub fn AwaitList(T: type) type {
    return struct {
        list: std.StringHashMap(*Await(T)),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .list = std.StringHashMap(*Await(T)).init(allocator),
            };
        }

        pub fn deinit(this: *@This()) void {
            this.list.deinit();
        }

        pub fn wait(this: *@This(), id: []u8) !?T {
            var aw = Await(T){
                .sem = std.Thread.Semaphore{},
            };
            try this.list.put(id, &aw);
            aw.sem.wait();
            return aw.response;
        }

        pub fn post(this: *@This(), id: []u8, result: ?T) void {
            var kv = this.list.fetchRemove(id).?;
            kv.value.response = result;
            kv.value.sem.post();
        }
    };
}

fn Await(T: type) type {
    return struct {
        sem: std.Thread.Semaphore,
        response: ?T = null,
    };
}
