//! Clean categories, scanning and deletion. Never follows junctions/symlinks.
const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const L = u.L;
const gpa = u.gpa;
const Str = u.Str;

pub const Kind = enum { files, recycle, dism };
pub const Group = enum(u8) { system, browser, dev, apps };
pub const group_titles = [_]Str{ L("Hệ thống"), L("Trình duyệt"), L("Lập trình"), L("Ứng dụng lâu không dùng · chỉ xóa cache") };

pub const Target = struct {
    id: []const u8,
    name: Str,
    note: Str,
    group: Group,
    needs_admin: bool = false,
    default_on: bool = false,
    kind: Kind = .files,
    /// Only delete files older than N days and prune empty folders.
    age_filter: bool = false,
    roots: []const Str = &.{},
    name_filter: ?*const fn ([]const u16) bool = null,
    // runtime
    checked: bool = false,
    bytes: i64 = -2, // -2 not scanned yet, -1 unknown
    busy_text: ?Str = null,
};

pub const Dirs = struct {
    local: Str, roaming: Str, locallow: Str, home: Str, win: Str, progdata: Str, temp: Str,
    progfiles: Str, progfiles86: Str,
};
pub var dirs: Dirs = undefined;

pub fn initDirs() void {
    var tbuf: [1024]u16 = undefined;
    const tn = w.GetTempPathW(tbuf.len, &tbuf);
    const local = u.env("LOCALAPPDATA");
    dirs = .{
        .local = local,
        .roaming = u.env("APPDATA"),
        .locallow = u.join(u.parentDir(local), L("LocalLow")),
        .home = u.env("USERPROFILE"),
        .win = u.env("SystemRoot"),
        .progdata = u.env("ProgramData"),
        .temp = u.trimSlash(tbuf[0..tn]),
        .progfiles = u.env("ProgramFiles"),
        .progfiles86 = u.env("ProgramFiles(x86)"),
    };
}

fn p(a: Str, comptime b: []const u8) Str {
    return u.join(a, L(b));
}

fn list(items: []const Str) []const Str {
    return gpa.dupe(Str, items) catch u.oom();
}

fn thumbFilter(n: []const u16) bool {
    return u.endsWithI(n, L(".db")) and (u.startsWithI(n, L("thumbcache_")) or u.startsWithI(n, L("iconcache_")));
}

pub fn staticTargets() []Target {
    const d = dirs;
    var t: std.ArrayList(Target) = .empty;
    const add = struct {
        fn f(l: *std.ArrayList(Target), x: Target) void {
            l.append(gpa, x) catch u.oom();
        }
    }.f;
    add(&t, .{ .id = "user_temp", .group = .system, .name = L("File tạm người dùng (%TEMP%)"), .note = L("Chỉ xóa file cũ hơn N ngày"), .default_on = true, .age_filter = true, .roots = list(&.{d.temp}) });
    add(&t, .{ .id = "win_temp", .group = .system, .name = L("File tạm Windows"), .note = L("Windows\\Temp · cũ hơn N ngày"), .needs_admin = true, .default_on = true, .age_filter = true, .roots = list(&.{p(d.win, "Temp")}) });
    add(&t, .{ .id = "wu_cache", .group = .system, .name = L("Bộ đệm Windows Update"), .note = L("Bản cập nhật đã tải về · cũ hơn N ngày"), .needs_admin = true, .default_on = true, .age_filter = true, .roots = list(&.{p(d.win, "SoftwareDistribution\\Download")}) });
    add(&t, .{ .id = "delivery_opt", .group = .system, .name = L("Bộ đệm Delivery Optimization"), .note = L("Cache chia sẻ bản cập nhật"), .needs_admin = true, .default_on = true, .roots = list(&.{p(d.win, "ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization\\Cache")}) });
    add(&t, .{ .id = "user_crash", .group = .system, .name = L("Báo cáo lỗi & crash dump"), .note = L("CrashDumps, WER của người dùng"), .default_on = true, .roots = list(&.{ p(d.local, "CrashDumps"), p(d.local, "Microsoft\\Windows\\WER") }) });
    add(&t, .{ .id = "sys_crash", .group = .system, .name = L("Báo cáo lỗi & dump hệ thống"), .note = L("WER, Minidump, LiveKernelReports, MEMORY.DMP"), .needs_admin = true, .default_on = true, .roots = list(&.{ p(d.progdata, "Microsoft\\Windows\\WER\\ReportArchive"), p(d.progdata, "Microsoft\\Windows\\WER\\ReportQueue"), p(d.progdata, "Microsoft\\Windows\\WER\\Temp"), p(d.win, "Minidump"), p(d.win, "LiveKernelReports"), p(d.win, "MEMORY.DMP") }) });
    add(&t, .{ .id = "win_logs", .group = .system, .name = L("Log hệ thống cũ"), .note = L("Windows\\Logs · cũ hơn N ngày"), .needs_admin = true, .default_on = true, .age_filter = true, .roots = list(&.{p(d.win, "Logs")}) });
    add(&t, .{ .id = "thumbcache", .group = .system, .name = L("Bộ đệm ảnh thu nhỏ"), .note = L("Windows tự tạo lại"), .default_on = true, .roots = list(&.{p(d.local, "Microsoft\\Windows\\Explorer")}), .name_filter = &thumbFilter });
    add(&t, .{ .id = "recycle", .group = .system, .name = L("Thùng rác"), .note = L("Không khôi phục được sau khi xóa"), .kind = .recycle });
    add(&t, .{ .id = "dism", .group = .system, .name = L("Dọn WinSxS (DISM)"), .note = L("Chậm 5–20 phút · gỡ bản cập nhật cũ đã bị thay thế"), .needs_admin = true, .kind = .dism });
    add(&t, .{ .id = "browser_cache", .group = .browser, .name = L("Cache trình duyệt"), .note = L("Chrome, Edge, Cốc Cốc, Brave, Opera, Firefox · không xóa mật khẩu/lịch sử/cookie"), .default_on = true, .roots = browserCaches() });
    add(&t, .{ .id = "npm_cache", .group = .dev, .name = L("npm cache"), .note = L("Tải lại khi npm install"), .default_on = true, .roots = list(&.{p(d.local, "npm-cache")}) });
    add(&t, .{ .id = "yarn_cache", .group = .dev, .name = L("Yarn cache"), .note = L("Tải lại khi yarn install"), .default_on = true, .roots = list(&.{p(d.local, "Yarn\\Cache")}) });
    add(&t, .{ .id = "nuget_http", .group = .dev, .name = L("NuGet HTTP cache"), .note = L("v3-cache, plugins-cache"), .default_on = true, .roots = list(&.{ p(d.local, "NuGet\\v3-cache"), p(d.local, "NuGet\\plugins-cache") }) });
    add(&t, .{ .id = "pip_cache", .group = .dev, .name = L("pip cache"), .note = L("Python"), .default_on = true, .roots = list(&.{p(d.local, "pip\\cache")}) });
    add(&t, .{ .id = "vscode_cache", .group = .dev, .name = L("Cache VS Code"), .note = L("Cache, CachedData, CachedExtensionVSIXs, logs"), .default_on = true, .roots = list(&.{ p(d.roaming, "Code\\Cache"), p(d.roaming, "Code\\CachedData"), p(d.roaming, "Code\\Code Cache"), p(d.roaming, "Code\\GPUCache"), p(d.roaming, "Code\\CachedExtensionVSIXs"), p(d.roaming, "Code\\logs") }) });
    add(&t, .{ .id = "nuget_pkgs", .group = .dev, .name = L("NuGet packages (~/.nuget/packages)"), .note = L("Lớn · lần build .NET sau sẽ tải lại"), .roots = list(&.{p(d.home, ".nuget\\packages")}) });
    add(&t, .{ .id = "gradle_cache", .group = .dev, .name = L("Gradle caches"), .note = L("Lần build Android sau sẽ tải lại"), .roots = list(&.{p(d.home, ".gradle\\caches")}) });
    return t.toOwnedSlice(gpa) catch u.oom();
}

pub fn subdirs(dir: []const u16) [][:0]u16 {
    var out: std.ArrayList([:0]u16) = .empty;
    const pat = u.concat(&.{ L("\\\\?\\"), dir, L("\\*") });
    defer gpa.free(pat);
    var fd: w.WIN32_FIND_DATAW = undefined;
    const h = w.FindFirstFileExW(pat.ptr, w.FindExInfoBasic, &fd, 0, null, w.FIND_FIRST_EX_LARGE_FETCH);
    if (h == w.INVALID_HANDLE) return out.toOwnedSlice(gpa) catch u.oom();
    defer _ = w.FindClose(h);
    while (true) {
        const name = std.mem.sliceTo(&fd.cFileName, 0);
        const is_dir = (fd.dwFileAttributes & w.FILE_ATTRIBUTE_DIRECTORY) != 0;
        const reparse = (fd.dwFileAttributes & w.FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        if (is_dir and !reparse and !isDots(name)) out.append(gpa, u.join(dir, name)) catch u.oom();
        if (w.FindNextFileW(h, &fd) == 0) break;
    }
    return out.toOwnedSlice(gpa) catch u.oom();
}

fn browserCaches() []const Str {
    const d = dirs;
    var out: std.ArrayList(Str) = .empty;
    const per_profile = [_][]const u16{ L("Cache"), L("Code Cache"), L("GPUCache"), L("DawnGraphiteCache"), L("DawnWebGPUCache") };
    const top_level = [_][]const u16{ L("GrShaderCache"), L("ShaderCache"), L("GraphiteDawnCache") };
    const roots = [_]Str{ p(d.local, "Google\\Chrome\\User Data"), p(d.local, "Microsoft\\Edge\\User Data"), p(d.local, "CocCoc\\Browser\\User Data"), p(d.local, "BraveSoftware\\Brave-Browser\\User Data") };
    for (roots) |root| {
        if (!u.isDir(root)) continue;
        for (top_level) |t| out.append(gpa, u.join(root, t)) catch u.oom();
        for (subdirs(root)) |prof| {
            const n = u.baseName(prof);
            if (std.mem.eql(u16, n, L("Default")) or std.mem.eql(u16, n, L("Guest Profile")) or std.mem.startsWith(u16, n, L("Profile ")))
                for (per_profile) |c| out.append(gpa, u.join(prof, c)) catch u.oom();
        }
    }
    for ([_]Str{ p(d.local, "Opera Software\\Opera Stable"), p(d.local, "Opera Software\\Opera GX Stable") }) |op|
        for (per_profile) |c| out.append(gpa, u.join(op, c)) catch u.oom();
    for (subdirs(p(d.local, "Mozilla\\Firefox\\Profiles"))) |prof| out.append(gpa, u.join(prof, L("cache2"))) catch u.oom();
    return out.toOwnedSlice(gpa) catch u.oom();
}

// ---------------------------------------------------------------- walking

pub var cancel = std.atomic.Value(bool).init(false);

pub fn isDots(n: []const u16) bool {
    return (n.len == 1 and n[0] == '.') or (n.len == 2 and n[0] == '.' and n[1] == '.');
}

pub fn newest(fd: *const w.WIN32_FIND_DATAW) u64 {
    return @max(u.ft(fd.ftLastWriteTime), u.ft(fd.ftCreationTime));
}

pub fn fileSize(fd: *const w.WIN32_FIND_DATAW) i64 {
    return @intCast((@as(u64, fd.nFileSizeHigh) << 32) | fd.nFileSizeLow);
}

/// Visits every file under `root` (or `root` itself if it is a file).
/// ctx.file(dir, fd) is called with the containing directory.
pub fn walk(root: []const u16, ctx: anytype) void {
    var fd: w.WIN32_FIND_DATAW = undefined;
    const rootz = u.concat(&.{ L("\\\\?\\"), root });
    defer gpa.free(rootz);
    const attrs = w.GetFileAttributesW(rootz.ptr);
    if (attrs == w.INVALID_FILE_ATTRIBUTES or (attrs & w.FILE_ATTRIBUTE_REPARSE_POINT) != 0) return;
    if ((attrs & w.FILE_ATTRIBUTE_DIRECTORY) == 0) {
        const h = w.FindFirstFileExW(rootz.ptr, w.FindExInfoBasic, &fd, 0, null, 0);
        if (h == w.INVALID_HANDLE) return;
        _ = w.FindClose(h);
        ctx.file(u.parentDir(root), &fd);
        return;
    }
    var stack: std.ArrayList([:0]u16) = .empty;
    defer stack.deinit(gpa);
    stack.append(gpa, u.dupeW(root)) catch u.oom();
    while (stack.pop()) |dir| {
        defer gpa.free(dir);
        if (cancel.load(.monotonic)) {
            for (stack.items) |x| gpa.free(x);
            return;
        }
        const pat = u.concat(&.{ L("\\\\?\\"), dir, L("\\*") });
        defer gpa.free(pat);
        const h = w.FindFirstFileExW(pat.ptr, w.FindExInfoBasic, &fd, 0, null, w.FIND_FIRST_EX_LARGE_FETCH);
        if (h == w.INVALID_HANDLE) continue;
        defer _ = w.FindClose(h);
        while (true) {
            const name = std.mem.sliceTo(&fd.cFileName, 0);
            if (!isDots(name) and (fd.dwFileAttributes & w.FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
                if ((fd.dwFileAttributes & w.FILE_ATTRIBUTE_DIRECTORY) != 0)
                    stack.append(gpa, u.join(dir, name)) catch u.oom()
                else
                    ctx.file(dir, &fd);
            }
            if (w.FindNextFileW(h, &fd) == 0) break;
        }
    }
}

fn cutoffFor(t: *const Target, age_days: u32) u64 {
    return if (t.age_filter) u.now() -| @as(u64, age_days) * u.DAY else std.math.maxInt(u64);
}

fn matches(t: *const Target, fd: *const w.WIN32_FIND_DATAW, cutoff: u64) bool {
    if (t.name_filter) |f| if (!f(std.mem.sliceTo(&fd.cFileName, 0))) return false;
    return cutoff == std.math.maxInt(u64) or newest(fd) < cutoff;
}

pub const ScanResult = struct { bytes: i64 = 0, files: u64 = 0 };

pub fn scan(t: *const Target, age_days: u32) ScanResult {
    switch (t.kind) {
        .recycle => {
            var info: w.SHQUERYRBINFO = .{};
            if (w.SHQueryRecycleBinW(null, &info) != 0) return .{};
            return .{ .bytes = info.i64Size, .files = @intCast(@max(info.i64NumItems, 0)) };
        },
        .dism => return .{ .bytes = -1 },
        .files => {},
    }
    const Ctx = struct {
        t: *const Target,
        cutoff: u64,
        r: ScanResult = .{},
        pub fn file(self: *@This(), _: []const u16, fd: *const w.WIN32_FIND_DATAW) void {
            if (!matches(self.t, fd, self.cutoff)) return;
            self.r.bytes += fileSize(fd);
            self.r.files += 1;
        }
    };
    var ctx: Ctx = .{ .t = t, .cutoff = cutoffFor(t, age_days) };
    for (t.roots) |root| walk(root, &ctx);
    return ctx.r;
}

pub const CleanResult = struct { bytes: i64 = 0, deleted: u64 = 0, skipped: u64 = 0 };

pub fn clean(t: *const Target, age_days: u32, logf: *const fn ([]const u8) void) CleanResult {
    switch (t.kind) {
        .recycle => {
            const before = scan(t, age_days);
            const hr = w.SHEmptyRecycleBinW(null, null, 1 | 2 | 4); // no confirm/progress/sound
            if (hr == 0 or before.files == 0) return .{ .bytes = before.bytes, .deleted = before.files };
            return .{ .skipped = before.files };
        },
        .dism => return runDism(logf),
        .files => {},
    }
    const Ctx = struct {
        t: *const Target,
        cutoff: u64,
        r: CleanResult = .{},
        pub fn file(self: *@This(), dir: []const u16, fd: *const w.WIN32_FIND_DATAW) void {
            if (!matches(self.t, fd, self.cutoff)) return;
            const full = u.concat(&.{ L("\\\\?\\"), dir, L("\\"), std.mem.sliceTo(&fd.cFileName, 0) });
            defer gpa.free(full);
            if ((fd.dwFileAttributes & w.FILE_ATTRIBUTE_READONLY) != 0) _ = w.SetFileAttributesW(full.ptr, w.FILE_ATTRIBUTE_NORMAL);
            if (w.DeleteFileW(full.ptr) != 0) {
                self.r.bytes += fileSize(fd);
                self.r.deleted += 1;
            } else self.r.skipped += 1; // in use / no permission -> leave it
        }
    };
    var ctx: Ctx = .{ .t = t, .cutoff = cutoffFor(t, age_days) };
    for (t.roots) |root| {
        walk(root, &ctx);
        if (t.age_filter) removeEmptyDirs(root, ctx.cutoff, true);
    }
    return ctx.r;
}

/// Post-order removal of empty sub-folders older than cutoff. RemoveDirectoryW fails on non-empty dirs.
fn removeEmptyDirs(dir: []const u16, cutoff: u64, is_root: bool) void {
    const Sub = struct { path: [:0]u16, created: u64 };
    var subs: std.ArrayList(Sub) = .empty;
    defer subs.deinit(gpa);
    {
        const pat = u.concat(&.{ L("\\\\?\\"), dir, L("\\*") });
        defer gpa.free(pat);
        var fd: w.WIN32_FIND_DATAW = undefined;
        const h = w.FindFirstFileExW(pat.ptr, w.FindExInfoBasic, &fd, 0, null, 0);
        if (h == w.INVALID_HANDLE) return;
        defer _ = w.FindClose(h);
        while (true) {
            const name = std.mem.sliceTo(&fd.cFileName, 0);
            const a = fd.dwFileAttributes;
            if (!isDots(name) and (a & w.FILE_ATTRIBUTE_DIRECTORY) != 0 and (a & w.FILE_ATTRIBUTE_REPARSE_POINT) == 0)
                subs.append(gpa, .{ .path = u.join(dir, name), .created = u.ft(fd.ftCreationTime) }) catch u.oom();
            if (w.FindNextFileW(h, &fd) == 0) break;
        }
    }
    for (subs.items) |s| {
        removeEmptyDirs(s.path, cutoff, false);
        if (s.created < cutoff) {
            const pz = u.concat(&.{ L("\\\\?\\"), s.path });
            _ = w.RemoveDirectoryW(pz.ptr);
            gpa.free(pz);
        }
        gpa.free(s.path);
    }
    _ = is_root;
}

fn freeSpace() u64 {
    var free: u64 = 0;
    const root = u.systemDriveRoot();
    defer gpa.free(root);
    _ = w.GetDiskFreeSpaceExW(root.ptr, &free, null, null);
    return free;
}

fn runDism(logf: *const fn ([]const u8) void) CleanResult {
    const before = freeSpace();
    logf("DISM đang chạy, có thể mất 5–20 phút…");
    const cmd = u.concat(&.{ L("\""), dirs.win, L("\\System32\\Dism.exe\" /Online /Cleanup-Image /StartComponentCleanup") });
    defer gpa.free(cmd);
    const r = u.run(cmd, false);
    gpa.free(r.output);
    const after = freeSpace();
    return .{ .bytes = @intCast(after -| before), .skipped = if (r.code == 0) 0 else 1 };
}
