const std = @import("std");
const builtin = @import("builtin");

const zigName =
    "zig-" ++
    @tagName(builtin.cpu.arch) ++
    "-" ++
    @tagName(builtin.os.tag) ++
    "-" ++
    builtin.zig_version_string;
const zigArchive = @embedFile(zigName ++ if (builtin.target.os.tag == .windows) ".zip" else ".tar.xz");
const umkaApiH = @embedFile("umka_api");

pub fn unrollZig(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var dir = try std.fs.cwd().makeOpenPath(path, .{});
    defer dir.close();
    if (dir.access(zigName, .{})) {
        return std.fs.path.join(allocator, &.{ path, zigName });
    } else |err| {
        if (err != error.FileNotFound)
            return err;
    }

    std.log.info("Extracting zig to {s}", .{path});

    var arena_impl = std.heap.ArenaAllocator.init(allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var stream = std.io.fixedBufferStream(zigArchive);
    if (builtin.target.os.tag == .windows) {
        // This is a workaround because dir.access doesn't seem to work on Windows properly.
        std.zip.extract(dir, stream, .{}) catch |err| {
            if (err == error.PathAlreadyExists)
                return std.fs.path.join(allocator, &.{ path, zigName });
            return err;
        };
    } else {
        var decompressor = try std.compress.xz.decompress(arena, stream.reader());
        var reader = decompressor.reader();
        // I really don't like this, but using adapters didn't work. Let's just wait until the decompressor uses new io.
        const data = try reader.readAllAlloc(arena, std.math.maxInt(usize));
        defer arena.free(data);
        var reader_new = std.Io.Reader.fixed(data);
        try std.tar.pipeToFileSystem(dir, &reader_new, .{});
    }

    const file = try dir.createFile("umka_api.h", .{});
    defer file.close();
    try file.writeAll(umkaApiH);

    return std.fs.path.join(allocator, &.{ path, zigName });
}
