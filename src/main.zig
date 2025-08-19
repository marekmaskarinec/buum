const std = @import("std");
const umka = @import("umka");

const bu_um = @embedFile("bu.um");

fn handleError(header: []const u8, inst: umka.Instance) void {
    const err = inst.getError();
    std.debug.print("{s} Error: {s}:{s}:{d}:{d}: {s}\n", .{ header, err.file_name, err.fn_name, err.line, err.pos, err.msg });
}

fn printHelpAndExit(status: u8) void {
    std.io.getStdOut().writeAll("buum - an Umka builder\n" ++ "\t-C <dir>\t-- change root directory\n" ++ "\t-h\t-- show this help message\n") catch {};
    std.process.exit(status);
}

fn onFree(p: [*]umka.StackSlot, r: *umka.StackSlot) callconv(.C) void {
    _ = p;
    _ = r;
    std.log.warn("Free", .{});
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

    try instance.compile();

    // var build: Build = .{
    //     .outPath = "buum/build.zig",
    //     .data = undefined,
    // };
    var build_mem = try instance.allocData(@sizeOf(Build), onFree);
    var build: *Build = @ptrCast(@alignCast(build_mem.ptr));
    build.outPath = "buum/build.zig";

    var initFunc = try instance.getFunc("bu.um", "__init");
    var func = try instance.getFunc("build.um", "build");
    var deinitFunc = try instance.getFunc("bu.um", "__deinit");

    initFunc.setParameters(&.{.{ .ptr = build }});
    build_mem.incRef();
    try initFunc.call();
    var ec = initFunc.getResult().int;
    if (ec != 0) {
        std.log.err("Initializing build failed with code {d}", .{ec});
    }

    func.setParameters(&.{.{ .ptr = build }});
    build_mem.incRef();
    try func.call();

    deinitFunc.setParameters(&.{.{ .ptr = build }});
    build_mem.incRef();
    try deinitFunc.call();
    ec = deinitFunc.getResult().int;
    if (ec != 0) {
        std.log.err("Deinitializing build failed with code {d}", .{ec});
    }

    return std.mem.sliceTo(build.outPath, 0);
}

pub fn main() !void {
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
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelpAndExit(0);
        } else {
            std.log.err("invalid argument {s}", .{arg});
            printHelpAndExit(1);
        }
    }

    try std.fs.cwd().makePath("buum");
    const buildZigPath = try runBuildUm();
    _ = buildZigPath;
}
