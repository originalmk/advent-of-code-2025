const std = @import("std");
const day2 = @import("day2");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdinReaderBuffer: [1024]u8 = undefined;
    var stdinReader = std.fs.File.stdin().readerStreaming(&stdinReaderBuffer);
    var lineWriter = std.Io.Writer.Allocating.init(allocator);
    defer lineWriter.deinit();

    _ = try stdinReader.interface.streamDelimiter(&lineWriter.writer, '\n');
    std.debug.print("{s}\n", .{lineWriter.written()});
}
