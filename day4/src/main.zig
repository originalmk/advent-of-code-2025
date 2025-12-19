const std = @import("std");
const expect = @import("std").testing.expect;

const CircularWriteBuffer = struct {
    allocator: std.mem.Allocator,
    writePtr: usize,
    cap: u32,
    buf: []?[]u8,

    pub fn init(allocator: std.mem.Allocator, cap: u32) !CircularWriteBuffer {
        const buf = try allocator.alloc(?[]u8, cap);

        for (0..buf.len) |idx| {
            buf[idx] = null;
        }

        return CircularWriteBuffer{
            .allocator = allocator,
            .writePtr = 0,
            .cap = cap,
            .buf = buf,
        };
    }

    pub fn pushAlloc(self: *CircularWriteBuffer, element: []const u8) !void {
        const nextWritePtr = (self.writePtr + 1) % self.cap;

        if (self.buf[nextWritePtr] != null) {
            self.allocator.free(self.buf[nextWritePtr].?);
        }

        const elementDupe = try self.allocator.dupe(u8, element);
        self.buf[nextWritePtr] = elementDupe;
        self.writePtr = nextWritePtr;
    }

    // NOTE: Assumes that user provides idx < self.cap
    pub fn getRow(self: CircularWriteBuffer, idx: usize) ![]u8 {
        const eIdx: usize = subMod(self.writePtr, self.cap - idx - 1, self.cap);
        const element = self.buf[eIdx];

        if (element == null) {
            return error.DoesNotExist;
        }

        return element.?;
    }

    pub fn get(self: CircularWriteBuffer, rowIdx: usize, colIdx: usize) !u8 {
        const row = try self.getRow(rowIdx);
        const elem = row[colIdx];

        return elem;
    }

    pub fn print(self: CircularWriteBuffer, writer: *std.Io.Writer) !void {
        const p = try std.fmt.allocPrint(self.allocator, "Circular Buffer [{}]\n", .{self.cap});
        defer self.allocator.free(p);
        _ = try writer.write(p);

        for (0..self.cap) |i| {
            const element = try self.getRow(i);

            if (element == null) {
                var pBuf: [200]u8 = undefined;
                _ = try std.fmt.bufPrint(&pBuf, "{d}>> ~empty~", .{i});
            } else {
                const pel = try std.fmt.allocPrint(self.allocator, "{d}>> {s}\n", .{ i, element.? });
                defer self.allocator.free(pel);
                _ = try writer.write(pel);
            }
        }
    }

    pub fn deinit(self: CircularWriteBuffer) void {
        for (self.buf) |element| {
            if (element != null) {
                self.allocator.free(element.?);
            }
        }

        self.allocator.free(self.buf);
    }
};

test "circular write buffer" {
    var cBuf: CircularWriteBuffer = try CircularWriteBuffer.init(std.testing.allocator, 3);
    defer cBuf.deinit();

    try cBuf.pushAlloc(&[_]u8{ 'a', 'b', 'c' });
    try cBuf.pushAlloc(&[_]u8{ 'd', 'e', 'f' });
    try cBuf.pushAlloc(&[_]u8{ 'g', 'h', 'i' });

    try expect(try cBuf.get(0, 0) == 'a');
    try expect(try cBuf.get(0, 1) == 'b');
    try expect(try cBuf.get(0, 2) == 'c');
    try expect(try cBuf.get(1, 0) == 'd');
    try expect(try cBuf.get(1, 1) == 'e');
    try expect(try cBuf.get(1, 2) == 'f');
    try expect(try cBuf.get(2, 0) == 'g');
    try expect(try cBuf.get(2, 1) == 'h');
    try expect(try cBuf.get(2, 2) == 'i');

    try cBuf.pushAlloc(&[_]u8{ 'j', 'k', 'l' });

    try expect(std.mem.eql(u8, try cBuf.getRow(0), &[_]u8{ 'd', 'e', 'f' }));
    try expect(std.mem.eql(u8, try cBuf.getRow(1), &[_]u8{ 'g', 'h', 'i' }));
    try expect(std.mem.eql(u8, try cBuf.getRow(2), &[_]u8{ 'j', 'k', 'l' }));
}

fn subMod(a: usize, b: usize, mod: usize) usize {
    const aMod = a % mod;
    const bMod = b % mod;

    if (aMod >= bMod) {
        return aMod - bMod;
    } else {
        return aMod + mod - bMod;
    }
}

test "sub mod test" {
    try expect(subMod(1 + 0, 3, 3) == 1);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdinReaderBuffer: [100]u8 = undefined;
    var stdinReader = std.fs.File.stdin().reader(&stdinReaderBuffer);

    var cBuf = try CircularWriteBuffer.init(allocator, 3);
    defer cBuf.deinit();

    while (true) {
        const line = readLine(allocator, &stdinReader.interface) catch break;
        defer allocator.free(line);

        try cBuf.pushAlloc(line);
    }

    var stdoutWriterBuffer: [100]u8 = undefined;
    var stdoutWriter = std.fs.File.stdout().writer(&stdoutWriterBuffer);

    try cBuf.print(&stdoutWriter.interface);
    try stdoutWriter.interface.flush();
}

fn readLine(allocator: std.mem.Allocator, stdinReader: *std.Io.Reader) ![]u8 {
    var lineWriter = std.Io.Writer.Allocating.init(allocator);
    defer lineWriter.deinit();
    _ = try stdinReader.streamDelimiter(&lineWriter.writer, '\n');
    const line = try allocator.dupe(u8, lineWriter.written());
    lineWriter.clearRetainingCapacity();
    stdinReader.toss(1);

    return line;
}
