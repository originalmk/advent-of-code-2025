const std = @import("std");
const expect = @import("std").testing.expect;
const math = @import("std").math;

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

    var rangesIter = std.mem.splitScalar(u8, lineWriter.written(), ',');
    while (rangesIter.next()) |range| {
        var rangeIter = std.mem.splitScalar(u8, range, '-');
        const rangeStartStr = rangeIter.next() orelse return error.InputDataIncorrect;
        const rangeEndStr = rangeIter.next() orelse return error.InputDataIncorrect;
        const rangeStart = try std.fmt.parseInt(u64, rangeStartStr, 10);
        const rangeEnd = try std.fmt.parseInt(u64, rangeEndStr, 10);

        std.log.debug("{d} up to {d}", .{ rangeStart, rangeEnd });
    }
}

fn generateInvalids(allocator: std.mem.Allocator, rangeStartInclusive: u64, rangeEndInclusive: u64) !std.ArrayList(u64) {
    var list: std.ArrayList(u64) = .empty;

    var currentHalf = try getStartingHalf(allocator, rangeStartInclusive);
    var currentFull = concatDupNumber(currentHalf);

    while (currentFull <= rangeEndInclusive) {
        try list.append(allocator, currentFull);

        currentHalf += 1;
        currentFull = concatDupNumber(currentHalf);
    }

    return list;
}

test "generate invalids" {
    var invalids = try generateInvalids(std.testing.allocator, 1, 75);
    defer invalids.deinit(std.testing.allocator);

    try expect(std.mem.eql(u64, invalids.items, &[_]u64{ 11, 22, 33, 44, 55, 66 }));
}

fn getStartingHalf(allocator: std.mem.Allocator, startFrom: u64) !u64 {
    const smallestEven = findSmallestDigitEven(startFrom);
    var startingHalf = try getFirstHalfOfNumber(allocator, smallestEven);
    var result = concatDupNumber(startingHalf);

    while (result < startFrom) {
        startingHalf += 1;
        result = concatDupNumber(startingHalf);
    }

    return startingHalf;
}

test "get starting half" {
    var startingHalf = try getStartingHalf(std.testing.allocator, 1);
    try expect(startingHalf == 1);

    startingHalf = try getStartingHalf(std.testing.allocator, 1234);
    try expect(startingHalf == 13);
}

fn concatDupNumber(half: u64) u64 {
    const halfDigitsCount = countDigits(half);
    var result = half;

    result = result + math.pow(u64, 10, halfDigitsCount) * result;

    return result;
}

test "concat dup number" {
    try expect(concatDupNumber(123) == 123123);
}

fn findSmallestDigitEven(startFrom: u64) u64 {
    const startFromDigitsCount = countDigits(startFrom);

    if (startFromDigitsCount % 2 != 0) {
        return math.pow(u64, 10, startFromDigitsCount);
    } else {
        return startFrom;
    }
}

test "find smallest digit even" {
    try expect(findSmallestDigitEven(1) == 10);
    try expect(findSmallestDigitEven(774) == 1000);
}

fn getFirstHalfOfNumber(allocator: std.mem.Allocator, num: u64) !u64 {
    const numDigitsCount = countDigits(num);

    if (numDigitsCount % 2 != 0) {
        return error.DigitsCountNotEven;
    }

    var currNum = num;
    var currDigitIdx: u64 = 0;
    var digits = try allocator.alloc(u64, numDigitsCount);
    defer allocator.free(digits);

    while (currDigitIdx < numDigitsCount) {
        const digit = currNum % 10;

        digits[currDigitIdx] = digit;

        currNum /= 10;
        currDigitIdx += 1;
    }

    var currHalfIdx: u64 = 0;
    var result: u64 = 0;

    while (currHalfIdx < numDigitsCount / 2) {
        const digitIdx = numDigitsCount / 2 + currHalfIdx;
        result += math.pow(u64, 10, currHalfIdx) * digits[digitIdx];
        currHalfIdx += 1;
    }

    return result;
}

test "get first half of number" {
    const half = try getFirstHalfOfNumber(std.testing.allocator, 112233);
    try expect(half == 112);
}

fn countDigits(x: u64) u64 {
    var digitCount: u32 = 0;
    var currX = x;

    while (currX != 0) {
        digitCount += 1;
        currX /= 10;
    }

    return digitCount;
}

test "digit counting" {
    try expect(countDigits(1) == 1);
    try expect(countDigits(123) == 3);
}
