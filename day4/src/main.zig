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
            const maybeElement = self.getRow(i);

            if (maybeElement) |element| {
                const pel = try std.fmt.allocPrint(self.allocator, "{d}>> {s}\n", .{ i, element });
                defer self.allocator.free(pel);
                _ = try writer.write(pel);
            } else |_| {
                _ = try writer.print("{d}>> ~empty~\n", .{i});
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

    var i: usize = 0;
    while (i < 3) {
        const line = try readLine(allocator, &stdinReader.interface);
        defer allocator.free(line);
        try cBuf.pushAlloc(line);
        i += 1;
    }

    var result: u64 = 0;
    result += try getRowMovableCount(cBuf, 0, '@', true, false);

    while (true) {
        result += try getRowMovableCount(cBuf, 1, '@', false, false);
        const line = readLine(allocator, &stdinReader.interface) catch break;
        defer allocator.free(line);
        try cBuf.pushAlloc(line);
    }

    result += try getRowMovableCount(cBuf, 2, '@', false, true);

    var stdoutWriterBuffer: [100]u8 = undefined;
    var stdoutWriter = std.fs.File.stdout().writer(&stdoutWriterBuffer);

    try stdoutWriter.interface.print("Result: {d}\n", .{result});
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

// Assumption: row length must be at least 2 chars
fn getRowMovableCount(
    cBuf: CircularWriteBuffer,
    rowIdx: usize,
    comptime adjChar: u8,
    comptime isTop: bool,
    comptime isBottom: bool,
) !u64 {
    var result: u64 = 0;
    const row = try cBuf.getRow(rowIdx);
    const rowLen = row.len;

    if (row[0] == '@') {
        const adjs = try getElemAdjacentsCount(cBuf, rowIdx, 0, adjChar, true, isTop, false, isBottom);
        if (adjs < 4) result += 1;
    }

    if (row[rowLen - 1] == '@') {
        const adjs = try getElemAdjacentsCount(cBuf, rowIdx, rowLen - 1, adjChar, false, isTop, true, isBottom);
        if (adjs < 4) result += 1;
    }

    var i: usize = 1;
    while (i < rowLen - 1) : (i += 1) {
        if (row[i] != '@') continue;

        const adjs = try getElemAdjacentsCount(cBuf, rowIdx, i, adjChar, false, isTop, false, isBottom);
        if (adjs < 4) result += 1;
    }

    return result;
}

test "get row movable count" {
    var cBuf = try CircularWriteBuffer.init(std.testing.allocator, 3);
    defer cBuf.deinit();

    try cBuf.pushAlloc(&[_]u8{ '@', '.', '.' });
    try cBuf.pushAlloc(&[_]u8{ '@', '@', '.' });
    try cBuf.pushAlloc(&[_]u8{ '@', '.', '.' });

    try expect(try getRowMovableCount(cBuf, 0, '@', true, false) == 1);
    try expect(try getRowMovableCount(cBuf, 1, '@', false, false) == 2);
}

fn getElemAdjacentsCount(
    cBuf: CircularWriteBuffer,
    rowIdx: usize,
    colIdx: usize,
    comptime adjChar: u8,
    comptime isLeft: bool,
    comptime isTop: bool,
    comptime isRight: bool,
    comptime isBottom: bool,
) !u64 {
    var result: u64 = 0;

    // Y..
    // .$.
    // ...
    if (!isLeft and !isTop) {
        const c = try cBuf.get(rowIdx - 1, colIdx - 1);
        if (c == adjChar) result += 1;
    }

    // .Y.
    // .$.
    // ...
    if (!isTop) {
        const c = try cBuf.get(rowIdx - 1, colIdx);
        if (c == adjChar) result += 1;
    }

    // ..Y
    // .$.
    // ...
    if (!isRight and !isTop) {
        const c = try cBuf.get(rowIdx - 1, colIdx + 1);
        if (c == adjChar) result += 1;
    }

    // ...
    // Y$.
    // ...
    if (!isLeft) {
        const c = try cBuf.get(rowIdx, colIdx - 1);
        if (c == adjChar) result += 1;
    }

    // ...
    // .$Y
    // ...
    if (!isRight) {
        const c = try cBuf.get(rowIdx, colIdx + 1);
        if (c == adjChar) result += 1;
    }

    // ...
    // .$.
    // Y..
    if (!isLeft and !isBottom) {
        const c = try cBuf.get(rowIdx + 1, colIdx - 1);
        if (c == adjChar) result += 1;
    }

    // ...
    // .$.
    // .Y.
    if (!isBottom) {
        const c = try cBuf.get(rowIdx + 1, colIdx);
        if (c == adjChar) result += 1;
    }

    // ...
    // .$.
    // ..Y
    if (!isRight and !isBottom) {
        const c = try cBuf.get(rowIdx + 1, colIdx + 1);
        if (c == adjChar) result += 1;
    }

    return result;
}

test "get elem adjacents count" {
    var cBuf = try CircularWriteBuffer.init(std.testing.allocator, 3);
    defer cBuf.deinit();

    try cBuf.pushAlloc(&[_]u8{ '@', '.', '.' });
    try cBuf.pushAlloc(&[_]u8{ '@', '@', '.' });
    try cBuf.pushAlloc(&[_]u8{ '@', '.', '.' });

    try expect(try getElemAdjacentsCount(cBuf, 0, 0, '@', true, true, false, false) == 2);
    try expect(try getElemAdjacentsCount(cBuf, 1, 0, '@', true, false, false, false) == 3);
    try expect(try getElemAdjacentsCount(cBuf, 1, 1, '@', false, false, false, false) == 3);
    try expect(try getElemAdjacentsCount(cBuf, 2, 0, '@', true, false, false, true) == 2);
}
