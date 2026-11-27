const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const c = @import("cleaner.zig");
const stale = @import("stale.zig");
const settings = @import("settings.zig");
const apps = @import("apps.zig");
const gui = @import("gui.zig");
const L = u.L;
const gpa = u.gpa;

pub fn main() void {
    u.initAppDir();
    c.initDirs();
    settings.load();

    var argc: i32 = 0;
    const argv = w.CommandLineToArgvW(w.GetCommandLineW(), &argc);
    var mode: enum { gui, auto, scan, apps, leftovers, cmds } = .gui;
    var arg2: ?[]const u16 = null;
    if (argv) |av| {
        var i: usize = 1;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            const a = std.mem.span(av[i]);
            if (u.eqlI(a, L("--auto"))) mode = .auto;
            if (u.eqlI(a, L("--scan"))) mode = .scan;
            if (u.eqlI(a, L("--apps"))) mode = .apps;
            if (u.eqlI(a, L("--uninstall-cmd"))) mode = .cmds;
            if (u.eqlI(a, L("--leftovers"))) {
                mode = .leftovers;
                if (i + 1 < @as(usize, @intCast(argc))) arg2 = std.mem.span(av[i + 1]);
            }
        }
    }
    switch (mode) {
        .gui => gui.run(),
        .auto => autoRun(),
        .scan => scanReport(),
        .apps => appsReport(),
        .leftovers => leftoversReport(arg2 orelse L("")),
        .cmds => cmdsReport(),
    }
}

// ---------------------------------------------------------------- console output (works when redirected)
var out_handle: ?w.HANDLE = null;
var out_is_console = false;

fn openOut() void {
    _ = w.AttachConsole(w.ATTACH_PARENT_PROCESS);
    out_handle = w.GetStdHandle(w.STD_OUTPUT_HANDLE);
    if (out_handle) |h| out_is_console = w.GetFileType(h) == w.FILE_TYPE_CHAR;
}

fn print(comptime f: []const u8, args: anytype) void {
    const h = out_handle orelse return;
    const s = u.fmt8(f, args);
    defer gpa.free(s);
    if (out_is_console) {
        const ws = u.W(s);
        defer gpa.free(ws);
        _ = w.WriteConsoleW(h, ws.ptr, @intCast(ws.len), null, null);
    } else _ = w.WriteFile(h, s.ptr, @intCast(s.len), null, null);
}

fn allTargets() []c.Target {
    const st = c.staticTargets();
    const dyn = stale.discover(settings.stale_days);
    return std.mem.concat(gpa, c.Target, &.{ st, dyn }) catch u.oom();
}

fn scanReport() void {
    openOut();
    var total: i64 = 0;
    for (allTargets()) |*t| {
        const r = c.scan(t, settings.temp_age_days);
        if (r.bytes > 0) total += r.bytes;
        var b: [32]u8 = undefined;
        print("{s:>12}  {d:>8} file  {s:<16} {s}\r\n", .{ u.fmtSize(&b, r.bytes), r.files, t.id, u.U8(t.name) });
    }
    var b: [32]u8 = undefined;
    print("{s:>12}  TỔNG\r\n", .{u.fmtSize(&b, total)});
}

fn appsReport() void {
    openOut();
    _ = stale.discover(settings.stale_days);
    const list = apps.list();
    for (list) |a| {
        const lu = stale.lastUsedFor(a.name);
        print("{s:<50} | {s:<30} | {d:>7} MB | {s} | {s}\r\n", .{ u.U8(a.name), u.U8(a.publisher), a.size_kb / 1024, u.U8(a.date), if (lu > 0) u.fmtDate(lu) else "" });
    }
    print("{d} ứng dụng\r\n", .{list.len});
}

/// Read-only: shows what would be offered for deletion if the app were uninstalled now.
fn leftoversReport(name: []const u16) void {
    openOut();
    const list = apps.list();
    for (list) |*a| {
        if (u.findI(a.name, name) == null) continue;
        print("== {s}  (core: {s})\r\n", .{ u.U8(a.name), u.U8(apps.coreName(a.name)) });
        for (apps.findLeftovers(a, list)) |l| {
            var b: [32]u8 = undefined;
            print("  [{s}] {s:>10}  {s}  — {s}\r\n", .{ if (l.checked) "x" else " ", if (l.kind == .regkey) "" else u.fmtSize(&b, l.bytes), u.U8(l.display), u.U8(l.reason) });
        }
        return;
    }
    print("Không tìm thấy app\r\n", .{});
}

fn logLine(s: []const u8) void {
    u.log(s);
}

fn autoRun() void {
    u.log(u.fmt8("=== Tự động dọn bắt đầu (admin={}, tuổi file tạm={d} ngày)", .{ u.is_admin, settings.temp_age_days }));
    var total: i64 = 0;
    for (allTargets()) |*t| {
        const is_app = std.mem.startsWith(u8, t.id, "app:");
        const wanted = if (is_app)
            !settings.contains(settings.excluded, t.id)
        else if (settings.selected) |sel| settings.contains(sel, t.id) else t.default_on;
        if (!wanted) continue;
        if (t.needs_admin and !u.is_admin) {
            u.log(u.fmt8("  Bỏ qua (cần Admin): {s}", .{u.U8(t.name)}));
            continue;
        }
        const r = c.clean(t, settings.temp_age_days, &logLine);
        total += r.bytes;
        var b: [32]u8 = undefined;
        u.log(u.fmt8("  {s}: xóa {d} file, {s} (bỏ qua {d} file đang dùng)", .{ u.U8(t.name), r.deleted, u.fmtSize(&b, r.bytes), r.skipped }));
    }
    var b: [32]u8 = undefined;
    u.log(u.fmt8("=== Xong. Giải phóng {s}", .{u.fmtSize(&b, total)}));
}

/// Read-only: prints the (silent) uninstall command that would be used for every app.
fn cmdsReport() void {
    openOut();
    for (apps.list()) |*a| {
        const cmd = apps.uninstallCommand(a);
        print("{s:<6} {s:<45} \"{s}\" {s}\r\n", .{ if (cmd.silent) "silent" else "UI", u.U8(a.name), u.U8(cmd.file), u.U8(cmd.params) });
    }
}
