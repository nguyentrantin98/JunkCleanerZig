//! Finds apps whose AppData folders were not written for N days and exposes ONLY their cache folders.
const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const c = @import("cleaner.zig");
const L = u.L;
const gpa = u.gpa;

const cache_names = [_][]const u16{
    L("Cache"),             L("Caches"),           L("Cache_Data"), L("Code Cache"),  L("GPUCache"),         L("CachedData"),
    L("ShaderCache"),       L("GrShaderCache"),    L("DawnCache"),  L("DawnGraphiteCache"), L("DawnWebGPUCache"), L("GraphiteDawnCache"),
    L("Crashpad"),          L("CrashDumps"),       L("Crash Reports"), L("logs"),     L("log"),
};

/// Covered by fixed categories, part of Windows, or not an app folder.
const skip_names = [_][]const u16{
    L("Microsoft"), L("Google"),      L("CocCoc"),  L("BraveSoftware"), L("Mozilla"),       L("Opera Software"), L("npm-cache"),
    L("npm"),       L("Yarn"),        L("NuGet"),   L("pip"),           L("Code"),          L("Temp"),           L("Programs"),
    L("Packages"),  L("JunkCleaner"), L("CrashDumps"), L("D3DSCache"),  L("Comms"),         L("ConnectedDevicesPlatform"),
    L("PlaceholderTileLogoFolder"), L("Publishers"), L("VirtualStore"), L("Adobe"),     L("Sun"),             L("Macromedia"),
    L("Intel"),     L("NVIDIA"),      L("NVIDIA Corporation"), L("AMD"),  L("ATI"),           L("Package Cache"),
};

const package_caches = [_][]const u16{ L("AC\\INetCache"), L("AC\\Temp"), L("TempState") };
const max_cache_depth = 4;
const min_bytes: i64 = 1 << 20;

fn inList(name: []const u16, items: []const []const u16) bool {
    for (items) |x| if (u.eqlI(name, x)) return true;
    return false;
}

/// Grouping key: "PostmanAgent", "Postman-Agent", "Postman" all map to "postman".
pub fn appKey(name: []const u16) []u16 {
    const plain = u.normalize(name);
    var key: std.ArrayList(u16) = .empty;
    var i: usize = 0;
    outer: while (i < plain.len) {
        for ([_][]const u16{ L("agent"), L("desktop"), L("data") }) |word| {
            if (std.mem.startsWith(u16, plain[i..], word)) {
                i += word.len;
                continue :outer;
            }
        }
        key.append(gpa, plain[i]) catch u.oom();
        i += 1;
    }
    if (key.items.len >= 3) {
        gpa.free(plain);
        return key.toOwnedSlice(gpa) catch u.oom();
    }
    key.deinit(gpa);
    return plain;
}

/// "MSTeams_8wekyb3d8bbwe" -> "MSTeams"; "5319275A.WhatsAppDesktop_cv1g..." -> "WhatsAppDesktop".
fn packageName(pkg: []const u16) []const u16 {
    var name = pkg;
    if (std.mem.indexOfScalar(u16, name, '_')) |i| name = name[0..i];
    if (std.mem.indexOfScalar(u16, name, '.')) |dot| {
        var hex = dot > 0;
        var all_letters = true;
        for (name[0..dot]) |ch| {
            const is_hex = (ch >= '0' and ch <= '9') or (ch >= 'A' and ch <= 'F') or (ch >= 'a' and ch <= 'f');
            if (!is_hex) hex = false;
            if (!((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z'))) all_letters = false;
        }
        if (hex and !all_letters and dot + 1 < name.len) name = name[dot + 1 ..];
    }
    return name;
}

const Candidate = struct {
    key: []u16,
    display: []const u16,
    dir: [:0]u16,
    is_package: bool,
    // result
    stale: bool = false,
    newest: u64 = 0,
    caches: std.ArrayList([:0]u16) = .empty,
};

fn inspect(cand: *Candidate, cutoff: u64) void {
    if (cand.is_package) for (package_caches) |pc| {
        const path = u.join(cand.dir, pc);
        if (u.isDir(path)) cand.caches.append(gpa, path) catch u.oom() else gpa.free(path);
    };
    const Item = struct { dir: [:0]u16, depth: u32, in_cache: bool };
    var stack: std.ArrayList(Item) = .empty;
    defer {
        for (stack.items) |it| gpa.free(it.dir);
        stack.deinit(gpa);
    }
    stack.append(gpa, .{ .dir = u.dupeW(cand.dir), .depth = 0, .in_cache = false }) catch u.oom();
    var fd: w.WIN32_FIND_DATAW = undefined;
    while (stack.pop()) |it| {
        defer gpa.free(it.dir);
        if (c.cancel.load(.monotonic)) return;
        const pat = u.concat(&.{ L("\\\\?\\"), it.dir, L("\\*") });
        defer gpa.free(pat);
        const h = w.FindFirstFileExW(pat.ptr, w.FindExInfoBasic, &fd, 0, null, w.FIND_FIRST_EX_LARGE_FETCH);
        if (h == w.INVALID_HANDLE) continue;
        defer _ = w.FindClose(h);
        while (true) {
            const name = std.mem.sliceTo(&fd.cFileName, 0);
            const a = fd.dwFileAttributes;
            if (!c.isDots(name) and (a & w.FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
                if ((a & w.FILE_ATTRIBUTE_DIRECTORY) != 0) {
                    const is_cache = !it.in_cache and !cand.is_package and it.depth < max_cache_depth and inList(name, &cache_names);
                    const sub = u.join(it.dir, name);
                    if (is_cache) cand.caches.append(gpa, u.dupeW(sub)) catch u.oom();
                    stack.append(gpa, .{ .dir = sub, .depth = it.depth + 1, .in_cache = it.in_cache or is_cache }) catch u.oom();
                } else {
                    cand.newest = @max(cand.newest, c.newest(&fd));
                    if (cand.newest >= cutoff) return; // used recently -> not stale
                }
            }
            if (w.FindNextFileW(h, &fd) == 0) break;
        }
    }
    cand.stale = true;
}

const Pool = struct {
    cands: []Candidate,
    next: std.atomic.Value(usize) = .init(0),
    cutoff: u64,

    fn worker(arg: ?*anyopaque) callconv(.winapi) w.DWORD {
        const self: *Pool = @ptrCast(@alignCast(arg.?));
        while (true) {
            const i = self.next.fetchAdd(1, .monotonic);
            if (i >= self.cands.len) return 0;
            inspect(&self.cands[i], self.cutoff);
        }
    }
};

pub const App = struct { key: []const u8, display: []const u16, newest: u64 };

/// Last discovery result (keys of stale apps) so the Apps tab can show "không dùng N ngày" badges.
pub var last_apps: []App = &.{};

pub fn discover(days: u32) []c.Target {
    const cutoff = u.now() -| @as(u64, @max(days, 1)) * u.DAY;
    var cands: std.ArrayList(Candidate) = .empty;
    for ([_][]const u16{ c.dirs.local, c.dirs.roaming, c.dirs.locallow }) |base| {
        for (c.subdirs(base)) |d| {
            const n = u.baseName(d);
            if (!inList(n, &skip_names)) cands.append(gpa, .{ .key = appKey(n), .display = n, .dir = d, .is_package = false }) catch u.oom();
        }
    }
    for (c.subdirs(u.join(c.dirs.local, L("Packages")))) |d| {
        const n = packageName(u.baseName(d));
        if (u.startsWithI(n, L("Microsoft")) or u.startsWithI(n, L("Windows"))) continue;
        cands.append(gpa, .{ .key = appKey(n), .display = n, .dir = d, .is_package = true }) catch u.oom();
    }

    var pool: Pool = .{ .cands = cands.items, .cutoff = cutoff };
    var threads: [4]?w.HANDLE = .{ null, null, null, null };
    for (&threads) |*t| t.* = w.CreateThread(null, 0, &Pool.worker, &pool, 0, null);
    for (threads) |t| if (t) |h| {
        _ = w.WaitForSingleObject(h, w.INFINITE);
        _ = w.CloseHandle(h);
    };

    var out: std.ArrayList(c.Target) = .empty;
    var apps: std.ArrayList(App) = .empty;
    const done = gpa.alloc(bool, cands.items.len) catch u.oom();
    @memset(done, false);
    for (cands.items, 0..) |*first, i| {
        if (done[i]) continue;
        var all_stale = true;
        var newest_t: u64 = 0;
        var display = first.display;
        var caches: std.ArrayList([:0]u16) = .empty;
        for (cands.items[i..], i..) |*o, j| {
            if (!std.mem.eql(u16, o.key, first.key)) continue;
            done[j] = true;
            if (!o.stale) all_stale = false;
            newest_t = @max(newest_t, o.newest);
            if (o.display.len < display.len) display = o.display;
            for (o.caches.items) |cp| caches.append(gpa, cp) catch u.oom();
        }
        if (!all_stale or caches.items.len == 0 or newest_t == 0) continue;

        var probe: c.Target = .{ .id = "", .name = L(""), .note = L(""), .group = .apps, .roots = @ptrCast(caches.items) };
        if (c.scan(&probe, 0).bytes < min_bytes) continue;

        const key8 = u.U8(first.key);
        const disp8 = u.U8(display);
        const date = u.fmtDate(newest_t);
        const idle = (u.now() - newest_t) / u.DAY;
        var kinds: std.ArrayList(u8) = .empty;
        var shown: usize = 0;
        for (caches.items, 0..) |cp, k| {
            const bn = u.baseName(cp);
            var dup = false;
            for (caches.items[0..k]) |prev| if (u.eqlI(u.baseName(prev), bn)) {
                dup = true;
            };
            if (dup or shown >= 5) continue;
            if (shown > 0) kinds.appendSlice(gpa, ", ") catch u.oom();
            kinds.appendSlice(gpa, u.U8(bn)) catch u.oom();
            shown += 1;
        }
        probe.id = u.fmt8("app:{s}", .{key8});
        probe.name = u.fmtW("{s}", .{disp8});
        probe.note = u.fmtW("{d} ngày không dùng · lần cuối {s} · {s}", .{ idle, date, kinds.items });
        probe.roots = @ptrCast(caches.toOwnedSlice(gpa) catch u.oom());
        out.append(gpa, probe) catch u.oom();
        apps.append(gpa, .{ .key = key8, .display = u.dupeW(display), .newest = newest_t }) catch u.oom();
    }
    last_apps = apps.toOwnedSlice(gpa) catch u.oom();
    const items = out.toOwnedSlice(gpa) catch u.oom();
    std.mem.sort(c.Target, items, {}, struct {
        fn lt(_: void, a: c.Target, b: c.Target) bool {
            const n = @min(a.name.len, b.name.len);
            for (a.name[0..n], b.name[0..n]) |x, y| if (u.lower(x) != u.lower(y)) return u.lower(x) < u.lower(y);
            return a.name.len < b.name.len;
        }
    }.lt);
    return items;
}

/// Newest AppData write time for an installed app (used for the "lâu không dùng" badge); 0 = unknown.
pub fn lastUsedFor(name: []const u16) u64 {
    const key = appKey(name);
    defer gpa.free(key);
    const k8 = u.U8(key);
    defer gpa.free(k8);
    for (last_apps) |a| if (a.key.len >= 4 and (std.mem.startsWith(u8, k8, a.key) or std.mem.startsWith(u8, a.key, k8))) return a.newest;
    return 0;
}
