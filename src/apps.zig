//! Installed (user-visible) Win32 apps from the Uninstall registry keys, uninstall, and leftover detection.
const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const c = @import("cleaner.zig");
const L = u.L;
const gpa = u.gpa;
const Str = u.Str;

const uninstall_path = L("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall");

pub const Hive = enum { hklm64, hklm32, hkcu };

fn hiveKey(h: Hive) w.HKEY {
    return if (h == .hkcu) w.HKEY_CURRENT_USER else w.HKEY_LOCAL_MACHINE;
}
fn hiveView(h: Hive) w.DWORD {
    return if (h == .hklm32) w.KEY_WOW64_32KEY else w.KEY_WOW64_64KEY;
}

pub const App = struct {
    name: Str,
    publisher: Str,
    version: Str,
    location: Str,
    uninstall: Str,
    quiet: Str, // QuietUninstallString (may be empty)
    icon_path: Str,
    icon_index: i32,
    size_kb: u64,
    date: Str, // dd/mm/yyyy or ""
    hive: Hive,
    key: Str, // sub key name under Uninstall
    search: []u16, // lower-case name + publisher
    last_used: u64 = 0,
    icon: ?w.HICON = null,
    icon_tried: bool = false,
    state: State = .idle,
};

pub const State = enum(u8) { idle, queued, uninstalling, cleaning, removed, failed };

fn regStr(k: w.HKEY, sub: Str, value: []const u8) Str {
    var buf: [2048]u16 = undefined;
    var size: w.DWORD = buf.len * 2;
    const vz = u.W(value);
    defer gpa.free(vz);
    if (w.RegGetValueW(k, sub.ptr, vz.ptr, w.RRF_RT_REG_SZ, null, &buf, &size) != 0) return L("");
    const n = (size / 2) -| 1;
    return u.dupeW(std.mem.trim(u16, buf[0..n], &[_]u16{ ' ', 0 }));
}

fn regDword(k: w.HKEY, sub: Str, value: []const u8) ?u32 {
    var v: u32 = 0;
    var size: w.DWORD = 4;
    const vz = u.W(value);
    defer gpa.free(vz);
    if (w.RegGetValueW(k, sub.ptr, vz.ptr, w.RRF_RT_DWORD, null, &v, &size) != 0) return null;
    return v;
}

pub fn list() []App {
    var out: std.ArrayList(App) = .empty;
    for ([_]Hive{ .hklm64, .hklm32, .hkcu }) |hive| {
        var k: ?w.HKEY = null;
        if (w.RegOpenKeyExW(hiveKey(hive), uninstall_path, 0, w.KEY_READ | hiveView(hive), &k) != 0) continue;
        defer _ = w.RegCloseKey(k.?);
        var i: w.DWORD = 0;
        while (true) : (i += 1) {
            var name_buf: [512]u16 = undefined;
            var n: w.DWORD = name_buf.len;
            if (w.RegEnumKeyExW(k.?, i, &name_buf, &n, null, null, null, null) != 0) break;
            const sub = u.dupeW(name_buf[0..n]);
            const name = regStr(k.?, sub, "DisplayName");
            const unin = regStr(k.?, sub, "UninstallString");
            if (name.len == 0 or unin.len == 0) continue;
            if ((regDword(k.?, sub, "SystemComponent") orelse 0) == 1) continue;
            if (regStr(k.?, sub, "ParentKeyName").len > 0) continue;
            const rel = regStr(k.?, sub, "ReleaseType");
            if (u.findI(rel, L("update")) != null or u.findI(rel, L("hotfix")) != null) continue;
            const version = regStr(k.?, sub, "DisplayVersion");
            var dup = false;
            for (out.items) |a| if (u.eqlI(a.name, name) and u.eqlI(a.version, version)) {
                dup = true;
            };
            if (dup) continue;

            const publisher = regStr(k.?, sub, "Publisher");
            const raw_date = regStr(k.?, sub, "InstallDate");
            const date: Str = if (raw_date.len == 8)
                u.concat(&.{ raw_date[6..8], L("/"), raw_date[4..6], L("/"), raw_date[0..4] })
            else
                L("");
            var icon = regStr(k.?, sub, "DisplayIcon");
            var icon_index: i32 = 0;
            if (std.mem.lastIndexOfScalar(u16, icon, ',')) |comma| {
                const idx8 = u.U8(icon[comma + 1 ..]);
                icon_index = std.fmt.parseInt(i32, std.mem.trim(u8, idx8, " "), 10) catch 0;
                icon = u.dupeW(icon[0..comma]);
            }
            icon = u.dupeW(std.mem.trim(u16, icon, &[_]u16{ '"', ' ' }));
            var search: std.ArrayList(u16) = .empty;
            for (name) |ch| search.append(gpa, u.lower(ch)) catch u.oom();
            search.append(gpa, ' ') catch u.oom();
            for (publisher) |ch| search.append(gpa, u.lower(ch)) catch u.oom();
            out.append(gpa, .{
                .name = name,
                .publisher = publisher,
                .version = version,
                .location = u.trimSlash(std.mem.trim(u16, regStr(k.?, sub, "InstallLocation"), &[_]u16{'"'})),
                .uninstall = unin,
                .quiet = regStr(k.?, sub, "QuietUninstallString"),
                .icon_path = icon,
                .icon_index = icon_index,
                .size_kb = regDword(k.?, sub, "EstimatedSize") orelse 0,
                .date = date,
                .hive = hive,
                .key = sub,
                .search = search.toOwnedSlice(gpa) catch u.oom(),
            }) catch u.oom();
        }
    }
    const items = out.toOwnedSlice(gpa) catch u.oom();
    std.mem.sort(App, items, {}, struct {
        fn lt(_: void, a: App, b: App) bool {
            return lessI(a.name, b.name);
        }
    }.lt);
    return items;
}

pub fn lessI(a: []const u16, b: []const u16) bool {
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |x, y| if (u.lower(x) != u.lower(y)) return u.lower(x) < u.lower(y);
    return a.len < b.len;
}

pub fn loadIcon(a: *App, px: u32) void {
    if (a.icon_tried) return;
    a.icon_tried = true;
    if (a.icon_path.len == 0) return;
    var large: ?w.HICON = null;
    if (w.SHDefExtractIconW(a.icon_path.ptr, a.icon_index, 0, &large, null, px) == 0) a.icon = large;
}

pub fn keyExists(a: *const App) bool {
    const full = u.concat(&.{ uninstall_path, L("\\"), a.key });
    defer gpa.free(full);
    var k: ?w.HKEY = null;
    if (w.RegOpenKeyExW(hiveKey(a.hive), full.ptr, 0, w.KEY_READ | hiveView(a.hive), &k) != 0) return false;
    _ = w.RegCloseKey(k.?);
    return true;
}

pub const Started = struct { proc: ?w.HANDLE, silent: bool };

fn splitCmd(cmd: []const u16) struct { file: []const u16, params: []const u16 } {
    if (cmd.len > 0 and cmd[0] == '"') {
        if (std.mem.indexOfScalarPos(u16, cmd, 1, '"')) |q| return .{ .file = cmd[1..q], .params = std.mem.trim(u16, cmd[q + 1 ..], &[_]u16{' '}) };
    } else if (u.findI(cmd, L(".exe"))) |e| {
        return .{ .file = cmd[0 .. e + 4], .params = std.mem.trim(u16, cmd[e + 4 ..], &[_]u16{' '}) };
    } else if (std.mem.indexOfScalar(u16, cmd, ' ')) |sp| {
        return .{ .file = cmd[0..sp], .params = cmd[sp + 1 ..] };
    }
    return .{ .file = cmd, .params = L("") };
}

/// Starts the uninstaller without questions where the installer type allows it:
/// QuietUninstallString, MSI (/X /passive), Inno Setup (/VERYSILENT), Squirrel (-s), NSIS-style (/S).
/// Unknown uninstallers run with their own UI. UAC may still appear unless Junk Cleaner runs as Admin.
pub const Command = struct { file: [:0]u16, params: [:0]u16, silent: bool };

pub fn startUninstall(a: *const App) ?Started {
    const cmd = uninstallCommand(a);
    var sei: w.SHELLEXECUTEINFOW = .{ .fMask = w.SEE_MASK_NOCLOSEPROCESS, .lpFile = cmd.file.ptr, .lpParameters = cmd.params.ptr, .nShow = if (cmd.silent) 0 else w.SW_SHOWNORMAL };
    u.log(u.fmt8("  Lệnh gỡ: \"{s}\" {s}", .{ u.U8(cmd.file), u.U8(cmd.params) }));
    if (w.ShellExecuteExW(&sei) == 0) return null;
    return .{ .proc = sei.hProcess, .silent = cmd.silent };
}

pub fn uninstallCommand(a: *const App) Command {
    var silent = true;
    var file: []const u16 = undefined;
    var params: []const u16 = undefined;
    if (a.quiet.len > 0 and !u.endsWithI(a.key, L("_is1"))) {
        const sc = splitCmd(std.mem.trim(u16, a.quiet, &[_]u16{' '}));
        file = sc.file;
        params = sc.params;
    } else {
        const sc = splitCmd(std.mem.trim(u16, a.uninstall, &[_]u16{' '}));
        file = sc.file;
        params = sc.params;
        const base = u.baseName(file);
        if (u.findI(base, L("msiexec")) != null) {
            const m = u.dupeW(params);
            if (u.findI(m, L("/I{"))) |i| m[i + 1] = 'X';
            params = u.concat(&.{ m, L(" /passive /norestart") });
        } else if (u.endsWithI(a.key, L("_is1"))) {
            params = u.concat(&.{ params, L(" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART") });
        } else if (u.eqlI(base, L("update.exe")) and u.findI(params, L("--uninstall")) != null) {
            params = u.concat(&.{ params, L(" -s") });
        } else if (params.len == 0 and (u.startsWithI(base, L("uninst")) or u.startsWithI(base, L("uninstall")))) {
            params = L("/S");
        } else silent = false;
    }
    return .{ .file = u.dupeW(file), .params = u.dupeW(params), .silent = silent };
}

// ---------------------------------------------------------------- leftovers

pub const LeftKind = enum { folder, file, regkey };

pub const Leftover = struct {
    kind: LeftKind,
    display: Str,
    reason: Str,
    path: Str = L(""), // filesystem path
    hive: Hive = .hkcu, // registry
    parent: Str = L(""),
    child: Str = L(""),
    bytes: i64 = 0,
    checked: bool = true,
};

const protected = [_][]const u16{
    L("Microsoft"), L("Windows"),     L("Common Files"), L("Packages"),  L("Temp"),           L("WindowsApps"),
    L("Microsoft.NET"), L("dotnet"),  L("Internet Explorer"), L("Windows Defender"), L("Windows NT"), L("Programs"),
    L("Package Cache"), L("Classes"), L("Policies"),     L("Wow6432Node"), L("Clients"),       L("RegisteredApplications"),
    L("JunkCleaner"), L("Intel"),     L("NVIDIA Corporation"), L("Google"), L("Mozilla"),
};

fn isProtected(name: []const u16) bool {
    for (protected) |x| if (u.eqlI(name, x)) return true;
    return false;
}

/// "Riot Client 1.2.3 (x64)" -> "riotclient"
pub fn coreName(name: []const u16) []u16 {
    var s = name;
    if (std.mem.indexOfScalar(u16, s, '(')) |i| s = s[0..i];
    // "Lightshot-5.5.0.7", "dbForge SQL Complete, v2025.2" -> cut before the version
    for (s, 0..) |ch, i| {
        if ((ch == '-' or ch == ',' or ch == '_') and i + 1 < s.len) {
            var j = i + 1;
            while (j < s.len and s[j] == ' ') j += 1;
            if (j < s.len and (s[j] == 'v' or s[j] == 'V')) j += 1;
            if (j < s.len and s[j] >= '0' and s[j] <= '9') {
                s = s[0..i];
                break;
            }
        }
    }
    // drop trailing words containing digits (versions) or arch tags
    while (true) {
        const t = std.mem.trimEnd(u16, s, &[_]u16{ ' ', '-', '_' });
        const sp = std.mem.lastIndexOfScalar(u16, t, ' ') orelse {
            s = t;
            break;
        };
        const word = t[sp + 1 ..];
        var has_digit = false;
        for (word) |ch| if (ch >= '0' and ch <= '9') {
            has_digit = true;
        };
        if (has_digit or u.eqlI(word, L("x64")) or u.eqlI(word, L("x86")) or u.eqlI(word, L("64-bit"))) s = t[0..sp] else {
            s = t;
            break;
        }
    }
    return u.normalize(s);
}

fn nameMatches(folder: []const u16, core: []const u16) bool {
    const nd = u.normalize(folder);
    defer gpa.free(nd);
    if (nd.len == 0 or core.len == 0) return false;
    if (std.mem.eql(u16, nd, core)) return true;
    if (nd.len < 4 or core.len < 4) return false;
    return std.mem.startsWith(u16, core, nd) or std.mem.startsWith(u16, nd, core);
}

fn exactName(folder: []const u16, core: []const u16) bool {
    const nd = u.normalize(folder);
    defer gpa.free(nd);
    return std.mem.eql(u16, nd, core);
}

const Finder = struct {
    app: *const App,
    others: []const App,
    core: []u16,
    pub_core: []u16,
    out: std.ArrayList(Leftover) = .empty,

    /// Another still-installed app also matches this name -> ambiguous, skip.
    fn ambiguous(self: *Finder, name: []const u16) bool {
        for (self.others) |*o| {
            if (o == self.app or std.mem.eql(u16, o.key, self.app.key)) continue;
            const oc = coreName(o.name);
            defer gpa.free(oc);
            if (std.mem.eql(u16, oc, self.core)) continue; // same product, other entry
            if (nameMatches(name, oc)) return true;
        }
        return false;
    }

    fn already(self: *Finder, path: []const u16) bool {
        for (self.out.items) |x| if (x.kind != .regkey and (u.eqlI(x.path, path) or (path.len > x.path.len and u.startsWithI(path, x.path) and path[x.path.len] == '\\'))) return true;
        return false;
    }

    fn addPath(self: *Finder, path: Str, reason: []const u8, checked: bool) void {
        if (self.already(path)) return;
        const is_dir = u.isDir(path);
        var r: c.ScanResult = .{};
        if (is_dir) {
            const t: c.Target = .{ .id = "", .name = L(""), .note = L(""), .group = .apps, .roots = &.{path} };
            r = c.scan(&t, 0);
        }
        self.out.append(gpa, .{ .kind = if (is_dir) .folder else .file, .display = path, .path = path, .reason = u.W(reason), .bytes = r.bytes, .checked = checked }) catch u.oom();
    }

    fn scanBase(self: *Finder, base: []const u16, reason: []const u8) void {
        for (c.subdirs(base)) |d| {
            const n = u.baseName(d);
            if (isProtected(n)) continue;
            if (nameMatches(n, self.core)) {
                if (!self.ambiguous(n)) self.addPath(d, reason, exactName(n, self.core));
            } else if (self.pub_core.len >= 3 and nameMatches(n, self.pub_core)) {
                // Publisher folder: look for the product inside.
                const inner = c.subdirs(d);
                var hits: usize = 0;
                for (inner) |id| if (nameMatches(u.baseName(id), self.core) and !self.ambiguous(u.baseName(id))) {
                    self.addPath(id, reason, exactName(u.baseName(id), self.core));
                    hits += 1;
                };
                if (hits > 0 and hits == inner.len and !self.ambiguous(n)) self.addPath(d, "Thư mục nhà phát hành (chỉ chứa app này)", false);
            }
        }
    }

    fn scanShortcuts(self: *Finder, dir: []const u16, reason: []const u8) void {
        const pat = u.concat(&.{ L("\\\\?\\"), dir, L("\\*") });
        defer gpa.free(pat);
        var fd: w.WIN32_FIND_DATAW = undefined;
        const h = w.FindFirstFileExW(pat.ptr, w.FindExInfoBasic, &fd, 0, null, 0);
        if (h == w.INVALID_HANDLE) return;
        defer _ = w.FindClose(h);
        while (true) {
            const name = std.mem.sliceTo(&fd.cFileName, 0);
            if (!c.isDots(name)) {
                const is_dir = (fd.dwFileAttributes & w.FILE_ATTRIBUTE_DIRECTORY) != 0;
                const stem = if (!is_dir and u.endsWithI(name, L(".lnk"))) name[0 .. name.len - 4] else if (is_dir) name else null;
                if (stem) |st| if (nameMatches(st, self.core) and !self.ambiguous(st)) self.addPath(u.join(dir, name), reason, exactName(st, self.core));
            }
            if (w.FindNextFileW(h, &fd) == 0) break;
        }
    }

    fn addReg(self: *Finder, hive: Hive, parent: []const u16, child: []const u16, reason: []const u8, checked: bool) void {
        const root = if (hive == .hkcu) "HKCU" else "HKLM";
        const view = if (hive == .hklm32) " (32-bit)" else "";
        self.out.append(gpa, .{
            .kind = .regkey,
            .display = u.fmtW("{s}\\{s}\\{s}{s}", .{ root, u.U8(parent), u.U8(child), view }),
            .reason = u.W(reason),
            .hive = hive,
            .parent = u.dupeW(parent),
            .child = u.dupeW(child),
            .checked = checked,
        }) catch u.oom();
    }

    fn scanRegistry(self: *Finder, hive: Hive, parent: []const u16) void {
        const pz = u.dupeW(parent);
        defer gpa.free(pz);
        var k: ?w.HKEY = null;
        if (w.RegOpenKeyExW(hiveKey(hive), pz.ptr, 0, w.KEY_READ | hiveView(hive), &k) != 0) return;
        defer _ = w.RegCloseKey(k.?);
        var i: w.DWORD = 0;
        while (true) : (i += 1) {
            var buf: [512]u16 = undefined;
            var n: w.DWORD = buf.len;
            if (w.RegEnumKeyExW(k.?, i, &buf, &n, null, null, null, null) != 0) break;
            const name = buf[0..n];
            if (isProtected(name)) continue;
            if (nameMatches(name, self.core) and !self.ambiguous(name)) {
                self.addReg(hive, parent, name, "Khóa registry của app", exactName(name, self.core));
            } else if (self.pub_core.len >= 3 and nameMatches(name, self.pub_core)) {
                const sub_parent = u.concat(&.{ parent, L("\\"), name });
                const sz = u.dupeW(sub_parent);
                var k2: ?w.HKEY = null;
                if (w.RegOpenKeyExW(hiveKey(hive), sz.ptr, 0, w.KEY_READ | hiveView(hive), &k2) == 0) {
                    var j: w.DWORD = 0;
                    while (true) : (j += 1) {
                        var b2: [512]u16 = undefined;
                        var n2: w.DWORD = b2.len;
                        if (w.RegEnumKeyExW(k2.?, j, &b2, &n2, null, null, null, null) != 0) break;
                        if (nameMatches(b2[0..n2], self.core) and !self.ambiguous(b2[0..n2])) self.addReg(hive, sub_parent, b2[0..n2], "Khóa registry của app", exactName(b2[0..n2], self.core));
                    }
                    _ = w.RegCloseKey(k2.?);
                }
            }
        }
    }
};

pub fn findLeftovers(app: *const App, installed: []const App) []Leftover {
    const d = c.dirs;
    var f: Finder = .{ .app = app, .others = installed, .core = coreName(app.name), .pub_core = coreName(app.publisher) };
    if (f.core.len < 3) return f.out.toOwnedSlice(gpa) catch u.oom();

    if (app.location.len > 3 and u.isDir(app.location) and !isProtected(u.baseName(app.location)) and std.mem.count(u16, app.location, L("\\")) >= 2)
        f.addPath(app.location, "Thư mục cài đặt còn sót", true);
    f.scanBase(d.local, "AppData\\Local");
    f.scanBase(d.roaming, "AppData\\Roaming");
    f.scanBase(d.locallow, "AppData\\LocalLow");
    f.scanBase(u.join(d.local, L("Programs")), "AppData\\Local\\Programs");
    f.scanBase(d.progdata, "ProgramData");
    if (d.progfiles.len > 0) f.scanBase(d.progfiles, "Program Files");
    if (d.progfiles86.len > 0) f.scanBase(d.progfiles86, "Program Files (x86)");
    f.scanShortcuts(u.join(d.roaming, L("Microsoft\\Windows\\Start Menu\\Programs")), "Shortcut Start Menu");
    f.scanShortcuts(u.join(d.progdata, L("Microsoft\\Windows\\Start Menu\\Programs")), "Shortcut Start Menu");
    f.scanShortcuts(u.join(d.home, L("Desktop")), "Shortcut Desktop");
    f.scanShortcuts(u.join(u.env("PUBLIC"), L("Desktop")), "Shortcut Desktop");

    f.scanRegistry(.hkcu, L("Software"));
    f.scanRegistry(.hklm64, L("SOFTWARE"));
    f.scanRegistry(.hklm32, L("SOFTWARE"));
    if (keyExists(app)) f.addReg(app.hive, uninstall_path, app.key, "Mục gỡ cài đặt còn sót", true);
    return f.out.toOwnedSlice(gpa) catch u.oom();
}

pub const RemoveResult = struct { removed: usize = 0, failed: usize = 0, bytes: i64 = 0 };

/// Files/folders go to the Recycle Bin; registry keys are exported to a .reg backup first.
pub fn removeLeftovers(items: []const Leftover, app_name: []const u16) RemoveResult {
    var r: RemoveResult = .{};
    const backup_dir = u.join(u.app_dir, L("backup"));
    _ = w.CreateDirectoryW(backup_dir.ptr, null);
    const core8 = u.U8(coreName(app_name));
    var n: usize = 0;
    for (items) |it| {
        if (!it.checked) continue;
        switch (it.kind) {
            .folder, .file => {
                const from = u.concat(&.{ it.path, L("\x00") }); // double NUL
                var op: w.SHFILEOPSTRUCTW = .{
                    .wFunc = w.FO_DELETE,
                    .pFrom = from.ptr,
                    .fFlags = w.FOF_ALLOWUNDO | w.FOF_NOCONFIRMATION | w.FOF_SILENT | w.FOF_NOERRORUI,
                };
                if (w.SHFileOperationW(&op) == 0 and op.fAnyOperationsAborted == 0 and !u.exists(it.path)) {
                    r.removed += 1;
                    r.bytes += it.bytes;
                    u.log(u.fmt8("  Đã chuyển vào Thùng rác: {s}", .{u.U8(it.path)}));
                } else {
                    r.failed += 1;
                    u.log(u.fmt8("  Không xóa được (cần Admin hoặc đang dùng): {s}", .{u.U8(it.path)}));
                }
            },
            .regkey => {
                n += 1;
                const root = if (it.hive == .hkcu) "HKCU" else "HKLM";
                const file = u.fmt8("{s}\\{s}-{d}.reg", .{ u.U8(backup_dir), core8, n });
                const exp = u.fmtW("reg.exe export \"{s}\\{s}\\{s}\" \"{s}\" /y{s}", .{ root, u.U8(it.parent), u.U8(it.child), file, if (it.hive == .hklm32) " /reg:32" else " /reg:64" });
                const er = u.run(exp, true);
                if (er.code != 0) {
                    r.failed += 1;
                    u.log(u.fmt8("  Bỏ qua (không sao lưu được): {s}", .{u.U8(it.display)}));
                    continue;
                }
                var k: ?w.HKEY = null;
                const pz = u.dupeW(it.parent);
                if (w.RegOpenKeyExW(hiveKey(it.hive), pz.ptr, 0, w.KEY_ALL_ACCESS | hiveView(it.hive), &k) == 0) {
                    const cz = u.dupeW(it.child);
                    const res = w.RegDeleteTreeW(k.?, cz.ptr);
                    _ = w.RegCloseKey(k.?);
                    if (res == 0) {
                        r.removed += 1;
                        u.log(u.fmt8("  Đã xóa registry (sao lưu: {s}): {s}", .{ file, u.U8(it.display) }));
                        continue;
                    }
                }
                r.failed += 1;
                u.log(u.fmt8("  Không xóa được registry (cần Admin?): {s}", .{u.U8(it.display)}));
            },
        }
    }
    return r;
}
