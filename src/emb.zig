const std = @import("std");
const builtin = @import("builtin");

const zigArchive = @embedFile("zig-" ++
    @tagName(builtin.cpu.arch) ++
    "-" ++
    @tagName(builtin.os.tag) ++
    "-" ++
    builtin.zig_version_string ++
    ".tar.xz");

pub fn unrollZig(allocator: std.mem.Allocator, path: []const u8) !void {
    const dir = try std.fs.cwd().makeOpenPath(path, .{});
    if (dir.access("LICENSE", .{})) {
        return;
    } else |err| {
        if (err != error.FileNotFound)
            return err;
    }

    std.log.info("Extracting zig to {s}", .{path});

    var arena_impl = std.heap.ArenaAllocator.init(allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var stream = std.io.fixedBufferStream(zigArchive);
    var decompressor = try std.compress.xz.decompress(arena, stream.reader());
    try std.tar.pipeToFileSystem(dir, decompressor.reader(), .{ .strip_components = 1 });
}
