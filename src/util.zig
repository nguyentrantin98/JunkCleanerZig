//! Strings (UTF-16 <-> UTF-8), paths, time, size formatting, logging, process helpers.
const std = @import("std");
const w = @import("win.zig");

pub const gpa = std.heap.smp_allocator;
/// Compile-time UTF-8 -> UTF-16 literal (raised eval quota for long Vietnamese strings).
pub inline fn L(comptime s: []const u8) *const [lenW(s):0]u16 {
    return comptime blk: {
        @setEvalBranchQuota(1_000_000);
        break :blk std.unicode.utf8ToUtf16LeStringLiteral(s);
    };
}
fn lenW(comptime s: []const u8) usize {
    @setEvalBranchQuota(1_000_000);
    return std.unicode.calcUtf16LeLen(s) catch unreachable;
}
pub const Str = [:0]const u16;

pub fn oom() noreturn {
    @panic("out of memory");
}

/// UTF-8 -> owned UTF-16 (NUL-terminated).
pub fn W(s: []const u8) [:0]u16 {
    return std.unicode.utf8ToUtf16LeAllocZ(gpa, s) catch |e| switch (e) {
        error.OutOfMemory => oom(),
        error.InvalidUtf8 => gpa.dupeSentinel(u16, L("?"), 0) catch oom(),
    };
}

/// UTF-16 -> owned UTF-8 (unpaired surrogates become '?').
pub fn U8(s: []const u16) []u8 {
    return std.unicode.utf16LeToUtf8Alloc(gpa, s) catch blk: {
        const copy = gpa.alloc(u16, s.len) catch oom();
        for (s, 0..) |c, i| copy[i] = if (c >= 0xD800 and c <= 0xDFFF) '?' else c;
        defer gpa.free(copy);
        break :blk std.unicode.utf16LeToUtf8Alloc(gpa, copy) catch oom();
    };
}

/// printf into owned UTF-16.
pub fn fmtW(comptime f: []const u8, args: anytype) [:0]u16 {
    const s = std.fmt.allocPrint(gpa, f, args) catch oom();
    defer gpa.free(s);
    return W(s);
}

pub fn fmt8(comptime f: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(gpa, f, args) catch oom();
}

pub fn concat(parts: []const []const u16) [:0]u16 {
    return std.mem.concatWithSentinel(gpa, u16, parts, 0) catch oom();
}

pub fn dupeW(s: []const u16) [:0]u16 {
    return gpa.dupeSentinel(u16, s, 0) catch oom();
}

/// a + "\" + b (b given as UTF-16).
pub fn join(a: []const u16, b: []const u16) [:0]u16 {
    if (a.len > 0 and a[a.len - 1] == '\\') return concat(&.{ a, b });
    return concat(&.{ a, L("\\"), b });
}

pub fn lower(c: u16) u16 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

pub fn eqlI(a: []const u16, b: []const u16) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (lower(x) != lower(y)) return false;
    return true;
}

pub fn startsWithI(s: []const u16, p: []const u16) bool {
    return s.len >= p.len and eqlI(s[0..p.len], p);
}

pub fn endsWithI(s: []const u16, p: []const u16) bool {
    return s.len >= p.len and eqlI(s[s.len - p.len ..], p);
}

pub fn findI(s: []const u16, p: []const u16) ?usize {
    if (p.len == 0) return 0;
    if (s.len < p.len) return null;
    var i: usize = 0;
    while (i + p.len <= s.len) : (i += 1) if (eqlI(s[i .. i + p.len], p)) return i;
    return null;
}

pub fn baseName(p: []const u16) []const u16 {
    var end = p.len;
    while (end > 0 and p[end - 1] == '\\') end -= 1;
    var i = end;
    while (i > 0 and p[i - 1] != '\\') i -= 1;
    return p[i..end];
}

pub fn parentDir(p: []const u16) []const u16 {
    var end = p.len;
    while (end > 0 and p[end - 1] == '\\') end -= 1;
    while (end > 0 and p[end - 1] != '\\') end -= 1;
    while (end > 0 and p[end - 1] == '\\') end -= 1;
    return p[0..end];
}

/// Letters/digits only, ASCII lower-cased (used for fuzzy app-name matching).
pub fn normalize(s: []const u16) []u16 {
    var out: std.ArrayList(u16) = .empty;
    for (s) |c| {
        const isAlnum = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c > 0x7F;
        if (isAlnum) out.append(gpa, lower(c)) catch oom();
    }
    return out.toOwnedSlice(gpa) catch oom();
}

pub fn env(comptime name: []const u8) [:0]u16 {
    var buf: [32768]u16 = undefined;
    const n = w.GetEnvironmentVariableW(L(name), &buf, buf.len);
    if (n == 0 or n >= buf.len) return dupeW(L(""));
    return trimSlash(buf[0..n]);
}

pub fn trimSlash(s: []const u16) [:0]u16 {
    var e = s.len;
    while (e > 3 and s[e - 1] == '\\') e -= 1;
    return dupeW(s[0..e]);
}

pub fn exePath() [:0]u16 {
    var buf: [32768]u16 = undefined;
    const n = w.GetModuleFileNameW(null, &buf, buf.len);
    return dupeW(buf[0..n]);
}

pub fn isDir(p: [:0]const u16) bool {
    const a = w.GetFileAttributesW(p.ptr);
    return a != w.INVALID_FILE_ATTRIBUTES and (a & w.FILE_ATTRIBUTE_DIRECTORY) != 0;
}

pub fn exists(p: [:0]const u16) bool {
    return w.GetFileAttributesW(p.ptr) != w.INVALID_FILE_ATTRIBUTES;
}

// ---------------------------------------------------------------- time
pub const DAY: u64 = 864_000_000_000; // FILETIME ticks per day

pub fn ft(t: w.FILETIME) u64 {
    return (@as(u64, t.hi) << 32) | t.lo;
}

pub fn now() u64 {
    var t: w.FILETIME = .{};
    w.GetSystemTimeAsFileTime(&t);
    return ft(t);
}

pub fn localTime(ticks: u64) w.SYSTEMTIME {
    const f: w.FILETIME = .{ .lo = @truncate(ticks), .hi = @truncate(ticks >> 32) };
    var utc: w.SYSTEMTIME = .{};
    var loc: w.SYSTEMTIME = .{};
    _ = w.FileTimeToSystemTime(&f, &utc);
    if (w.SystemTimeToTzSpecificLocalTime(null, &utc, &loc) == 0) return utc;
    return loc;
}

pub fn fmtDate(ticks: u64) []u8 {
    const t = localTime(ticks);
    return fmt8("{d:0>2}/{d:0>2}/{d}", .{ t.wDay, t.wMonth, t.wYear });
}

// ---------------------------------------------------------------- sizes
pub fn fmtSize(buf: []u8, bytes: i64) []const u8 {
    const b: f64 = @floatFromInt(@max(bytes, 0));
    const r = if (bytes < 0)
        std.fmt.bufPrint(buf, "?", .{})
    else if (bytes >= 1 << 30)
        std.fmt.bufPrint(buf, "{d:.2} GB", .{b / (1 << 30)})
    else if (bytes >= 1 << 20)
        std.fmt.bufPrint(buf, "{d:.1} MB", .{b / (1 << 20)})
    else if (bytes >= 1 << 10)
        std.fmt.bufPrint(buf, "{d:.0} KB", .{b / 1024})
    else
        std.fmt.bufPrint(buf, "{d} B", .{bytes});
    return r catch "?";
}

pub fn sizeW(bytes: i64) [:0]u16 {
    var buf: [32]u8 = undefined;
    return W(fmtSize(&buf, bytes));
}

// ---------------------------------------------------------------- paths of this app
pub var app_dir: [:0]u16 = undefined;
pub var log_path: [:0]u16 = undefined;
pub var is_admin: bool = false;

pub fn initAppDir() void {
    app_dir = join(env("LOCALAPPDATA"), L("JunkCleaner"));
    _ = w.CreateDirectoryW(app_dir.ptr, null);
    log_path = join(app_dir, L("clean.log"));
    is_admin = w.IsUserAnAdmin() != 0;
}

// ---------------------------------------------------------------- logging
var log_lock: w.SRWLOCK = .{};

pub fn log(line: []const u8) void {
    w.AcquireSRWLockExclusive(&log_lock);
    defer w.ReleaseSRWLockExclusive(&log_lock);
    var h = w.CreateFileW(log_path.ptr, w.FILE_APPEND_DATA, w.FILE_SHARE_READ | w.FILE_SHARE_WRITE, null, w.OPEN_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE) return;
    var size: i64 = 0;
    if (w.GetFileSizeEx(h, &size) != 0 and size > 1_000_000) {
        _ = w.CloseHandle(h);
        _ = w.DeleteFileW(log_path.ptr);
        h = w.CreateFileW(log_path.ptr, w.FILE_APPEND_DATA, w.FILE_SHARE_READ | w.FILE_SHARE_WRITE, null, w.OPEN_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
        if (h == w.INVALID_HANDLE) return;
    }
    defer _ = w.CloseHandle(h);
    var t: w.SYSTEMTIME = .{};
    w.GetLocalTime(&t);
    var buf: [64]u8 = undefined;
    const stamp = std.fmt.bufPrint(&buf, "[{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{ t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond }) catch "";
    _ = w.WriteFile(h, stamp.ptr, @intCast(stamp.len), null, null);
    _ = w.WriteFile(h, line.ptr, @intCast(line.len), null, null);
    _ = w.WriteFile(h, "\r\n", 2, null, null);
}

// ---------------------------------------------------------------- files
pub fn readFile(path: [:0]const u16) ?[]u8 {
    const h = w.CreateFileW(path.ptr, w.GENERIC_READ, w.FILE_SHARE_READ | w.FILE_SHARE_WRITE, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE) return null;
    defer _ = w.CloseHandle(h);
    var size: i64 = 0;
    if (w.GetFileSizeEx(h, &size) == 0 or size > 16 << 20) return null;
    const buf = gpa.alloc(u8, @intCast(size)) catch oom();
    var got: w.DWORD = 0;
    if (w.ReadFile(h, buf.ptr, @intCast(buf.len), &got, null) == 0) {
        gpa.free(buf);
        return null;
    }
    return buf[0..got];
}

pub fn writeFile(path: [:0]const u16, data: []const u8) bool {
    const h = w.CreateFileW(path.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE) return false;
    defer _ = w.CloseHandle(h);
    return w.WriteFile(h, data.ptr, @intCast(data.len), null, null) != 0;
}

// ---------------------------------------------------------------- processes
pub const RunResult = struct { code: u32, output: [:0]u16 };

/// Runs a command line hidden and waits. When `capture`, stdout+stderr are returned (OEM code page decoded).
pub fn run(cmdline: []const u16, capture: bool) RunResult {
    const cmd = dupeW(cmdline);
    defer gpa.free(cmd);
    var si: w.STARTUPINFOW = .{};
    var pi: w.PROCESS_INFORMATION = .{};
    var rd: w.HANDLE = undefined;
    var wr: w.HANDLE = undefined;
    if (capture) {
        var sa: w.SECURITY_ATTRIBUTES = .{ .bInheritHandle = 1 };
        if (w.CreatePipe(&rd, &wr, &sa, 0) == 0) return .{ .code = 1, .output = dupeW(L("CreatePipe failed")) };
        _ = w.SetHandleInformation(rd, w.HANDLE_FLAG_INHERIT, 0);
        si.dwFlags = w.STARTF_USESTDHANDLES;
        si.hStdOutput = wr;
        si.hStdError = wr;
    }
    const ok = w.CreateProcessW(null, cmd.ptr, null, null, @intFromBool(capture), w.CREATE_NO_WINDOW, null, null, &si, &pi);
    if (capture) _ = w.CloseHandle(wr);
    if (ok == 0) {
        if (capture) _ = w.CloseHandle(rd);
        return .{ .code = 1, .output = dupeW(L("Không chạy được lệnh")) };
    }
    var out: std.ArrayList(u8) = .empty;
    if (capture) {
        var buf: [4096]u8 = undefined;
        var got: w.DWORD = 0;
        while (w.ReadFile(rd, &buf, buf.len, &got, null) != 0 and got > 0) out.appendSlice(gpa, buf[0..got]) catch oom();
        _ = w.CloseHandle(rd);
    }
    _ = w.WaitForSingleObject(pi.hProcess.?, w.INFINITE);
    var code: w.DWORD = 1;
    _ = w.GetExitCodeProcess(pi.hProcess.?, &code);
    _ = w.CloseHandle(pi.hProcess.?);
    _ = w.CloseHandle(pi.hThread.?);
    defer out.deinit(gpa);
    return .{ .code = code, .output = oemToW(out.items) };
}

pub fn oemToW(bytes: []const u8) [:0]u16 {
    if (bytes.len == 0) return dupeW(L(""));
    const n = w.MultiByteToWideChar(w.CP_OEMCP, 0, bytes.ptr, @intCast(bytes.len), null, 0);
    const out = gpa.allocSentinel(u16, @intCast(n), 0) catch oom();
    _ = w.MultiByteToWideChar(w.CP_OEMCP, 0, bytes.ptr, @intCast(bytes.len), out.ptr, n);
    return out;
}

pub fn systemDriveRoot() [:0]u16 {
    const win = env("SystemRoot");
    if (win.len >= 2) return concat(&.{ win[0..2], L("\\") });
    return dupeW(L("C:\\"));
}
