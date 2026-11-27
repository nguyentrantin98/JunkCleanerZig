//! Registers "JunkCleaner.exe --auto" with Task Scheduler (or HKCU Run for non-admin logon).
const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const s = @import("settings.zig");
const L = u.L;
const gpa = u.gpa;

const task_name = "JunkCleaner_AutoClean";
const run_key = L("Software\\Microsoft\\Windows\\CurrentVersion\\Run");

pub const Result = struct { ok: bool, msg: []const u8 };

fn schtasks(args: []const u8) u.RunResult {
    const cmd = u.fmtW("\"{s}\\System32\\schtasks.exe\" {s}", .{ u.U8(u.env("SystemRoot")), args });
    defer gpa.free(cmd);
    return u.run(cmd, true);
}

fn removeRunKey() void {
    var key: ?w.HKEY = null;
    if (w.RegOpenKeyExW(w.HKEY_CURRENT_USER, run_key, 0, w.KEY_SET_VALUE, &key) == 0) {
        _ = w.RegDeleteValueW(key.?, L(task_name));
        _ = w.RegCloseKey(key.?);
    }
}

pub fn apply() Result {
    removeRunKey();
    const exe = u.U8(u.exePath());
    defer gpa.free(exe);
    switch (s.schedule) {
        .off => {
            _ = schtasks("/Delete /TN " ++ task_name ++ " /F");
            return .{ .ok = true, .msg = "Đã tắt tự động dọn." };
        },
        .logon => if (!u.is_admin) {
            _ = schtasks("/Delete /TN " ++ task_name ++ " /F");
            var key: ?w.HKEY = null;
            if (w.RegCreateKeyExW(w.HKEY_CURRENT_USER, run_key, 0, null, 0, w.KEY_SET_VALUE, null, &key, null) != 0)
                return .{ .ok = false, .msg = "Không ghi được registry Run." };
            defer _ = w.RegCloseKey(key.?);
            const val = u.fmtW("\"{s}\" --auto", .{exe});
            defer gpa.free(val);
            _ = w.RegSetValueExW(key.?, L(task_name), 0, w.REG_SZ, @ptrCast(val.ptr), @intCast((val.len + 1) * 2));
            return .{ .ok = true, .msg = "Đã bật: tự dọn khi đăng nhập (không có quyền Admin nên bỏ qua mục hệ thống)." };
        },
        else => {},
    }
    const when = switch (s.schedule) {
        .daily => u.fmt8("/SC DAILY /ST {d:0>2}:{d:0>2}", .{ s.hour, s.minute }),
        .weekly => u.fmt8("/SC WEEKLY /D SUN /ST {d:0>2}:{d:0>2}", .{ s.hour, s.minute }),
        else => u.fmt8("/SC ONLOGON /DELAY 0005:00", .{}),
    };
    defer gpa.free(when);
    const args = u.fmt8("/Create /F /TN {s} /TR \"\\\"{s}\\\" --auto\" {s}{s}", .{ task_name, exe, when, if (u.is_admin) " /RL HIGHEST" else "" });
    defer gpa.free(args);
    const r = schtasks(args);
    if (r.code != 0) return .{ .ok = false, .msg = u.fmt8("Tạo lịch thất bại: {s}", .{std.mem.trim(u8, u.U8(r.output), " \r\n")}) };
    return .{ .ok = true, .msg = if (u.is_admin)
        "Đã tạo lịch tự động dọn (quyền cao nhất, dọn cả mục hệ thống)."
    else
        "Đã tạo lịch tự động dọn. Không có quyền Admin nên các mục cần Admin sẽ bị bỏ qua." };
}
