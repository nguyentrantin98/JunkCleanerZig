//! settings.ini in %LOCALAPPDATA%\JunkCleaner (simple key=value, UTF-8).
const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const L = u.L;
const gpa = u.gpa;

pub const Schedule = enum { off, daily, weekly, logon };

pub var temp_age_days: u32 = 2;
pub var stale_days: u32 = 30;
pub var schedule: Schedule = .off;
pub var hour: u32 = 12;
pub var minute: u32 = 0;
/// Comma-separated ids; null = first run (use defaults).
pub var selected: ?[]u8 = null;
/// Stale-app ids the user unticked.
pub var excluded: []u8 = &.{};

fn path() [:0]u16 {
    return u.join(u.app_dir, L("settings.ini"));
}

pub fn load() void {
    const pth = path();
    defer gpa.free(pth);
    const data = u.readFile(pth) orelse return;
    var it = std.mem.tokenizeAny(u8, data, "\r\n");
    while (it.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const k = std.mem.trim(u8, line[0..eq], " ");
        const v = std.mem.trim(u8, line[eq + 1 ..], " ");
        if (std.mem.eql(u8, k, "TempAgeDays")) temp_age_days = std.fmt.parseInt(u32, v, 10) catch 2;
        if (std.mem.eql(u8, k, "StaleAppDays")) stale_days = std.fmt.parseInt(u32, v, 10) catch 30;
        if (std.mem.eql(u8, k, "Schedule")) schedule = std.meta.stringToEnum(Schedule, v) orelse .off;
        if (std.mem.eql(u8, k, "Time")) {
            if (std.mem.indexOfScalar(u8, v, ':')) |c| {
                hour = std.fmt.parseInt(u32, v[0..c], 10) catch 12;
                minute = std.fmt.parseInt(u32, v[c + 1 ..], 10) catch 0;
            }
        }
        if (std.mem.eql(u8, k, "Selected")) selected = gpa.dupe(u8, v) catch u.oom();
        if (std.mem.eql(u8, k, "ExcludedApps")) excluded = gpa.dupe(u8, v) catch u.oom();
    }
    temp_age_days = @min(temp_age_days, 365);
    stale_days = std.math.clamp(stale_days, 7, 3650);
    hour = @min(hour, 23);
    minute = @min(minute, 59);
}

pub fn save() void {
    const pth = path();
    defer gpa.free(pth);
    const text = u.fmt8(
        "TempAgeDays={d}\r\nStaleAppDays={d}\r\nSchedule={s}\r\nTime={d:0>2}:{d:0>2}\r\nSelected={s}\r\nExcludedApps={s}\r\n",
        .{ temp_age_days, stale_days, @tagName(schedule), hour, minute, selected orelse "", excluded },
    );
    defer gpa.free(text);
    _ = u.writeFile(pth, text);
}

pub fn contains(csv: []const u8, id: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, csv, ',');
    while (it.next()) |x| if (std.mem.eql(u8, x, id)) return true;
    return false;
}
