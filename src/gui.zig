//! Custom-drawn UI in a shadcn/ui-like style (zinc palette, rounded cards, pill tabs, toasts, dialogs).
//! Shapes: GDI+ (anti-aliased). Text: GDI ClearType. Only the search box and the log are native EDITs.
const std = @import("std");
const w = @import("win.zig");
const u = @import("util.zig");
const c = @import("cleaner.zig");
const stale = @import("stale.zig");
const settings = @import("settings.zig");
const scheduler = @import("scheduler.zig");
const apps = @import("apps.zig");
const L = u.L;
const gpa = u.gpa;
const Str = u.Str;

// ================================================================ theme (zinc)
const page: u32 = 0xFFFAFAFA;
const card_bg: u32 = 0xFFFFFFFF;
const border: u32 = 0xFFE4E4E7;
const input_border: u32 = 0xFFD4D4D8;
const muted: u32 = 0xFFF4F4F5;
const muted_fg: u32 = 0xFF71717A;
const fg: u32 = 0xFF09090B;
const fg2: u32 = 0xFF3F3F46;
const primary: u32 = 0xFF18181B;
const primary_hover: u32 = 0xFF3F3F46;
const destructive: u32 = 0xFFDC2626;
const destructive_hover: u32 = 0xFFB91C1C;
const destructive_soft: u32 = 0xFFFEF2F2;
const amber_bg: u32 = 0xFFFEF3C7;
const amber_fg: u32 = 0xFF92400E;
const green_bg: u32 = 0xFFDCFCE7;
const green_fg: u32 = 0xFF166534;
const white: u32 = 0xFFFFFFFF;

const Font = enum(u8) { title, h, body, body_b, small, small_b, mono };
const font_specs = [_]struct { px: f32, weight: i32, face: Str }{
    .{ .px = 22, .weight = 600, .face = L("Segoe UI") },
    .{ .px = 15, .weight = 600, .face = L("Segoe UI") },
    .{ .px = 14, .weight = 400, .face = L("Segoe UI") },
    .{ .px = 14, .weight = 600, .face = L("Segoe UI") },
    .{ .px = 12.5, .weight = 400, .face = L("Segoe UI") },
    .{ .px = 12, .weight = 600, .face = L("Segoe UI") },
    .{ .px = 12.5, .weight = 400, .face = L("Consolas") },
};
var fonts: [font_specs.len]?w.HFONT = @splat(null);

// ================================================================ state
var hwnd: w.HWND = undefined;
var hinst: ?w.HINSTANCE = null;
var scale: f32 = 1;
var win_w: f32 = 0;
var win_h: f32 = 0;
var edit_search: w.HWND = undefined;
var edit_log: w.HWND = undefined;
var white_brush: ?w.HBRUSH = null;

var tg: std.ArrayList(c.Target) = .empty;
var static_n: usize = 0;
var app_list: []apps.App = &.{};
var view: std.ArrayList(usize) = .empty;
var sort_mode: u8 = 0;
var tab: u8 = 0;
var scroll = [3]f32{ 0, 0, 0 };
var scroll_max = [3]f32{ 0, 0, 0 };

var clean_busy = false;
var clean_status: Str = L("");
var disk_free: u64 = 0;
var disk_total: u64 = 0;

// uninstall queue (processed one by one by a background worker)
var q_lock: w.SRWLOCK = .{};
var queue: std.ArrayList(usize) = .empty;
var worker_running = false;
var skip_current = std.atomic.Value(bool).init(false);
var quitting = std.atomic.Value(bool).init(false);

const Toast = struct { title: [:0]u16, desc: [:0]u16, ok: bool, until: u64 };
var toast: ?Toast = null;
var spinner_visible = false;

const Act = union(enum) {
    none,
    tab: u8,
    toggle: usize,
    scan,
    clean,
    admin,
    uninstall: usize,
    sort: u8,
    sched: u8,
    time_minus,
    time_plus,
    age_minus,
    age_plus,
    stale_minus,
    stale_plus,
    save_sched,
    open_log,
    skip_wait,
    toast_close,
};
const Rf = struct {
    x: f32, y: f32, w: f32, h: f32,
    fn has(r: Rf, px: f32, py: f32) bool {
        return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h;
    }
};
const Hit = struct { r: Rf, a: Act };
var hits: std.ArrayList(Hit) = .empty;
const ScrollArea = struct { r: Rf, idx: usize };
var scroll_areas: std.ArrayList(ScrollArea) = .empty;
var hover: Act = .none;
var pressed: Act = .none;
var mouse_tracking = false;

const MSG_LOG = w.WM_APP + 1;
const MSG_ITEM = w.WM_APP + 2;
const MSG_DISCOVERED = w.WM_APP + 3;
const MSG_JOB_DONE = w.WM_APP + 4;
const MSG_APP_UPDATE = w.WM_APP + 5;
const MSG_APP_DONE = w.WM_APP + 6;
const MSG_QUEUE_IDLE = w.WM_APP + 7;
const ID_SEARCH: usize = 201;
const ID_LOG: usize = 202;

// ================================================================ drawing primitives
var dc: w.HDC = undefined;
var g: *w.GpGraphics = undefined;
var arena_state: std.heap.ArenaAllocator = undefined;
var fa: std.mem.Allocator = undefined; // per-frame allocator

fn S(v: f32) f32 {
    return v * scale;
}

/// printf into frame-lifetime UTF-16.
fn F(comptime f: []const u8, args: anytype) [:0]const u16 {
    const s = std.fmt.allocPrint(fa, f, args) catch u.oom();
    return std.unicode.utf8ToUtf16LeAllocZ(fa, s) catch L("?");
}

fn sizeStr(bytes: i64) []const u8 {
    const buf = fa.alloc(u8, 32) catch u.oom();
    return u.fmtSize(buf, bytes);
}

fn u8s(s: []const u16) []const u8 {
    return std.unicode.utf16LeToUtf8Alloc(fa, s) catch "?";
}

fn roundPath(x: f32, y: f32, wd: f32, ht: f32, r: f32) *w.GpPath {
    var p: ?*w.GpPath = null;
    _ = w.GdipCreatePath(0, &p);
    const X = S(x);
    const Y = S(y);
    const W = S(wd);
    const H = S(ht);
    const d = @max(@min(S(r) * 2, @min(W, H)), 0.5);
    _ = w.GdipAddPathArc(p.?, X, Y, d, d, 180, 90);
    _ = w.GdipAddPathArc(p.?, X + W - d, Y, d, d, 270, 90);
    _ = w.GdipAddPathArc(p.?, X + W - d, Y + H - d, d, d, 0, 90);
    _ = w.GdipAddPathArc(p.?, X, Y + H - d, d, d, 90, 90);
    _ = w.GdipClosePathFigure(p.?);
    return p.?;
}

fn fillRound(x: f32, y: f32, wd: f32, ht: f32, r: f32, color: u32) void {
    var b: ?*w.GpBrush = null;
    _ = w.GdipCreateSolidFill(color, &b);
    const p = roundPath(x, y, wd, ht, r);
    _ = w.GdipFillPath(g, b.?, p);
    _ = w.GdipDeletePath(p);
    _ = w.GdipDeleteBrush(b.?);
}

/// Bordered rounded box: crisp 1px border made of two fills.
fn box(x: f32, y: f32, wd: f32, ht: f32, r: f32, fill: u32, edge: u32) void {
    fillRound(x, y, wd, ht, r, edge);
    const t = 1 / scale;
    fillRound(x + t, y + t, wd - 2 * t, ht - 2 * t, @max(r - t, 0.5), fill);
}

fn fillRect(x: f32, y: f32, wd: f32, ht: f32, color: u32) void {
    var b: ?*w.GpBrush = null;
    _ = w.GdipCreateSolidFill(color, &b);
    _ = w.GdipFillRectangle(g, b.?, S(x), S(y), S(wd), S(ht));
    _ = w.GdipDeleteBrush(b.?);
}

fn line(x1: f32, y1: f32, x2: f32, y2: f32, color: u32, width: f32) void {
    var pen: ?*w.GpPen = null;
    _ = w.GdipCreatePen1(color, S(width), 2, &pen);
    _ = w.GdipSetPenStartCap(pen.?, 2);
    _ = w.GdipSetPenEndCap(pen.?, 2);
    _ = w.GdipDrawLine(g, pen.?, S(x1), S(y1), S(x2), S(y2));
    _ = w.GdipDeletePen(pen.?);
}

fn colorRef(argb: u32) w.DWORD {
    const r = (argb >> 16) & 0xFF;
    const gg = (argb >> 8) & 0xFF;
    const b = argb & 0xFF;
    return r | (gg << 8) | (b << 16);
}

const left_mid = w.DT_SINGLELINE | w.DT_VCENTER | w.DT_END_ELLIPSIS;

fn text(s: []const u16, x: f32, y: f32, wd: f32, ht: f32, font: Font, color: u32, flags: u32) void {
    if (s.len == 0) return;
    _ = w.GdipFlush(g, 1);
    _ = w.SelectObject(dc, @ptrCast(fonts[@intFromEnum(font)].?));
    _ = w.SetTextColor(dc, colorRef(color));
    var rc: w.RECT = .{
        .left = @intFromFloat(@round(S(x))),
        .top = @intFromFloat(@round(S(y))),
        .right = @intFromFloat(@round(S(x + wd))),
        .bottom = @intFromFloat(@round(S(y + ht))),
    };
    _ = w.DrawTextW(dc, s.ptr, @intCast(s.len), &rc, flags | w.DT_NOPREFIX);
}

fn textWidth(s: []const u16, font: Font) f32 {
    if (s.len == 0) return 0;
    _ = w.SelectObject(dc, @ptrCast(fonts[@intFromEnum(font)].?));
    var sz: w.SIZE = .{};
    _ = w.GetTextExtentPoint32W(dc, s.ptr, @intCast(s.len), &sz);
    return @as(f32, @floatFromInt(sz.cx)) / scale;
}

/// Height needed for word-wrapped text.
fn textHeight(s: []const u16, wd: f32, font: Font) f32 {
    _ = w.SelectObject(dc, @ptrCast(fonts[@intFromEnum(font)].?));
    var rc: w.RECT = .{ .right = @intFromFloat(S(wd)) };
    _ = w.DrawTextW(dc, s.ptr, @intCast(s.len), &rc, w.DT_WORDBREAK | w.DT_CALCRECT | w.DT_NOPREFIX);
    return @as(f32, @floatFromInt(rc.bottom)) / scale;
}

fn clip(r: Rf) void {
    _ = w.GdipSetClipRect(g, S(r.x), S(r.y), S(r.w), S(r.h), 0);
    _ = w.IntersectClipRect(dc, @intFromFloat(S(r.x)), @intFromFloat(S(r.y)), @intFromFloat(S(r.x + r.w)), @intFromFloat(S(r.y + r.h)));
}

fn unclip() void {
    _ = w.GdipResetClip(g);
    _ = w.SelectClipRgn(dc, null);
}

fn isHover(a: Act) bool {
    return std.meta.eql(hover, a);
}

fn addHit(r: Rf, a: Act) void {
    hits.append(gpa, .{ .r = r, .a = a }) catch u.oom();
}

// ================================================================ components
const Variant = enum { primary, outline, destructive, destructive_outline, ghost };

fn button(x: f32, y: f32, wd: f32, ht: f32, label: []const u16, v: Variant, a: Act, enabled: bool) void {
    const hov = enabled and isHover(a);
    var bg: u32 = undefined;
    var tc: u32 = undefined;
    var edge: ?u32 = null;
    switch (v) {
        .primary => {
            bg = if (hov) primary_hover else primary;
            tc = white;
        },
        .destructive => {
            bg = if (hov) destructive_hover else destructive;
            tc = white;
        },
        .outline => {
            bg = if (hov) muted else card_bg;
            tc = fg;
            edge = border;
        },
        .destructive_outline => {
            bg = if (hov) destructive_soft else card_bg;
            tc = destructive;
            edge = border;
        },
        .ghost => {
            bg = if (hov) muted else 0x00000000;
            tc = fg;
        },
    }
    if (!enabled) {
        bg = if (v == .primary or v == .destructive) 0xFFA1A1AA else muted;
        tc = if (v == .primary or v == .destructive) white else 0xFFA1A1AA;
        edge = null;
    }
    if (edge) |e| box(x, y, wd, ht, 8, bg, e) else if ((bg >> 24) != 0) fillRound(x, y, wd, ht, 8, bg);
    text(label, x, y, wd, ht, .body_b, tc, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
    if (enabled) addHit(.{ .x = x, .y = y, .w = wd, .h = ht }, a);
}

const BadgeKind = enum { outline, amber, green, secondary };

fn badge(x: f32, y: f32, label: []const u16, k: BadgeKind) f32 {
    const wd = textWidth(label, .small_b) + 16;
    switch (k) {
        .outline => box(x, y, wd, 20, 10, card_bg, border),
        .amber => fillRound(x, y, wd, 20, 10, amber_bg),
        .green => fillRound(x, y, wd, 20, 10, green_bg),
        .secondary => fillRound(x, y, wd, 20, 10, muted),
    }
    const tc: u32 = switch (k) {
        .outline => fg2,
        .amber => amber_fg,
        .green => green_fg,
        .secondary => fg2,
    };
    text(label, x, y, wd, 20, .small_b, tc, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
    return wd;
}

fn checkbox(x: f32, y: f32, checked: bool, enabled: bool) void {
    if (checked) {
        fillRound(x, y, 18, 18, 5, if (enabled) primary else 0xFFA1A1AA);
        line(x + 4.5, y + 9.5, x + 7.8, y + 12.8, white, 2);
        line(x + 7.8, y + 12.8, x + 13.5, y + 5.8, white, 2);
    } else box(x, y, 18, 18, 5, card_bg, input_border);
}

fn segmented(x: f32, y: f32, seg_w: f32, labels: []const []const u16, active: usize, comptime mk: fn (u8) Act) void {
    const n: f32 = @floatFromInt(labels.len);
    fillRound(x, y, seg_w * n + 8, 40, 10, muted);
    for (labels, 0..) |lab, i| {
        const fi: f32 = @floatFromInt(i);
        const bx = x + 4 + fi * seg_w;
        const a = mk(@intCast(i));
        if (i == active) {
            fillRound(bx, y + 4 + 1, seg_w, 32, 7, 0x0A000000);
            box(bx, y + 4, seg_w, 32, 7, card_bg, border);
        } else if (isHover(a)) fillRound(bx, y + 4, seg_w, 32, 7, 0xFFEAEAEC);
        text(lab, bx, y + 4, seg_w, 32, .body_b, if (i == active) fg else muted_fg, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
        addHit(.{ .x = bx, .y = y + 4, .w = seg_w, .h = 32 }, a);
    }
}

fn stepper(x: f32, y: f32, value: []const u16, minus: Act, plus: Act) void {
    const wd: f32 = 150;
    box(x, y, wd, 36, 8, card_bg, border);
    if (isHover(minus)) fillRound(x + 2, y + 2, 32, 32, 6, muted);
    if (isHover(plus)) fillRound(x + wd - 34, y + 2, 32, 32, 6, muted);
    line(x + 12, y + 18, x + 24, y + 18, fg, 1.6);
    line(x + wd - 24, y + 18, x + wd - 12, y + 18, fg, 1.6);
    line(x + wd - 18, y + 12, x + wd - 18, y + 24, fg, 1.6);
    fillRect(x + 36, y + 6, 1, 24, border);
    fillRect(x + wd - 37, y + 6, 1, 24, border);
    text(value, x + 36, y, wd - 72, 36, .body_b, fg, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
    addHit(.{ .x = x, .y = y, .w = 36, .h = 36 }, minus);
    addHit(.{ .x = x + wd - 36, .y = y, .w = 36, .h = 36 }, plus);
}

fn spinner(cx: f32, cy: f32, r: f32) void {
    spinner_visible = true;
    var pen: ?*w.GpPen = null;
    _ = w.GdipCreatePen1(0x33000000, S(2), 2, &pen);
    _ = w.GdipDrawEllipse(g, pen.?, S(cx - r), S(cy - r), S(2 * r), S(2 * r));
    _ = w.GdipDeletePen(pen.?);
    _ = w.GdipCreatePen1(fg, S(2), 2, &pen);
    _ = w.GdipSetPenStartCap(pen.?, 2);
    _ = w.GdipSetPenEndCap(pen.?, 2);
    const t: f32 = @floatFromInt(w.GetTickCount64() % 900);
    _ = w.GdipDrawArc(g, pen.?, S(cx - r), S(cy - r), S(2 * r), S(2 * r), t / 900 * 360, 90);
    _ = w.GdipDeletePen(pen.?);
}

fn card(x: f32, y: f32, wd: f32, ht: f32) void {
    fillRound(x, y + 1, wd, ht, 12, 0x0D000000);
    box(x, y, wd, ht, 12, card_bg, border);
}

fn scrollbar(r: Rf, idx: usize, content: f32) void {
    scroll_max[idx] = @max(0, content - r.h);
    scroll[idx] = std.math.clamp(scroll[idx], 0, scroll_max[idx]);
    scroll_areas.append(gpa, .{ .r = r, .idx = idx }) catch u.oom();
    if (content <= r.h) return;
    const th = @max(32, r.h * r.h / content);
    const ty = r.y + (r.h - th) * (scroll[idx] / scroll_max[idx]);
    fillRound(r.x + r.w - 8, ty + 2, 5, th - 4, 2.5, 0x33000000);
}

// ================================================================ screens
fn drawHeader() void {
    text(L("Junk Cleaner"), 28, 18, 400, 32, .title, fg, left_mid);
    text(L("Dọn rác ổ C và gỡ ứng dụng · bản Zig native"), 28, 50, 500, 20, .small, muted_fg, left_mid);
    if (u.is_admin) {
        const bw = textWidth(L("Quyền Admin"), .small_b) + 16;
        _ = badge(win_w - 28 - bw, 34, L("Quyền Admin"), .green);
    } else {
        button(win_w - 28 - 200, 26, 200, 36, L("Chạy với quyền Admin"), .outline, .admin, true);
    }
}

fn drawDisk() void {
    const x: f32 = 24;
    const y: f32 = 84;
    const wd = win_w - 48;
    card(x, y, wd, 92);
    const used = disk_total -| disk_free;
    const pct: f32 = if (disk_total > 0) @as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(disk_total)) else 0;
    text(L("Ổ C"), x + 20, y + 14, 200, 18, .small, muted_fg, left_mid);
    text(F("{s} trống", .{sizeStr(@intCast(disk_free))}), x + 20, y + 32, 400, 30, .title, fg, left_mid);
    text(F("Đã dùng {s} / {s} · {d:.0}%", .{ sizeStr(@intCast(used)), sizeStr(@intCast(disk_total)), pct * 100 }), x + wd - 420, y + 32, 400, 30, .body, muted_fg, left_mid | w.DT_RIGHT);
    fillRound(x + 20, y + 70, wd - 40, 8, 4, muted);
    fillRound(x + 20, y + 70, @max(8, (wd - 40) * pct), 8, 4, if (pct >= 0.9) destructive else primary);
}

fn mkTab(i: u8) Act {
    return .{ .tab = i };
}
fn mkSort(i: u8) Act {
    return .{ .sort = i };
}
fn mkSched(i: u8) Act {
    return .{ .sched = i };
}

fn drawTabs() void {
    const labels = [_][]const u16{ L("Dọn rác"), F("Ứng dụng · {d}", .{app_list.len}), L("Tự động & cài đặt") };
    segmented(24, 192, 170, &labels, tab, mkTab);
    if (clean_busy) {
        spinner(win_w - 36, 212, 7);
        text(clean_status, win_w - 400, 192, 350, 40, .small, muted_fg, left_mid | w.DT_RIGHT);
    }
}

const content_top: f32 = 248;

fn drawCleanTab() void {
    const x: f32 = 24;
    const wd = win_w - 48;
    const footer_y = win_h - 24 - 44;
    const list_h = footer_y - 16 - content_top;
    card(x, content_top, wd, list_h);
    const area: Rf = .{ .x = x + 1, .y = content_top + 1, .w = wd - 2, .h = list_h - 2 };

    // content height
    var content: f32 = 8;
    for (0..4) |gi| {
        var any = false;
        for (tg.items) |t| if (@intFromEnum(t.group) == gi) {
            any = true;
            content += 60;
        };
        if (any) content += 40;
    }
    content += 8;
    scrollbar(area, 0, content);
    clip(area);
    var y = content_top + 8 - scroll[0];
    for (0..4) |gi| {
        var any = false;
        for (tg.items) |t| if (@intFromEnum(t.group) == gi) {
            any = true;
        };
        if (!any) continue;
        text(c.group_titles[gi], x + 20, y + 10, wd - 40, 24, .small_b, muted_fg, left_mid);
        y += 40;
        for (tg.items, 0..) |*t, i| {
            if (@intFromEnum(t.group) != gi) continue;
            defer y += 60;
            if (y + 60 < area.y or y > area.y + area.h) continue;
            const locked = t.needs_admin and !u.is_admin;
            const a: Act = .{ .toggle = i };
            if (isHover(a)) fillRound(x + 8, y, wd - 16, 60, 8, muted);
            checkbox(x + 22, y + 21, t.checked, !clean_busy);
            text(t.name, x + 56, y + 9, wd - 300, 22, .body_b, if (locked) muted_fg else fg, left_mid);
            if (t.needs_admin) {
                const nw = @min(textWidth(t.name, .body_b), wd - 300);
                _ = badge(x + 56 + nw + 8, y + 10, L("Admin"), .outline);
            }
            text(t.note, x + 56, y + 31, wd - 260, 20, .small, muted_fg, left_mid);
            const size_txt: []const u16 = if (t.busy_text) |bt| bt else switch (t.bytes) {
                -2 => L("—"),
                -1 => L("chưa rõ"),
                else => F("{s}", .{sizeStr(t.bytes)}),
            };
            text(size_txt, x + wd - 200, y, 170, 60, if (t.busy_text != null) .small else .body_b, if (t.busy_text != null or t.bytes < 0) muted_fg else fg, left_mid | w.DT_RIGHT);
            const vis_top = @max(y, area.y);
            const vis_bot = @min(y + 60, area.y + area.h);
            if (!clean_busy and vis_bot > vis_top) addHit(.{ .x = x + 8, .y = vis_top, .w = wd - 16, .h = vis_bot - vis_top }, a);
        }
    }
    unclip();

    // footer
    var total: i64 = 0;
    var count: usize = 0;
    for (tg.items) |t| if (t.checked) {
        count += 1;
        if (t.bytes > 0) total += t.bytes;
    };
    text(L("Đã chọn"), 28, footer_y, 300, 18, .small, muted_fg, left_mid);
    text(F("{s} · {d} mục", .{ sizeStr(total), count }), 28, footer_y + 18, 400, 26, .h, fg, left_mid);
    button(win_w - 24 - 140, footer_y, 140, 44, L("Dọn dẹp"), .primary, .clean, !clean_busy and count > 0);
    button(win_w - 24 - 140 - 10 - 110, footer_y, 110, 44, L("Quét lại"), .outline, .scan, !clean_busy);
}

fn searchRect() Rf {
    return .{ .x = 24, .y = content_top, .w = 340, .h = 40 };
}

fn drawAppsTab() void {
    const sr = searchRect();
    box(sr.x, sr.y, sr.w, sr.h, 8, card_bg, input_border);
    // magnifier icon
    var pen: ?*w.GpPen = null;
    _ = w.GdipCreatePen1(muted_fg, S(1.6), 2, &pen);
    _ = w.GdipDrawEllipse(g, pen.?, S(sr.x + 13), S(sr.y + 13), S(11), S(11));
    _ = w.GdipDeletePen(pen.?);
    line(sr.x + 22.5, sr.y + 22.5, sr.x + 27, sr.y + 27, muted_fg, 1.6);

    const sorts = [_][]const u16{ L("Tên"), L("Dung lượng"), L("Lâu không dùng") };
    segmented(sr.x + sr.w + 12, content_top, 120, &sorts, sort_mode, mkSort);
    var total_kb: u64 = 0;
    for (view.items) |i| total_kb += app_list[i].size_kb;
    text(F("{d} ứng dụng · {s}", .{ view.items.len, sizeStr(@intCast(total_kb * 1024)) }), win_w - 24 - 300, content_top, 300, 40, .small, muted_fg, left_mid | w.DT_RIGHT);

    const x: f32 = 24;
    const wd = win_w - 48;
    const top = content_top + 56;
    const ht = win_h - 24 - top;
    card(x, top, wd, ht);
    const area: Rf = .{ .x = x + 1, .y = top + 1, .w = wd - 2, .h = ht - 2 };
    const row_h: f32 = 68;
    scrollbar(area, 1, @as(f32, @floatFromInt(view.items.len)) * row_h + 12);
    clip(area);
    const now = u.now();
    for (view.items, 0..) |ai, vi| {
        const y = top + 6 + @as(f32, @floatFromInt(vi)) * row_h - scroll[1];
        if (y + row_h < area.y or y > area.y + area.h) continue;
        const a = &app_list[ai];
        const act: Act = .{ .uninstall = ai };
        if (isHover(act)) fillRound(x + 8, y, wd - 16, row_h, 8, muted);
        apps.loadIcon(a, @intFromFloat(S(32)));
        if (a.icon) |ic| {
            _ = w.GdipFlush(g, 1);
            _ = w.DrawIconEx(dc, @intFromFloat(S(x + 20)), @intFromFloat(S(y + 18)), ic, @intFromFloat(S(32)), @intFromFloat(S(32)), 0, null, 3);
        } else {
            fillRound(x + 20, y + 18, 32, 32, 8, muted);
            text(a.name[0..1], x + 20, y + 18, 32, 32, .body_b, muted_fg, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
        }
        text(a.name, x + 66, y + 13, wd - 400, 22, .body_b, fg, left_mid);
        var meta: std.ArrayList(u8) = .empty;
        if (a.publisher.len > 0) meta.appendSlice(fa, u8s(a.publisher)) catch u.oom();
        if (a.version.len > 0) meta.appendSlice(fa, std.fmt.allocPrint(fa, "{s}v{s}", .{ if (meta.items.len > 0) " · " else "", u8s(a.version) }) catch u.oom()) catch u.oom();
        if (a.size_kb > 0) meta.appendSlice(fa, std.fmt.allocPrint(fa, " · {s}", .{sizeStr(@intCast(a.size_kb * 1024))}) catch u.oom()) catch u.oom();
        if (a.date.len > 0) meta.appendSlice(fa, std.fmt.allocPrint(fa, " · cài {s}", .{u8s(a.date)}) catch u.oom()) catch u.oom();
        text(F("{s}", .{meta.items}), x + 66, y + 35, wd - 400, 20, .small, muted_fg, left_mid);

        const bx = x + wd - 20 - 76;
        const vis_top = @max(y + 18, area.y);
        const vis_bot = @min(y + 50, area.y + area.h);
        const visible = vis_bot > vis_top;
        var badge_right = bx - 12;
        switch (a.state) {
            .idle, .failed => {
                box(bx, y + 18, 76, 32, 8, if (isHover(act)) destructive_soft else card_bg, border);
                text(L("Gỡ"), bx, y + 18, 76, 32, .body_b, destructive, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
                if (visible) addHit(.{ .x = bx, .y = vis_top, .w = 76, .h = vis_bot - vis_top }, act);
                if (a.state == .failed) {
                    const lab = L("Gỡ chưa xong");
                    badge_right -= badge(badge_right - (textWidth(lab, .small_b) + 16), y + 24, lab, .amber) + 8;
                }
            },
            .queued => _ = badge(x + wd - 20 - (textWidth(L("Đang chờ"), .small_b) + 16), y + 24, L("Đang chờ"), .secondary),
            .uninstalling, .cleaning => {
                const lab = if (a.state == .uninstalling) L("Đang gỡ…") else L("Đang dọn file sót…");
                const tw = textWidth(lab, .small) + 8;
                var right = x + wd - 20;
                if (a.state == .uninstalling) {
                    button(right - 76, y + 18, 76, 32, L("Bỏ qua"), .ghost, .skip_wait, visible);
                    right -= 84;
                }
                text(lab, right - tw, y, tw, row_h, .small, muted_fg, left_mid | w.DT_RIGHT);
                spinner(right - tw - 12, y + row_h / 2, 7);
                badge_right = right - tw - 28;
            },
            .removed => _ = badge(x + wd - 20 - (textWidth(L("Đã gỡ"), .small_b) + 16), y + 24, L("Đã gỡ"), .green),
        }
        if (a.last_used > 0 and (a.state == .idle or a.state == .failed)) {
            const days = (now -| a.last_used) / u.DAY;
            const lab = F("Không dùng {d} ngày", .{days});
            const bw = textWidth(lab, .small_b) + 16;
            _ = badge(badge_right - bw, y + 24, lab, .amber);
        }
    }
    if (view.items.len == 0) text(L("Không tìm thấy ứng dụng nào"), x, top, wd, 120, .body, muted_fg, w.DT_SINGLELINE | w.DT_VCENTER | w.DT_CENTER);
    unclip();
}

fn logCardRect() Rf {
    const y = content_top + 236;
    return .{ .x = 24, .y = y, .w = win_w - 48, .h = win_h - 24 - y };
}

fn drawAutoTab() void {
    const cw = (win_w - 48 - 16) / 2;
    const y = content_top;
    // schedule card
    const ax: f32 = 24;
    card(ax, y, cw, 220);
    text(L("Lịch tự động dọn"), ax + 20, y + 16, cw - 40, 24, .h, fg, left_mid);
    text(L("Chạy ngầm và dọn các mục đang được chọn ở tab Dọn rác."), ax + 20, y + 40, cw - 40, 20, .small, muted_fg, left_mid);
    const labels = [_][]const u16{ L("Tắt"), L("Hàng ngày"), L("Hàng tuần"), L("Đăng nhập") };
    segmented(ax + 20, y + 72, (cw - 48) / 4, &labels, @intFromEnum(settings.schedule), mkSched);
    if (settings.schedule == .daily or settings.schedule == .weekly) {
        text(if (settings.schedule == .weekly) L("Chủ nhật, lúc") else L("Giờ chạy"), ax + 20, y + 130, 120, 36, .body, fg2, left_mid);
        stepper(ax + 140, y + 130, F("{d:0>2}:{d:0>2}", .{ settings.hour, settings.minute }), .time_minus, .time_plus);
    } else if (settings.schedule == .logon) {
        text(L("Chạy 5 phút sau khi đăng nhập."), ax + 20, y + 130, cw - 40, 36, .body, fg2, left_mid);
    }
    button(ax + cw - 20 - 120, y + 220 - 20 - 40, 120, 40, L("Lưu lịch"), .primary, .save_sched, true);

    // settings card
    const bx = ax + cw + 16;
    card(bx, y, cw, 220);
    text(L("Cài đặt"), bx + 20, y + 16, cw - 40, 24, .h, fg, left_mid);
    text(L("Áp dụng từ lần quét tiếp theo."), bx + 20, y + 40, cw - 40, 20, .small, muted_fg, left_mid);
    text(L("Chỉ xóa file tạm cũ hơn"), bx + 20, y + 80, cw - 200, 36, .body, fg2, left_mid);
    stepper(bx + cw - 20 - 150, y + 80, F("{d} ngày", .{settings.temp_age_days}), .age_minus, .age_plus);
    text(L("App coi là lâu không dùng sau"), bx + 20, y + 136, cw - 200, 36, .body, fg2, left_mid);
    stepper(bx + cw - 20 - 150, y + 136, F("{d} ngày", .{settings.stale_days}), .stale_minus, .stale_plus);

    // log card
    const lr = logCardRect();
    card(lr.x, lr.y, lr.w, lr.h);
    text(L("Nhật ký"), lr.x + 20, lr.y + 14, 300, 24, .h, fg, left_mid);
    button(lr.x + lr.w - 20 - 120, lr.y + 10, 120, 32, L("Mở file log"), .ghost, .open_log, true);
}

fn drawToast() void {
    const t = toast orelse return;
    const tw: f32 = 380;
    const th: f32 = 76;
    const x = win_w - 24 - tw;
    const y = win_h - 24 - th;
    fillRound(x, y + 3, tw, th, 12, 0x1A000000);
    box(x, y, tw, th, 12, card_bg, border);
    fillRound(x + 16, y + 18, 22, 22, 11, if (t.ok) green_bg else destructive_soft);
    if (t.ok) {
        line(x + 21.5, y + 29, x + 25.5, y + 33, green_fg, 2);
        line(x + 25.5, y + 33, x + 32.5, y + 24.5, green_fg, 2);
    } else {
        line(x + 23, y + 25, x + 31, y + 33, destructive, 2);
        line(x + 31, y + 25, x + 23, y + 33, destructive, 2);
    }
    text(t.title, x + 50, y + 14, tw - 66, 22, .body_b, fg, left_mid);
    text(t.desc, x + 50, y + 36, tw - 66, 34, .small, muted_fg, w.DT_WORDBREAK | w.DT_END_ELLIPSIS);
    addHit(.{ .x = x, .y = y, .w = tw, .h = th }, .toast_close);
}

fn drawAll() void {
    fillRect(0, 0, win_w, win_h, page);
    drawHeader();
    drawDisk();
    drawTabs();
    switch (tab) {
        0 => drawCleanTab(),
        1 => drawAppsTab(),
        else => drawAutoTab(),
    }
    drawToast();
}

fn paint() void {
    var ps: w.PAINTSTRUCT = .{};
    const hdc = w.BeginPaint(hwnd, &ps) orelse return;
    defer _ = w.EndPaint(hwnd, &ps);
    var rc: w.RECT = .{};
    _ = w.GetClientRect(hwnd, &rc);
    if (rc.right <= 0 or rc.bottom <= 0) return;
    const mem = w.CreateCompatibleDC(hdc) orelse return;
    defer _ = w.DeleteDC(mem);
    const bmp = w.CreateCompatibleBitmap(hdc, rc.right, rc.bottom) orelse return;
    defer _ = w.DeleteObject(@ptrCast(bmp));
    const old = w.SelectObject(mem, @ptrCast(bmp));
    defer _ = w.SelectObject(mem, old.?);

    arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    fa = arena_state.allocator();

    dc = mem;
    var gp: ?*w.GpGraphics = null;
    if (w.GdipCreateFromHDC(mem, &gp) != 0) return;
    g = gp.?;
    _ = w.GdipSetSmoothingMode(g, 4);
    _ = w.GdipSetPixelOffsetMode(g, 4);
    _ = w.SetBkMode(mem, w.TRANSPARENT);
    hits.clearRetainingCapacity();
    scroll_areas.clearRetainingCapacity();
    spinner_visible = false;
    win_w = @as(f32, @floatFromInt(rc.right)) / scale;
    win_h = @as(f32, @floatFromInt(rc.bottom)) / scale;
    drawAll();
    _ = w.GdipDeleteGraphics(g);
    _ = w.BitBlt(hdc, 0, 0, rc.right, rc.bottom, mem, 0, 0, w.SRCCOPY);
}

fn invalidate() void {
    _ = w.InvalidateRect(hwnd, null, 0);
}

// ================================================================ native edits
var ready = false;

fn placeEdits() void {
    if (!ready) return;
    var rc: w.RECT = .{};
    _ = w.GetClientRect(hwnd, &rc);
    win_w = @as(f32, @floatFromInt(rc.right)) / scale;
    win_h = @as(f32, @floatFromInt(rc.bottom)) / scale;
    const sr = searchRect();
    move(edit_search, sr.x + 34, sr.y + 10, sr.w - 44, 22);
    const lr = logCardRect();
    move(edit_log, lr.x + 20, lr.y + 50, lr.w - 40, lr.h - 64);
    _ = w.ShowWindow(edit_search, if (tab == 1) w.SW_SHOW else w.SW_HIDE);
    _ = w.ShowWindow(edit_log, if (tab == 2) w.SW_SHOW else w.SW_HIDE);
}

fn move(h: w.HWND, x: f32, y: f32, wd: f32, ht: f32) void {
    _ = w.MoveWindow(h, @intFromFloat(S(x)), @intFromFloat(S(y)), @intFromFloat(@max(S(wd), 1)), @intFromFloat(@max(S(ht), 1)), 1);
}

fn makeFonts() void {
    for (&fonts, font_specs) |*f, spec| {
        if (f.*) |old| _ = w.DeleteObject(@ptrCast(old));
        f.* = w.CreateFontW(-@as(i32, @intFromFloat(@round(spec.px * scale))), 0, 0, 0, spec.weight, 0, 0, 0, 1, 0, 0, 5, 0, spec.face.ptr);
    }
    _ = w.SendMessageW(edit_search, w.WM_SETFONT, @intFromPtr(fonts[@intFromEnum(Font.body)].?), 1);
    _ = w.SendMessageW(edit_log, w.WM_SETFONT, @intFromPtr(fonts[@intFromEnum(Font.mono)].?), 1);
}

fn logUi(s: []const u8) void {
    var t: w.SYSTEMTIME = .{};
    w.GetLocalTime(&t);
    const line_w = u.fmtW("[{d:0>2}:{d:0>2}:{d:0>2}] {s}\r\n", .{ t.wHour, t.wMinute, t.wSecond, s });
    defer gpa.free(line_w);
    const len: usize = @intCast(w.GetWindowTextLengthW(edit_log));
    _ = w.SendMessageW(edit_log, w.EM_SETSEL, len, @intCast(len));
    _ = w.SendMessageW(edit_log, w.EM_REPLACESEL, 0, @bitCast(@intFromPtr(line_w.ptr)));
}

/// From worker threads: write to the log file and forward to the UI log.
fn postLog(s: []const u8) void {
    u.log(s);
    const ws = u.W(s);
    _ = w.PostMessageW(hwnd, MSG_LOG, 0, @bitCast(@intFromPtr(ws.ptr)));
}

fn showToast(ok: bool, title: []const u8, desc: []const u8) void {
    if (toast) |t| {
        gpa.free(t.title);
        gpa.free(t.desc);
    }
    toast = .{ .ok = ok, .title = u.W(title), .desc = u.W(desc), .until = w.GetTickCount64() + 5000 };
    invalidate();
}

// ================================================================ data helpers
fn refreshDisk() void {
    const root = u.systemDriveRoot();
    defer gpa.free(root);
    _ = w.GetDiskFreeSpaceExW(root.ptr, &disk_free, &disk_total, null);
}

fn saveSelection() void {
    var sel: std.ArrayList(u8) = .empty;
    var exc: std.ArrayList(u8) = .empty;
    // keep exclusions for apps not currently listed
    var it = std.mem.tokenizeScalar(u8, settings.excluded, ',');
    while (it.next()) |id| {
        var shown = false;
        for (tg.items[static_n..]) |t| if (std.mem.eql(u8, t.id, id)) {
            shown = true;
        };
        if (!shown) {
            if (exc.items.len > 0) exc.append(gpa, ',') catch u.oom();
            exc.appendSlice(gpa, id) catch u.oom();
        }
    }
    for (tg.items, 0..) |t, i| {
        const list = if (i < static_n) &sel else &exc;
        const want = if (i < static_n) t.checked else !t.checked;
        if (!want) continue;
        if (list.items.len > 0) list.append(gpa, ',') catch u.oom();
        list.appendSlice(gpa, t.id) catch u.oom();
    }
    settings.selected = sel.toOwnedSlice(gpa) catch u.oom();
    settings.excluded = exc.toOwnedSlice(gpa) catch u.oom();
    settings.save();
}

fn rebuildView() void {
    var buf: [256]u16 = undefined;
    const n: usize = @intCast(w.GetWindowTextW(edit_search, &buf, buf.len));
    for (buf[0..n]) |*ch| ch.* = u.lower(ch.*);
    const q = std.mem.trim(u16, buf[0..n], &[_]u16{' '});
    view.clearRetainingCapacity();
    for (app_list, 0..) |a, i| if (q.len == 0 or u.findI(a.search, q) != null) view.append(gpa, i) catch u.oom();
    const Ctx = struct {
        fn bySize(_: void, a: usize, b: usize) bool {
            return app_list[a].size_kb > app_list[b].size_kb;
        }
        fn byUnused(_: void, a: usize, b: usize) bool {
            const la = app_list[a].last_used;
            const lb = app_list[b].last_used;
            if ((la == 0) != (lb == 0)) return la != 0;
            if (la != lb) return la < lb;
            return a < b;
        }
    };
    switch (sort_mode) {
        1 => std.mem.sort(usize, view.items, {}, Ctx.bySize),
        2 => std.mem.sort(usize, view.items, {}, Ctx.byUnused),
        else => {},
    }
    scroll[1] = 0;
}

fn applyLastUsed() void {
    for (app_list) |*a| a.last_used = stale.lastUsedFor(a.name);
}

fn reloadApps() void {
    for (app_list) |a| if (a.icon) |ic| {
        _ = w.DestroyIcon(ic);
    };
    app_list = apps.list();
    applyLastUsed();
    rebuildView();
}

// ================================================================ background jobs (clean tab)
const JobKind = enum(usize) { discover, scan, clean };
const Job = struct { kind: JobKind, idx: []const usize, age: u32, days: u32 };

fn startJob(kind: JobKind, idx: []const usize) void {
    clean_busy = true;
    clean_status = switch (kind) {
        .discover => L("Đang tìm app lâu không dùng…"),
        .scan => L("Đang quét dung lượng…"),
        .clean => L("Đang dọn dẹp…"),
    };
    const job = gpa.create(Job) catch u.oom();
    job.* = .{ .kind = kind, .idx = idx, .age = settings.temp_age_days, .days = settings.stale_days };
    if (w.CreateThread(null, 0, &jobThread, job, 0, null)) |h| _ = w.CloseHandle(h);
    invalidate();
}

fn allIndices() []usize {
    const idx = gpa.alloc(usize, tg.items.len) catch u.oom();
    for (idx, 0..) |*v, i| v.* = i;
    return idx;
}

fn jobThread(arg: ?*anyopaque) callconv(.winapi) w.DWORD {
    const job: *Job = @ptrCast(@alignCast(arg.?));
    switch (job.kind) {
        .discover => {
            const found = gpa.create([]c.Target) catch u.oom();
            found.* = stale.discover(job.days);
            _ = w.PostMessageW(hwnd, MSG_DISCOVERED, 0, @bitCast(@intFromPtr(found)));
        },
        .scan => for (job.idx) |i| {
            const t = &tg.items[i];
            t.busy_text = L("Đang quét…");
            _ = w.PostMessageW(hwnd, MSG_ITEM, i, 0);
            const r = c.scan(t, job.age);
            t.bytes = r.bytes;
            t.busy_text = null;
            _ = w.PostMessageW(hwnd, MSG_ITEM, i, 0);
        },
        .clean => {
            var total: i64 = 0;
            postLog(u.fmt8("=== Bắt đầu dọn {d} mục", .{job.idx.len}));
            for (job.idx) |i| {
                const t = &tg.items[i];
                t.busy_text = L("Đang dọn…");
                _ = w.PostMessageW(hwnd, MSG_ITEM, i, 0);
                const r = c.clean(t, job.age, &postLog);
                total += r.bytes;
                var b: [32]u8 = undefined;
                postLog(u.fmt8("  {s}: xóa {d} file, {s}{s}", .{ u.U8(t.name), r.deleted, u.fmtSize(&b, r.bytes), if (r.skipped > 0) u.fmt8(" (bỏ qua {d} file đang dùng)", .{r.skipped}) else "" }));
                t.busy_text = null;
                _ = w.PostMessageW(hwnd, MSG_ITEM, i, 0);
            }
            var b: [32]u8 = undefined;
            postLog(u.fmt8("=== Xong. Đã xóa {s}", .{u.fmtSize(&b, total)}));
            _ = w.PostMessageW(hwnd, MSG_JOB_DONE, @intFromEnum(JobKind.clean), @bitCast(@as(isize, @intCast(total))));
            return 0;
        },
    }
    _ = w.PostMessageW(hwnd, MSG_JOB_DONE, @intFromEnum(job.kind), 0);
    return 0;
}

var last_clean_idx: []usize = &.{};

fn onJobDone(kind: JobKind, total: i64) void {
    clean_busy = false;
    switch (kind) {
        .discover => {},
        .scan => {},
        .clean => {
            refreshDisk();
            var b: [32]u8 = undefined;
            showToast(true, "Dọn dẹp xong", u.fmt8("Đã giải phóng {s}. Chi tiết ở tab Tự động & cài đặt.", .{u.fmtSize(&b, total)}));
            startJob(.scan, last_clean_idx);
        },
    }
    invalidate();
}

// ================================================================ uninstall queue
const AppDone = struct { idx: usize, ok: bool, removed: usize = 0, failed: usize = 0, bytes: i64 = 0 };

fn enqueue(i: usize) void {
    const a = &app_list[i];
    if (a.state != .idle and a.state != .failed) return;
    a.state = .queued;
    w.AcquireSRWLockExclusive(&q_lock);
    queue.append(gpa, i) catch u.oom();
    w.ReleaseSRWLockExclusive(&q_lock);
    if (!worker_running) {
        worker_running = true;
        spawn(&uninstallWorker, null);
    }
}

fn nextQueued() ?usize {
    w.AcquireSRWLockExclusive(&q_lock);
    defer w.ReleaseSRWLockExclusive(&q_lock);
    if (queue.items.len == 0) return null;
    return queue.orderedRemove(0);
}

fn postDone(d: AppDone) void {
    const p = gpa.create(AppDone) catch u.oom();
    p.* = d;
    _ = w.PostMessageW(hwnd, MSG_APP_DONE, 0, @bitCast(@intFromPtr(p)));
}

/// Uninstall -> wait until the Uninstall registry entry is gone -> remove exact-match leftovers.
fn uninstallWorker(_: ?*anyopaque) callconv(.winapi) w.DWORD {
    _ = w.CoInitializeEx(null, 0x2 | 0x4);
    while (nextQueued()) |i| {
        if (quitting.load(.monotonic)) break;
        const a = &app_list[i];
        a.state = .uninstalling;
        skip_current.store(false, .monotonic);
        _ = w.PostMessageW(hwnd, MSG_APP_UPDATE, 0, 0);
        u.log(u.fmt8("=== Gỡ cài đặt: {s}", .{u.U8(a.name)}));
        const st = apps.startUninstall(a) orelse {
            u.log("  Không mở được trình gỡ cài đặt (UAC bị hủy hoặc lệnh gỡ hỏng)");
            a.state = .failed;
            postDone(.{ .idx = i, .ok = false });
            continue;
        };
        if (st.proc) |proc| {
            while (w.WaitForSingleObject(proc, 300) != 0) {
                if (skip_current.load(.monotonic) or quitting.load(.monotonic)) break;
            }
            _ = w.CloseHandle(proc);
        }
        // Some uninstallers relaunch themselves from %TEMP% and return immediately.
        const limit: u32 = if (st.silent) 180 else 1800;
        var waited: u32 = 0;
        while (apps.keyExists(a) and waited < limit and !skip_current.load(.monotonic) and !quitting.load(.monotonic)) : (waited += 1) w.Sleep(1000);
        if (apps.keyExists(a)) {
            u.log("  Ứng dụng vẫn còn được cài, không dọn file sót.");
            a.state = .failed;
            postDone(.{ .idx = i, .ok = false });
            continue;
        }
        a.state = .cleaning;
        _ = w.PostMessageW(hwnd, MSG_APP_UPDATE, 0, 0);
        const left = apps.findLeftovers(a, app_list);
        const r = apps.removeLeftovers(left, a.name); // only exact-name matches are pre-checked
        for (left) |l| if (!l.checked) {
            u.log(u.fmt8("  Giữ lại (chỉ khớp một phần tên): {s}", .{u.U8(l.display)}));
        };
        a.state = .removed;
        postDone(.{ .idx = i, .ok = true, .removed = r.removed, .failed = r.failed, .bytes = r.bytes });
    }
    _ = w.PostMessageW(hwnd, MSG_QUEUE_IDLE, 0, 0);
    return 0;
}

fn spawn(f: w.THREADPROC, arg: ?*anyopaque) void {
    if (w.CreateThread(null, 0, f, arg, 0, null)) |h| _ = w.CloseHandle(h);
}

fn startClean() void {
    var idx: std.ArrayList(usize) = .empty;
    for (tg.items, 0..) |t, i| if (t.checked) {
        if (t.needs_admin and !u.is_admin) {
            logUi(u.fmt8("Bỏ qua (cần Admin): {s}", .{u.U8(t.name)}));
            continue;
        }
        idx.append(gpa, i) catch u.oom();
    };
    last_clean_idx = idx.toOwnedSlice(gpa) catch u.oom();
    startJob(.clean, last_clean_idx);
}

// ================================================================ actions
fn perform(a: Act) void {
    switch (a) {
        .none => {},
        .tab => |i| {
            tab = i;
            placeEdits();
        },
        .toggle => |i| {
            tg.items[i].checked = !tg.items[i].checked;
            saveSelection();
        },
        .scan => startJob(.discover, &.{}),
        .clean => startClean(),
        .admin => {
            const exe = u.exePath();
            const r = w.ShellExecuteW(hwnd, L("runas"), exe.ptr, null, null, w.SW_SHOWNORMAL);
            if (@intFromPtr(r) > 32) _ = w.DestroyWindow(hwnd);
        },
        .uninstall => |i| enqueue(i),
        .skip_wait => skip_current.store(true, .monotonic),
        .sort => |i| {
            sort_mode = i;
            rebuildView();
        },
        .sched => |i| settings.schedule = @enumFromInt(i),
        .time_minus, .time_plus => {
            var mins: i32 = @intCast(settings.hour * 60 + settings.minute);
            mins += if (a == .time_plus) 30 else -30;
            mins = @mod(mins, 24 * 60);
            settings.hour = @intCast(@divTrunc(mins, 60));
            settings.minute = @intCast(@mod(mins, 60));
        },
        .age_minus => settings.temp_age_days -|= 1,
        .age_plus => settings.temp_age_days = @min(settings.temp_age_days + 1, 365),
        .stale_minus => settings.stale_days = @max(settings.stale_days -| 5, 7),
        .stale_plus => settings.stale_days = @min(settings.stale_days + 5, 3650),
        .save_sched => {
            saveSelection();
            const r = scheduler.apply();
            logUi(r.msg);
            u.log(r.msg);
            showToast(r.ok, if (r.ok) "Đã lưu lịch" else "Không lưu được lịch", r.msg);
        },
        .open_log => _ = w.ShellExecuteW(hwnd, L("open"), u.log_path.ptr, null, null, w.SW_SHOWNORMAL),
        .toast_close => toast = null,
    }
    invalidate();
}

fn hitAt(px: f32, py: f32) Act {
    var i = hits.items.len;
    while (i > 0) {
        i -= 1;
        if (hits.items[i].r.has(px, py)) return hits.items[i].a;
    }
    return .none;
}

fn lpX(lp: w.LPARAM) f32 {
    const v: i16 = @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lp)))));
    return @as(f32, @floatFromInt(v)) / scale;
}
fn lpY(lp: w.LPARAM) f32 {
    const v: i16 = @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lp)) >> 16)));
    return @as(f32, @floatFromInt(v)) / scale;
}

// ================================================================ window procedure
fn wndProc(h: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        w.WM_PAINT => {
            paint();
            return 0;
        },
        w.WM_ERASEBKGND => return 1,
        w.WM_SIZE => {
            placeEdits();
            invalidate();
            return 0;
        },
        w.WM_GETMINMAXINFO => {
            const mmi: *w.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lp)));
            mmi.ptMinTrackSize = .{ .x = @intFromFloat(S(1000)), .y = @intFromFloat(S(720)) };
            return 0;
        },
        w.WM_DPICHANGED => {
            scale = @as(f32, @floatFromInt(w.hiword(wp))) / 96;
            const r: *const w.RECT = @ptrFromInt(@as(usize, @bitCast(lp)));
            makeFonts();
            _ = w.SetWindowPos(h, null, r.left, r.top, r.right - r.left, r.bottom - r.top, w.SWP_NOZORDER | w.SWP_NOACTIVATE);
            placeEdits();
            invalidate();
            return 0;
        },
        w.WM_MOUSEMOVE => {
            if (!mouse_tracking) {
                var tme: w.TRACKMOUSEEVENT = .{ .dwFlags = w.TME_LEAVE, .hwndTrack = h };
                _ = w.TrackMouseEvent(&tme);
                mouse_tracking = true;
            }
            const a = hitAt(lpX(lp), lpY(lp));
            if (!std.meta.eql(a, hover)) {
                hover = a;
                invalidate();
            }
            return 0;
        },
        w.WM_MOUSELEAVE => {
            mouse_tracking = false;
            if (hover != .none) {
                hover = .none;
                invalidate();
            }
            return 0;
        },
        w.WM_SETCURSOR => {
            if (w.loword(@bitCast(lp)) == w.HTCLIENT) {
                _ = w.SetCursor(w.LoadCursorW(null, if (hover != .none) w.IDC_HAND else w.IDC_ARROW));
                return 1;
            }
        },
        w.WM_LBUTTONDOWN => {
            pressed = hitAt(lpX(lp), lpY(lp));
            _ = w.SetCapture(h);
            _ = w.SetFocus(h);
            return 0;
        },
        w.WM_LBUTTONUP => {
            _ = w.ReleaseCapture();
            const a = hitAt(lpX(lp), lpY(lp));
            const p = pressed;
            pressed = .none;
            if (a != .none and std.meta.eql(a, p)) perform(a);
            return 0;
        },
        w.WM_MOUSEWHEEL => {
            var pt: w.POINT = .{ .x = @as(i16, @bitCast(w.loword(@bitCast(lp)))), .y = @as(i16, @bitCast(w.hiword(@bitCast(lp)))) };
            _ = w.ScreenToClient(h, &pt);
            const px = @as(f32, @floatFromInt(pt.x)) / scale;
            const py = @as(f32, @floatFromInt(pt.y)) / scale;
            const delta: f32 = @floatFromInt(@as(i16, @bitCast(w.hiword(wp))));
            var i = scroll_areas.items.len;
            while (i > 0) {
                i -= 1;
                const sa = scroll_areas.items[i];
                if (sa.r.has(px, py)) {
                    scroll[sa.idx] = std.math.clamp(scroll[sa.idx] - delta / 120 * 96, 0, scroll_max[sa.idx]);
                    invalidate();
                    break;
                }
            }
            return 0;
        },
        w.WM_TIMER => {
            if (toast) |t| if (w.GetTickCount64() > t.until) {
                toast = null;
                invalidate();
            };
            if (spinner_visible) invalidate();
            return 0;
        },
        w.WM_COMMAND => {
            if (w.loword(wp) == ID_SEARCH and w.hiword(wp) == w.EN_CHANGE) {
                rebuildView();
                invalidate();
            }
            return 0;
        },
        w.WM_CTLCOLOREDIT, w.WM_CTLCOLORSTATIC => {
            const hdc: w.HDC = @ptrFromInt(wp);
            _ = w.SetBkColor(hdc, colorRef(white));
            _ = w.SetTextColor(hdc, colorRef(if (@as(usize, @bitCast(lp)) == @intFromPtr(edit_log)) fg2 else fg));
            return @bitCast(@intFromPtr(white_brush.?));
        },
        MSG_LOG => {
            const p: [*:0]u16 = @ptrFromInt(@as(usize, @bitCast(lp)));
            const s = std.mem.span(p);
            logUi(u.U8(s));
            gpa.free(s);
            return 0;
        },
        MSG_ITEM => {
            invalidate();
            return 0;
        },
        MSG_DISCOVERED => {
            const found: *[]c.Target = @ptrFromInt(@as(usize, @bitCast(lp)));
            tg.shrinkRetainingCapacity(static_n);
            for (found.*) |t| {
                var x = t;
                x.checked = !settings.contains(settings.excluded, t.id);
                tg.append(gpa, x) catch u.oom();
            }
            applyLastUsed();
            rebuildView();
            clean_busy = false;
            startJob(.scan, allIndices());
            return 0;
        },
        MSG_JOB_DONE => {
            const kind: JobKind = @enumFromInt(wp);
            if (kind != .discover) onJobDone(kind, @intCast(lp));
            return 0;
        },
        MSG_APP_UPDATE => {
            invalidate();
            return 0;
        },
        MSG_APP_DONE => {
            const d: *AppDone = @ptrFromInt(@as(usize, @bitCast(lp)));
            defer gpa.destroy(d);
            const name8 = u.U8(app_list[d.idx].name);
            if (d.ok) {
                var b: [32]u8 = undefined;
                const desc = if (d.failed > 0)
                    u.fmt8("Dọn {d} mục còn sót ({s}). {d} mục cần quyền Admin nên chưa xóa được.", .{ d.removed, u.fmtSize(&b, d.bytes), d.failed })
                else
                    u.fmt8("Dọn {d} mục còn sót ({s}) vào Thùng rác.", .{ d.removed, u.fmtSize(&b, d.bytes) });
                logUi(u.fmt8("Đã gỡ {s}: {s}", .{ name8, desc }));
                showToast(true, u.fmt8("Đã gỡ {s}", .{name8}), desc);
            } else {
                logUi(u.fmt8("Chưa gỡ được {s}", .{name8}));
                showToast(false, u.fmt8("Chưa gỡ được {s}", .{name8}), "Trình gỡ bị hủy, cần quyền Admin, hoặc đang chờ bạn thao tác. Không có file nào bị xóa.");
            }
            invalidate();
            return 0;
        },
        MSG_QUEUE_IDLE => {
            worker_running = false;
            // A click may have queued an app right as the worker exited.
            w.AcquireSRWLockExclusive(&q_lock);
            const pending = queue.items.len > 0;
            w.ReleaseSRWLockExclusive(&q_lock);
            if (pending) {
                worker_running = true;
                spawn(&uninstallWorker, null);
            } else {
                reloadApps();
                refreshDisk();
                invalidate();
            }
            return 0;
        },
        w.WM_DESTROY => {
            c.cancel.store(true, .monotonic);
            quitting.store(true, .monotonic);
            w.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return w.DefWindowProcW(h, msg, wp, lp);
}

// ================================================================ entry
pub fn run() void {
    const icc: w.INITCOMMONCONTROLSEX = .{ .dwICC = w.ICC_STANDARD_CLASSES };
    _ = w.InitCommonControlsEx(&icc);
    var token: usize = 0;
    _ = w.GdiplusStartup(&token, &.{}, null);
    hinst = w.GetModuleHandleW(null);
    white_brush = w.CreateSolidBrush(colorRef(white));

    const cls = L("JunkCleanerZig");
    const wc: w.WNDCLASSEXW = .{
        .lpfnWndProc = &wndProc,
        .hInstance = hinst,
        .hCursor = w.LoadCursorW(null, w.IDC_ARROW),
        .hIcon = w.LoadIconW(null, w.IDI_APPLICATION),
        .lpszClassName = cls,
    };
    _ = w.RegisterClassExW(&wc);

    scale = @as(f32, @floatFromInt(w.GetDpiForSystem())) / 96;
    const ww: i32 = @intFromFloat(S(1120));
    const wh: i32 = @intFromFloat(S(820));
    const sx = @max(0, @divTrunc(w.GetSystemMetrics(w.SM_CXSCREEN) - ww, 2));
    const sy = @max(0, @divTrunc(w.GetSystemMetrics(w.SM_CYSCREEN) - wh, 2));
    const title = if (u.is_admin) L("Junk Cleaner [Admin]") else L("Junk Cleaner");
    hwnd = w.CreateWindowExW(0, cls, title, w.WS_OVERLAPPEDWINDOW | w.WS_CLIPCHILDREN, sx, sy, ww, wh, null, null, hinst, null) orelse return;
    scale = @as(f32, @floatFromInt(w.GetDpiForWindow(hwnd))) / 96;

    // Light title bar matching the page colour (Windows 11; ignored elsewhere).
    const caption: w.DWORD = colorRef(page);
    _ = w.DwmSetWindowAttribute(hwnd, 35, &caption, 4);
    const corner: w.DWORD = 2;
    _ = w.DwmSetWindowAttribute(hwnd, 33, &corner, 4);

    edit_search = w.CreateWindowExW(0, L("EDIT"), L(""), w.WS_CHILD | w.WS_TABSTOP | 0x80, 0, 0, 10, 10, hwnd, @ptrFromInt(ID_SEARCH), hinst, null).?;
    _ = w.SendMessageW(edit_search, w.EM_SETCUEBANNER, 1, @bitCast(@intFromPtr(L("Tìm ứng dụng…"))));
    edit_log = w.CreateWindowExW(0, L("EDIT"), L(""), w.WS_CHILD | w.ES_MULTILINE | w.ES_AUTOVSCROLL | w.ES_READONLY, 0, 0, 10, 10, hwnd, @ptrFromInt(ID_LOG), hinst, null).?;
    _ = w.SendMessageW(edit_log, w.EM_SETLIMITTEXT, 0, 0);
    ready = true;
    makeFonts();

    // data
    const st = c.staticTargets();
    for (st) |t| {
        var x = t;
        x.checked = if (settings.selected) |sel| settings.contains(sel, t.id) else t.default_on;
        tg.append(gpa, x) catch u.oom();
    }
    static_n = tg.items.len;
    app_list = apps.list();
    rebuildView();
    refreshDisk();
    if (!u.is_admin) logUi("Đang chạy không có quyền Admin: các mục gắn nhãn Admin sẽ bị bỏ qua khi dọn.");

    placeEdits();
    _ = w.ShowWindow(hwnd, w.SW_SHOW);
    _ = w.UpdateWindow(hwnd);
    _ = w.SetTimer(hwnd, 1, 50, null);
    startJob(.discover, &.{});

    var msg: w.MSG = .{};
    while (w.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }
}
