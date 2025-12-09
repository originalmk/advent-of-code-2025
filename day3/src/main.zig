const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdinReaderBuffer: [1024]u8 = undefined;
    var stdinReader = std.fs.File.stdin().readerStreaming(&stdinReaderBuffer);
    var lineWriter = std.Io.Writer.Allocating.init(allocator);
    defer lineWriter.deinit();

    var finalSolution: u64 = 0;

    while (true) {
        _ = stdinReader.interface.streamDelimiter(&lineWriter.writer, '\n') catch break;
        const digitsStr = lineWriter.written();

        var digits = try allocator.alloc(u32, digitsStr.len);
        defer allocator.free(digits);

        var indices = try allocator.alloc(usize, digitsStr.len);
        defer allocator.free(indices);

        for (0.., digitsStr) |i, digitChar| {
            indices[i] = i;
            digits[i] = try std.fmt.parseInt(u32, &[_]u8{digitChar}, 10);
        }

        _ = try stdinReader.interface.take(1);
        lineWriter.clearRetainingCapacity();

        const indicesSlice: []usize = indices;
        const digitsSlice: []u32 = digits;

        std.mem.sort(usize, indicesSlice, digitsSlice, sortDescendingPosAware);
        const solution = try findSolution(indicesSlice);
        const solutionNum = 10 * digitsSlice[solution[0]] + digitsSlice[solution[1]];
        finalSolution += solutionNum;
    }

    std.debug.print("{d}\n", .{finalSolution});
}

fn findSolution(indices: []usize) ![2]usize {
    var i: usize = 0;

    while (i < indices.len) {
        var j: usize = 0;

        while (j < indices.len) {
            if (i != j) {
                if (indices[i] < indices[j]) {
                    return .{ indices[i], indices[j] };
                }
            }

            j += 1;
        }

        i += 1;
    }

    return error.NotFound;
}

fn sortDescendingPosAware(context: []u32, lhs: usize, rhs: usize) bool {
    if (context[lhs] == context[rhs]) {
        return lhs < rhs;
    } else {
        return context[lhs] > context[rhs];
    }
}
