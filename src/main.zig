const std = @import("std");
const builtin = @import("builtin");
const umka = @import("umka");
const emb = @import("emb.zig");

const bu_um = @embedFile("bu.um");

const fatal = std.process.fatal;

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
    fatal("{s}: {s}:{s}:{d}:{d}: {s}\n", .{ header, err.file_name, err.fn_name, err.line, err.pos, err.msg });
}

fn printHelpAndExit(status: u8) void {
    std.io.getStdErr().writeAll("buum - an Umka builder\n" ++
        "\t-C <dir>\t-- change root directory\n" ++
        "\t-t <targets>\t-- set build targets\n" ++
        "\t-o <optimize>\t-- set optimization level\n" ++
        "\t-c <path>\t-- path to global cache directory\n" ++
        "\t-k\t-- keep build.zig\n" ++
        "\t-g\t-- only generate\n" ++
        "\t-h\t-- show this help message\n") catch {};
    std.process.exit(status);
}

fn onFree(p: [*]umka.StackSlot, r: *umka.StackSlot) callconv(.C) void {
    _ = p;
    _ = r;
    std.log.warn("Free", .{});
}

var g_targets: std.ArrayList(Target) = undefined;
var g_optimize_mode: std.builtin.OptimizeMode = .ReleaseSafe;

extern fn umkaMakeDynArray(self: *anyopaque, arr: *anyopaque, type: *umka.Type, size: c_int) callconv(.c) void;

fn umc__getTargets(params: [*]umka.StackSlot, result: *umka.StackSlot) callconv(.c) void {
    const typeptr: *umka.Type = params[1].ptr;
    const arr: *UmkaDynArray(Target) = @ptrCast(@alignCast(params[0].ptr));

    umkaMakeDynArray(result.ptr, @ptrCast(arr), typeptr, @intCast(g_targets.items.len));
    std.mem.copyForwards(Target, arr.slice(), g_targets.items);
}

fn getDefTarget() Target {
    return switch (builtin.target.os.tag) {
        .windows => .windows,
        .emscripten => .emscripten,
        .linux => if (builtin.target.abi.isGnu()) .linux_glibc else .linux_musl,
        else => .def,
    };
}

fn runBuildUm(gpa: std.mem.Allocator, cache_dir: []const u8) ![]const u8 {
    const Build = extern struct {
        outPath: [*:0]const u8,
        cacheDir: [*]u8,
        defTarget: Target,
        data: *anyopaque,
    };

    const instance = try umka.Instance.alloc();
    instance.init("build.um", null, .{ .impl_libs_enabled = false }) catch {
        handleError("init", instance);
    };
    defer instance.free();
    std.debug.assert(instance.alive());

    try instance.addModule("bu.um", bu_um);

    try instance.addFunc("umc__getTargets", &umc__getTargets);

    instance.compile() catch {
        handleError("compile", instance);
    };

    const cache_dirZ = try gpa.alloc(u8, cache_dir.len + 1);
    defer gpa.free(cache_dirZ);
    cache_dirZ[cache_dir.len] = 0;
    std.mem.copyForwards(u8, cache_dirZ, cache_dir);

    var build: Build = .{
        .outPath = "build.zig",
        .cacheDir = (try instance.makeStr(@ptrCast(cache_dirZ))).ptr,
        .defTarget = getDefTarget(),
        .data = undefined,
    };

    var initFunc = try instance.getFunc("bu.um", "__init");
    var func = try instance.getFunc("build.um", "build");
    var deinitFunc = try instance.getFunc("bu.um", "__deinit");

    initFunc.setParameters(&.{.{ .ptr = &build }});
    initFunc.call() catch {
        handleError("runtime", instance);
    };
    var ec = initFunc.getResult().int;
    if (ec != 0) {
        std.log.err("Initializing build failed with code {d}", .{ec});
    }

    func.setParameters(&.{.{ .ptr = &build }});
    func.call() catch {
        handleError("runtime", instance);
    };

    deinitFunc.setParameters(&.{.{ .ptr = &build }});
    deinitFunc.call() catch {
        handleError("runtime", instance);
    };
    ec = deinitFunc.getResult().int;
    if (ec != 0) {
        std.log.err("Deinitializing build failed with code {d}", .{ec});
    }

    return std.mem.sliceTo(build.outPath, 0);
}

fn runBuildZig(gpa: std.mem.Allocator, zig_bin: []const u8, path: []const u8) !u8 {
    // TODO: Make this basepath(path)/out
    try std.fs.cwd().makePath("buum/out");

    const optimize = try std.fmt.allocPrint(gpa, "-Doptimize={s}", .{@tagName(g_optimize_mode)});
    defer gpa.free(optimize);
    const args = [_][]const u8{ zig_bin, "build", "--build-file", path, "--prefix", "buum/out", "--cache-dir", "buum/cache", optimize };
    var cmd = std.process.Child.init(&args, gpa);
    const term = try std.process.Child.spawnAndWait(&cmd);
    return switch (term) {
        .Exited => |ec| ec,
        else => 127,
    };
}

fn getDefaultCacheDir(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .windows) {
        const app_data = try std.process.getEnvVarOwned(allocator, "LocalAppData");
        defer allocator.free(app_data);
        return std.fs.path.join(allocator, &.{ app_data, "buum" });
    }

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".cache", "buum" });
}

fn getZigBinPath(allocator: std.mem.Allocator, zig_path: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ zig_path, if (builtin.os.tag == .windows) "zig.exe" else "zig" });
}

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_impl.allocator();

    var gen_only = false;
    var keep_build_zig = false;
    var opt_cache_path: ?[]const u8 = null;
    g_targets = std.ArrayList(Target).init(gpa);
    defer g_targets.deinit();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-C")) {
            if (args.next()) |next| {
                std.process.changeCurDir(next) catch |err| {
                    std.log.err("Failed to change directory: {s}", .{@errorName(err)});
                    std.process.exit(1);
                };
            } else {
                fatal("usage: buum -C <directory>", .{});
            }
        } else if (std.mem.eql(u8, arg, "-g")) {
            gen_only = true;
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
                        try g_targets.append(t);
                    } else {
                        std.log.err("unknown target {s}, available targets: ", .{s});
                        inline for (std.meta.fields(Target)) |f| {
                            std.log.err("\t{s}", .{f.name});
                        }
                        std.process.exit(1);
                    }
                }
            } else {
                fatal("usage: buum -t <target list>", .{});
            }
        } else if (std.mem.eql(u8, arg, "-o")) {
            if (args.next()) |next| {
                var mode: ?std.builtin.OptimizeMode = null;
                inline for (std.meta.fields(std.builtin.OptimizeMode)) |f| {
                    if (std.mem.eql(u8, next, f.name)) {
                        mode = @enumFromInt(f.value);
                        break;
                    }
                }

                if (mode) |m| {
                    g_optimize_mode = m;
                } else {
                    std.log.err("unknown mode {s}, available modes: ", .{next});
                    inline for (std.meta.fields(std.builtin.OptimizeMode)) |f| {
                        std.log.err("\t{s}", .{f.name});
                    }
                    std.process.exit(1);
                }
            } else {
                fatal("usage: buum -t <optimization level>", .{});
            }
        } else if (std.mem.eql(u8, arg, "-c")) {
            if (args.next()) |next| {
                opt_cache_path = next;
            } else {
                fatal("usage: buum -c <path>", .{});
            }
        } else if (std.mem.eql(u8, arg, "-k")) {
            keep_build_zig = true;
        } else {
            std.log.err("invalid argument {s}", .{arg});
            printHelpAndExit(1);
        }
    }

    if (g_targets.items.len == 0) {
        try g_targets.append(.default);
    }

    const cache_dir: []const u8 = if (opt_cache_path) |p| p else try getDefaultCacheDir(gpa);
    defer if (opt_cache_path == null) gpa.free(cache_dir);
    const build_zig_path = try runBuildUm(gpa, cache_dir);

    if (gen_only) {
        std.log.info("Result saved to {s}", .{build_zig_path});
        return;
    }

    const zig_dir = try emb.unrollZig(gpa, cache_dir);
    defer gpa.free(zig_dir);
    const zig_bin_path = try getZigBinPath(gpa, zig_dir);
    defer gpa.free(zig_bin_path);
    const ec = try runBuildZig(gpa, zig_bin_path, build_zig_path);
    if (ec != 0)
        std.log.err("`zig build` failed with code {}", .{ec});

    if (!keep_build_zig)
        try std.fs.cwd().deleteFile(build_zig_path);

    std.process.exit(ec);
}
