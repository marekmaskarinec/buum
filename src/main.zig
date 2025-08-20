const std = @import("std");
const umka = @import("umka");

const bu_um = @embedFile("bu.um");

const Target = enum(c_int) {
    default = 0,
    linux = 1,
    linux_musl = 2,
    linux_glibc = 3,
    windows = 4,
    emscripten = 5,
};

fn UmkaDynArray(comptime T: type) type {
    return extern struct {
        internal: *anyopaque,
        itemSize: i64,
        data: [*]T,

        extern fn umkaGetDynArrayLen(arr: *anyopaque) c_int;

        pub fn len(self: *@This()) usize {
            return @intCast(umkaGetDynArrayLen(@ptrCast(self)));
        }

        pub fn slice(self: *@This()) []T {
            return self.data[0..self.len()];
        }
    };
}

fn handleError(header: []const u8, inst: umka.Instance) void {
    const err = inst.getError();
    std.debug.print("{s} Error: {s}:{s}:{d}:{d}: {s}\n", .{ header, err.file_name, err.fn_name, err.line, err.pos, err.msg });
}

fn printHelpAndExit(status: u8) void {
    std.io.getStdErr().writeAll("buum - an Umka builder\n" ++
        "\t-C <dir>\t-- change root directory\n" ++
        "\t-t <targets>\t-- set build targets\n" ++
        "\t-g\t-- only generate\n" ++
        "\t-h\t-- show this help message\n") catch {};
    std.process.exit(status);
}

fn onFree(p: [*]umka.StackSlot, r: *umka.StackSlot) callconv(.C) void {
    _ = p;
    _ = r;
    std.log.warn("Free", .{});
}

var targets: std.ArrayList(Target) = undefined;

extern fn umkaMakeDynArray(self: *anyopaque, arr: *anyopaque, type: *umka.Type, size: c_int) callconv(.c) void;

fn umc__getTargets(params: [*]umka.StackSlot, result: *umka.StackSlot) callconv(.c) void {
    const typeptr: *umka.Type = params[1].ptr;
    const arr: *UmkaDynArray(Target) = @ptrCast(@alignCast(params[0].ptr));

    umkaMakeDynArray(result.ptr, @ptrCast(arr), typeptr, @intCast(targets.items.len));
    std.mem.copyForwards(Target, arr.slice(), targets.items);
}

fn runBuildUm() ![]const u8 {
    const Build = extern struct {
        outPath: [*:0]const u8,
        data: *anyopaque,
    };

    const instance = try umka.Instance.alloc();
    try instance.init("build.um", null, .{});
    errdefer handleError("Umka", instance);
    defer instance.free();
    std.debug.assert(instance.alive());

    try instance.addModule("bu.um", bu_um);

    try instance.addFunc("umc__getTargets", &umc__getTargets);

    try instance.compile();

    var build: Build = .{
        .outPath = "build.zig",
        .data = undefined,
    };

    var initFunc = try instance.getFunc("bu.um", "__init");
    var func = try instance.getFunc("build.um", "build");
    var deinitFunc = try instance.getFunc("bu.um", "__deinit");

    initFunc.setParameters(&.{.{ .ptr = &build }});
    try initFunc.call();
    var ec = initFunc.getResult().int;
    if (ec != 0) {
        std.log.err("Initializing build failed with code {d}", .{ec});
    }

    func.setParameters(&.{.{ .ptr = &build }});
    try func.call();

    deinitFunc.setParameters(&.{.{ .ptr = &build }});
    try deinitFunc.call();
    ec = deinitFunc.getResult().int;
    if (ec != 0) {
        std.log.err("Deinitializing build failed with code {d}", .{ec});
    }

    return std.mem.sliceTo(build.outPath, 0);
}

fn runBuildZig(gpa: std.mem.Allocator, path: []const u8) !u8 {
    // TODO: Make this basepath(path)/out
    try std.fs.cwd().makePath("buum/out");

    // TODO: Embedded Zig
    const args = [_][]const u8{ "zig", "build", "--build-file", path, "--prefix", "buum/out" };
    var cmd = std.process.Child.init(&args, gpa);
    const term = try std.process.Child.spawnAndWait(&cmd);
    return switch (term) {
        .Exited => |ec| ec,
        else => error{InvalidTerm}.InvalidTerm,
    };
}

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_impl.allocator();

    var genOnly = false;
    targets = std.ArrayList(Target).init(gpa);
    defer targets.deinit();

    var args = std.process.args();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-C")) {
            if (args.next()) |next| {
                std.process.changeCurDir(next) catch |err| {
                    std.log.err("Failed to change directory: {s}", .{@errorName(err)});
                    std.process.exit(1);
                };
            } else {
                std.log.err("usage: buum -C <directory>", .{});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-g")) {
            genOnly = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelpAndExit(0);
        } else if (std.mem.eql(u8, arg, "-t")) {
            if (args.next()) |next| {
                var iter = std.mem.splitScalar(u8, next, ',');
                while (iter.next()) |s| {
                    var target: ?Target = null;
                    inline for (std.meta.fields(Target)) |f| {
                        if (std.mem.eql(u8, s, f.name)) {
                            target = @enumFromInt(f.value);
                            break;
                        }
                    }

                    if (target) |t| {
                        try targets.append(t);
                    } else {
                        std.log.err("unknown target {s}, available targets: ", .{s});
                        inline for (std.meta.fields(Target)) |f| {
                            std.log.err("\t{s} (default)", .{f.name});
                        }
                        std.process.exit(1);
                    }
                }
            } else {
                std.log.err("usage: buum -t <target list>", .{});
                std.process.exit(1);
            }
        } else {
            std.log.err("invalid argument {s}", .{arg});
            printHelpAndExit(1);
        }
    }

    if (targets.items.len == 0) {
        try targets.append(.default);
    }

    const buildZigPath = try runBuildUm();

    if (genOnly) {
        std.log.info("Result saved to {s}", .{buildZigPath});
        return;
    }

    std.process.exit(try runBuildZig(gpa, buildZigPath));
}
