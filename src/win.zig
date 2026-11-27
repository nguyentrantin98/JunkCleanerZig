//! Minimal hand-written Win32 bindings (only what this app uses).
//! Kept independent from std.os.windows so the app survives Zig std churn.

pub const BOOL = i32;
pub const UINT = u32;
pub const DWORD = u32;
pub const WORD = u16;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const HRESULT = i32;
pub const LPCWSTR = [*:0]const u16;
pub const LPWSTR = [*:0]u16;

pub const HWND = *opaque {};
pub const HINSTANCE = *opaque {};
pub const HMENU = *opaque {};
pub const HFONT = *opaque {};
pub const HBRUSH = *opaque {};
pub const HICON = *opaque {};
pub const HCURSOR = *opaque {};
pub const HKEY = *opaque {};
pub const HGDIOBJ = *opaque {};
pub const HANDLE = *anyopaque;

pub const INVALID_HANDLE: HANDLE = @ptrFromInt(~@as(usize, 0));
pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub const THREADPROC = *const fn (?*anyopaque) callconv(.winapi) DWORD;

pub const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
pub const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
pub const FILETIME = extern struct { lo: u32 = 0, hi: u32 = 0 };
pub const SYSTEMTIME = extern struct {
    wYear: u16 = 0, wMonth: u16 = 0, wDayOfWeek: u16 = 0, wDay: u16 = 0,
    wHour: u16 = 0, wMinute: u16 = 0, wSecond: u16 = 0, wMilliseconds: u16 = 0,
};
pub const SRWLOCK = extern struct { ptr: ?*anyopaque = null };

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: ?HICON = null,
};

pub const MSG = extern struct {
    hwnd: ?HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
    lPrivate: DWORD = 0,
};

pub const MINMAXINFO = extern struct {
    ptReserved: POINT, ptMaxSize: POINT, ptMaxPosition: POINT, ptMinTrackSize: POINT, ptMaxTrackSize: POINT,
};

pub const NMHDR = extern struct { hwndFrom: ?HWND, idFrom: usize, code: UINT };

pub const NMLISTVIEW = extern struct {
    hdr: NMHDR,
    iItem: i32,
    iSubItem: i32,
    uNewState: UINT,
    uOldState: UINT,
    uChanged: UINT,
    ptAction: POINT,
    lParam: LPARAM,
};

pub const LVCOLUMNW = extern struct {
    mask: UINT = 0,
    fmt: i32 = 0,
    cx: i32 = 0,
    pszText: ?LPCWSTR = null,
    cchTextMax: i32 = 0,
    iSubItem: i32 = 0,
    iImage: i32 = 0,
    iOrder: i32 = 0,
    cxMin: i32 = 0,
    cxDefault: i32 = 0,
    cxIdeal: i32 = 0,
};

pub const LVITEMW = extern struct {
    mask: UINT = 0,
    iItem: i32 = 0,
    iSubItem: i32 = 0,
    state: UINT = 0,
    stateMask: UINT = 0,
    pszText: ?LPCWSTR = null,
    cchTextMax: i32 = 0,
    iImage: i32 = 0,
    lParam: LPARAM = 0,
    iIndent: i32 = 0,
    iGroupId: i32 = 0,
    cColumns: UINT = 0,
    puColumns: ?*UINT = null,
    piColFmt: ?*i32 = null,
    iGroup: i32 = 0,
};

pub const LVGROUP = extern struct {
    cbSize: UINT = @sizeOf(LVGROUP),
    mask: UINT = 0,
    pszHeader: ?LPCWSTR = null,
    cchHeader: i32 = 0,
    pszFooter: ?LPCWSTR = null,
    cchFooter: i32 = 0,
    iGroupId: i32 = 0,
    stateMask: UINT = 0,
    state: UINT = 0,
    uAlign: UINT = 0,
    pszSubtitle: ?LPCWSTR = null,
    cchSubtitle: UINT = 0,
    pszTask: ?LPCWSTR = null,
    cchTask: UINT = 0,
    pszDescriptionTop: ?LPCWSTR = null,
    cchDescriptionTop: UINT = 0,
    pszDescriptionBottom: ?LPCWSTR = null,
    cchDescriptionBottom: UINT = 0,
    iTitleImage: i32 = 0,
    iExtendedImage: i32 = 0,
    iFirstItem: i32 = 0,
    cItems: UINT = 0,
    pszSubsetTitle: ?LPCWSTR = null,
    cchSubsetTitle: UINT = 0,
};

pub const INITCOMMONCONTROLSEX = extern struct { dwSize: DWORD = @sizeOf(INITCOMMONCONTROLSEX), dwICC: DWORD };

pub const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: DWORD,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    nFileSizeHigh: DWORD,
    nFileSizeLow: DWORD,
    dwReserved0: DWORD,
    dwReserved1: DWORD,
    cFileName: [260]u16,
    cAlternateFileName: [14]u16,
};

pub const SHQUERYRBINFO = extern struct { cbSize: DWORD = @sizeOf(SHQUERYRBINFO), i64Size: i64 = 0, i64NumItems: i64 = 0 };

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD = @sizeOf(SECURITY_ATTRIBUTES),
    lpSecurityDescriptor: ?*anyopaque = null,
    bInheritHandle: BOOL = 0,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD = @sizeOf(STARTUPINFOW),
    lpReserved: ?LPWSTR = null,
    lpDesktop: ?LPWSTR = null,
    lpTitle: ?LPWSTR = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: WORD = 0,
    cbReserved2: WORD = 0,
    lpReserved2: ?*u8 = null,
    hStdInput: ?HANDLE = null,
    hStdOutput: ?HANDLE = null,
    hStdError: ?HANDLE = null,
};

pub const PROCESS_INFORMATION = extern struct {
    hProcess: ?HANDLE = null,
    hThread: ?HANDLE = null,
    dwProcessId: DWORD = 0,
    dwThreadId: DWORD = 0,
};

// ---------------------------------------------------------------- constants
pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_TABSTOP: DWORD = 0x00010000;
pub const WS_GROUP: DWORD = 0x00020000;
pub const WS_VSCROLL: DWORD = 0x00200000;
pub const WS_CLIPCHILDREN: DWORD = 0x02000000;
pub const WS_EX_CLIENTEDGE: DWORD = 0x200;
pub const WS_EX_CONTROLPARENT: DWORD = 0x10000;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_GETMINMAXINFO: UINT = 0x0024;
pub const WM_SETFONT: UINT = 0x0030;
pub const WM_NOTIFY: UINT = 0x004E;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_DPICHANGED: UINT = 0x02E0;
pub const WM_USER: UINT = 0x0400;
pub const WM_APP: UINT = 0x8000;

pub const SW_HIDE: i32 = 0;
pub const SW_SHOWNORMAL: i32 = 1;
pub const SW_SHOW: i32 = 5;
pub const COLOR_BTNFACE: usize = 15;
pub const IDC_ARROW: usize = 32512;
pub const IDI_APPLICATION: usize = 32512;
pub const SWP_NOZORDER: UINT = 0x4;
pub const SWP_NOACTIVATE: UINT = 0x10;

pub const MB_OK: UINT = 0;
pub const MB_YESNO: UINT = 4;
pub const MB_ICONQUESTION: UINT = 0x20;
pub const MB_ICONWARNING: UINT = 0x30;
pub const MB_ICONINFORMATION: UINT = 0x40;
pub const IDYES: i32 = 6;

pub const BS_GROUPBOX: DWORD = 7;
pub const BN_CLICKED: u16 = 0;
pub const SS_RIGHT: DWORD = 2;
pub const SS_CENTERIMAGE: DWORD = 0x200;
pub const ES_MULTILINE: DWORD = 0x4;
pub const ES_AUTOVSCROLL: DWORD = 0x40;
pub const ES_READONLY: DWORD = 0x800;
pub const ES_NUMBER: DWORD = 0x2000;
pub const EN_CHANGE: u16 = 0x300;
pub const EM_SETSEL: UINT = 0xB1;
pub const EM_REPLACESEL: UINT = 0xC2;
pub const EM_SETLIMITTEXT: UINT = 0xC5;
pub const CBS_DROPDOWNLIST: DWORD = 3;
pub const CB_ADDSTRING: UINT = 0x143;
pub const CB_GETCURSEL: UINT = 0x147;
pub const CB_SETCURSEL: UINT = 0x14E;
pub const CBN_SELCHANGE: u16 = 1;

pub const ICC_LISTVIEW_CLASSES: DWORD = 0x1;
pub const ICC_UPDOWN_CLASS: DWORD = 0x10;
pub const ICC_PROGRESS_CLASS: DWORD = 0x20;
pub const ICC_DATE_CLASSES: DWORD = 0x100;
pub const ICC_STANDARD_CLASSES: DWORD = 0x4000;

pub const PBM_SETPOS: UINT = WM_USER + 2;
pub const UDS_SETBUDDYINT: DWORD = 0x2;
pub const UDS_ARROWKEYS: DWORD = 0x20;
pub const UDS_NOTHOUSANDS: DWORD = 0x80;
pub const UDM_SETBUDDY: UINT = WM_USER + 105;
pub const UDM_SETRANGE32: UINT = WM_USER + 111;
pub const UDM_SETPOS32: UINT = WM_USER + 113;
pub const UDM_GETPOS32: UINT = WM_USER + 114;
pub const DTS_TIMEFORMAT: DWORD = 0x9;
pub const DTM_GETSYSTEMTIME: UINT = 0x1001;
pub const DTM_SETSYSTEMTIME: UINT = 0x1002;
pub const DTM_SETFORMATW: UINT = 0x1032;
pub const GDT_VALID: WPARAM = 0;

pub const LVS_REPORT: DWORD = 0x1;
pub const LVS_SINGLESEL: DWORD = 0x4;
pub const LVS_SHOWSELALWAYS: DWORD = 0x8;
pub const LVS_NOSORTHEADER: DWORD = 0x8000;
pub const LVS_EX_CHECKBOXES: DWORD = 0x4;
pub const LVS_EX_FULLROWSELECT: DWORD = 0x20;
pub const LVS_EX_DOUBLEBUFFER: DWORD = 0x10000;
pub const LVM_FIRST: UINT = 0x1000;
pub const LVM_DELETEALLITEMS: UINT = LVM_FIRST + 9;
pub const LVM_SETCOLUMNWIDTH: UINT = LVM_FIRST + 30;
pub const LVM_SETITEMSTATE: UINT = LVM_FIRST + 43;
pub const LVM_SETEXTENDEDLISTVIEWSTYLE: UINT = LVM_FIRST + 54;
pub const LVM_INSERTITEMW: UINT = LVM_FIRST + 77;
pub const LVM_INSERTCOLUMNW: UINT = LVM_FIRST + 97;
pub const LVM_SETITEMTEXTW: UINT = LVM_FIRST + 116;
pub const LVM_INSERTGROUP: UINT = LVM_FIRST + 145;
pub const LVM_ENABLEGROUPVIEW: UINT = LVM_FIRST + 157;
pub const LVIF_TEXT: UINT = 0x1;
pub const LVIF_PARAM: UINT = 0x4;
pub const LVIF_STATE: UINT = 0x8;
pub const LVIF_GROUPID: UINT = 0x100;
pub const LVIS_STATEIMAGEMASK: UINT = 0xF000;
pub const LVCF_FMT: UINT = 0x1;
pub const LVCF_WIDTH: UINT = 0x2;
pub const LVCF_TEXT: UINT = 0x4;
pub const LVCFMT_RIGHT: i32 = 1;
pub const LVGF_HEADER: UINT = 0x1;
pub const LVGF_GROUPID: UINT = 0x10;
pub const LVN_ITEMCHANGED: UINT = @bitCast(@as(i32, -101));

pub const FILE_ATTRIBUTE_READONLY: DWORD = 0x1;
pub const FILE_ATTRIBUTE_DIRECTORY: DWORD = 0x10;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
pub const FILE_ATTRIBUTE_REPARSE_POINT: DWORD = 0x400;
pub const INVALID_FILE_ATTRIBUTES: DWORD = 0xFFFFFFFF;
pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const FILE_APPEND_DATA: DWORD = 0x4;
pub const FILE_SHARE_READ: DWORD = 0x1;
pub const FILE_SHARE_WRITE: DWORD = 0x2;
pub const CREATE_ALWAYS: DWORD = 2;
pub const OPEN_EXISTING: DWORD = 3;
pub const OPEN_ALWAYS: DWORD = 4;
pub const FindExInfoBasic: i32 = 1;
pub const FIND_FIRST_EX_LARGE_FETCH: DWORD = 2;

pub const STARTF_USESTDHANDLES: DWORD = 0x100;
pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
pub const HANDLE_FLAG_INHERIT: DWORD = 1;
pub const INFINITE: DWORD = 0xFFFFFFFF;
pub const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
pub const ATTACH_PARENT_PROCESS: DWORD = 0xFFFFFFFF;
pub const FILE_TYPE_CHAR: DWORD = 2;
pub const CP_OEMCP: UINT = 1;

pub const KEY_SET_VALUE: DWORD = 0x2;
pub const REG_SZ: DWORD = 1;

// ---------------------------------------------------------------- user32
pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
pub extern "user32" fn CreateWindowExW(ex: DWORD, class: LPCWSTR, title: LPCWSTR, style: DWORD, x: i32, y: i32, w: i32, h: i32, parent: ?HWND, menu: ?HMENU, inst: ?HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?HWND;
pub extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn GetMessageW(*MSG, ?HWND, UINT, UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn IsDialogMessageW(HWND, *MSG) callconv(.winapi) BOOL;
pub extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
pub extern "user32" fn SendMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn PostMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(HWND) callconv(.winapi) BOOL;
pub extern "user32" fn MoveWindow(HWND, i32, i32, i32, i32, BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(HWND, ?HWND, i32, i32, i32, i32, UINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(HWND, *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowTextW(HWND, LPCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowTextLengthW(HWND) callconv(.winapi) i32;
pub extern "user32" fn EnableWindow(HWND, BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn MessageBoxW(?HWND, LPCWSTR, LPCWSTR, UINT) callconv(.winapi) i32;
pub extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn LoadIconW(?HINSTANCE, usize) callconv(.winapi) ?HICON;
pub extern "user32" fn GetDpiForWindow(HWND) callconv(.winapi) UINT;
pub extern "user32" fn DestroyWindow(HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetSysColorBrush(i32) callconv(.winapi) ?HBRUSH;

// ---------------------------------------------------------------- gdi32 / comctl32
pub extern "gdi32" fn CreateFontW(h: i32, w: i32, esc: i32, orient: i32, weight: i32, italic: DWORD, underline: DWORD, strike: DWORD, charset: DWORD, outp: DWORD, clip: DWORD, quality: DWORD, pitch: DWORD, face: LPCWSTR) callconv(.winapi) ?HFONT;
pub extern "gdi32" fn DeleteObject(HGDIOBJ) callconv(.winapi) BOOL;
pub extern "comctl32" fn InitCommonControlsEx(*const INITCOMMONCONTROLSEX) callconv(.winapi) BOOL;

// ---------------------------------------------------------------- kernel32
pub extern "kernel32" fn GetModuleHandleW(?LPCWSTR) callconv(.winapi) ?HINSTANCE;
pub extern "kernel32" fn GetModuleFileNameW(?HINSTANCE, [*]u16, DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetCommandLineW() callconv(.winapi) LPWSTR;
pub extern "kernel32" fn GetEnvironmentVariableW(LPCWSTR, ?[*]u16, DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetTempPathW(DWORD, [*]u16) callconv(.winapi) DWORD;
pub extern "kernel32" fn FindFirstFileExW(LPCWSTR, i32, *WIN32_FIND_DATAW, i32, ?*anyopaque, DWORD) callconv(.winapi) HANDLE;
pub extern "kernel32" fn FindNextFileW(HANDLE, *WIN32_FIND_DATAW) callconv(.winapi) BOOL;
pub extern "kernel32" fn FindClose(HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileAttributesW(LPCWSTR) callconv(.winapi) DWORD;
pub extern "kernel32" fn SetFileAttributesW(LPCWSTR, DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn DeleteFileW(LPCWSTR) callconv(.winapi) BOOL;
pub extern "kernel32" fn RemoveDirectoryW(LPCWSTR) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateDirectoryW(LPCWSTR, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateFileW(LPCWSTR, DWORD, DWORD, ?*anyopaque, DWORD, DWORD, ?HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn ReadFile(HANDLE, [*]u8, DWORD, ?*DWORD, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn WriteFile(HANDLE, [*]const u8, DWORD, ?*DWORD, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileSizeEx(HANDLE, *i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetSystemTimeAsFileTime(*FILETIME) callconv(.winapi) void;
pub extern "kernel32" fn FileTimeToSystemTime(*const FILETIME, *SYSTEMTIME) callconv(.winapi) BOOL;
pub extern "kernel32" fn SystemTimeToTzSpecificLocalTime(?*anyopaque, *const SYSTEMTIME, *SYSTEMTIME) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetLocalTime(*SYSTEMTIME) callconv(.winapi) void;
pub extern "kernel32" fn GetDiskFreeSpaceExW(LPCWSTR, ?*u64, ?*u64, ?*u64) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateThread(?*anyopaque, usize, THREADPROC, ?*anyopaque, DWORD, ?*DWORD) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn WaitForSingleObject(HANDLE, DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateProcessW(?LPCWSTR, ?LPWSTR, ?*anyopaque, ?*anyopaque, BOOL, DWORD, ?*anyopaque, ?LPCWSTR, *STARTUPINFOW, *PROCESS_INFORMATION) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetExitCodeProcess(HANDLE, *DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreatePipe(*HANDLE, *HANDLE, ?*SECURITY_ATTRIBUTES, DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn SetHandleInformation(HANDLE, DWORD, DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetStdHandle(DWORD) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn AttachConsole(DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileType(HANDLE) callconv(.winapi) DWORD;
pub extern "kernel32" fn WriteConsoleW(HANDLE, [*]const u16, DWORD, ?*DWORD, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn MultiByteToWideChar(UINT, DWORD, [*]const u8, i32, ?[*]u16, i32) callconv(.winapi) i32;
pub extern "kernel32" fn LocalFree(?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn AcquireSRWLockExclusive(*SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn ReleaseSRWLockExclusive(*SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn ExitProcess(UINT) callconv(.winapi) noreturn;

// ---------------------------------------------------------------- shell32 / advapi32
pub extern "shell32" fn CommandLineToArgvW(LPCWSTR, *i32) callconv(.winapi) ?[*]LPWSTR;
pub extern "shell32" fn SHQueryRecycleBinW(?LPCWSTR, *SHQUERYRBINFO) callconv(.winapi) HRESULT;
pub extern "shell32" fn SHEmptyRecycleBinW(?HWND, ?LPCWSTR, DWORD) callconv(.winapi) HRESULT;
pub extern "shell32" fn ShellExecuteW(?HWND, ?LPCWSTR, LPCWSTR, ?LPCWSTR, ?LPCWSTR, i32) callconv(.winapi) ?HINSTANCE;
pub extern "shell32" fn IsUserAnAdmin() callconv(.winapi) BOOL;
pub extern "advapi32" fn RegCreateKeyExW(HKEY, LPCWSTR, DWORD, ?LPWSTR, DWORD, DWORD, ?*anyopaque, *?HKEY, ?*DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegOpenKeyExW(HKEY, LPCWSTR, DWORD, DWORD, *?HKEY) callconv(.winapi) i32;
pub extern "advapi32" fn RegSetValueExW(HKEY, LPCWSTR, DWORD, DWORD, [*]const u8, DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegDeleteValueW(HKEY, LPCWSTR) callconv(.winapi) i32;
pub extern "advapi32" fn RegCloseKey(HKEY) callconv(.winapi) i32;

pub inline fn loword(x: usize) u16 {
    return @truncate(x);
}
pub inline fn hiword(x: usize) u16 {
    return @truncate(x >> 16);
}

// ---------------------------------------------------------------- registry / shell (apps tab)
pub const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(0x80000002);
pub const KEY_READ: DWORD = 0x20019;
pub const KEY_ALL_ACCESS: DWORD = 0xF003F;
pub const KEY_WOW64_64KEY: DWORD = 0x100;
pub const KEY_WOW64_32KEY: DWORD = 0x200;
pub const RRF_RT_REG_SZ: DWORD = 0x2;
pub const RRF_RT_DWORD: DWORD = 0x18;
pub extern "advapi32" fn RegEnumKeyExW(HKEY, DWORD, [*]u16, *DWORD, ?*DWORD, ?[*]u16, ?*DWORD, ?*FILETIME) callconv(.winapi) i32;
pub extern "advapi32" fn RegGetValueW(HKEY, ?LPCWSTR, ?LPCWSTR, DWORD, ?*DWORD, ?*anyopaque, ?*DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegDeleteTreeW(HKEY, ?LPCWSTR) callconv(.winapi) i32;

pub const SHELLEXECUTEINFOW = extern struct {
    cbSize: DWORD = @sizeOf(SHELLEXECUTEINFOW),
    fMask: DWORD = 0,
    hwnd: ?HWND = null,
    lpVerb: ?LPCWSTR = null,
    lpFile: LPCWSTR,
    lpParameters: ?LPCWSTR = null,
    lpDirectory: ?LPCWSTR = null,
    nShow: i32 = SW_SHOWNORMAL,
    hInstApp: ?HINSTANCE = null,
    lpIDList: ?*anyopaque = null,
    lpClass: ?LPCWSTR = null,
    hkeyClass: ?HKEY = null,
    dwHotKey: DWORD = 0,
    hIconOrMonitor: ?HANDLE = null,
    hProcess: ?HANDLE = null,
};
pub const SEE_MASK_NOCLOSEPROCESS: DWORD = 0x40;
pub extern "shell32" fn ShellExecuteExW(*SHELLEXECUTEINFOW) callconv(.winapi) BOOL;

pub const SHFILEOPSTRUCTW = extern struct {
    hwnd: ?HWND = null,
    wFunc: UINT,
    pFrom: [*]const u16,
    pTo: ?[*]const u16 = null,
    fFlags: u16 = 0,
    fAnyOperationsAborted: BOOL = 0,
    hNameMappings: ?*anyopaque = null,
    lpszProgressTitle: ?LPCWSTR = null,
};
pub const FO_DELETE: UINT = 3;
pub const FOF_SILENT: u16 = 0x4;
pub const FOF_NOCONFIRMATION: u16 = 0x10;
pub const FOF_ALLOWUNDO: u16 = 0x40;
pub const FOF_NOERRORUI: u16 = 0x400;
pub extern "shell32" fn SHFileOperationW(*SHFILEOPSTRUCTW) callconv(.winapi) i32;
pub extern "shell32" fn SHDefExtractIconW(LPCWSTR, i32, UINT, ?*?HICON, ?*?HICON, UINT) callconv(.winapi) HRESULT;
pub extern "user32" fn DestroyIcon(HICON) callconv(.winapi) BOOL;
pub extern "kernel32" fn Sleep(DWORD) callconv(.winapi) void;

// ---------------------------------------------------------------- painting / input (custom-drawn UI)
pub const HDC = *opaque {};
pub const HBITMAP = *opaque {};
pub const SIZE = extern struct { cx: i32 = 0, cy: i32 = 0 };
pub const PAINTSTRUCT = extern struct {
    hdc: ?HDC = null,
    fErase: BOOL = 0,
    rcPaint: RECT = .{},
    fRestore: BOOL = 0,
    fIncUpdate: BOOL = 0,
    rgbReserved: [32]u8 = @splat(0),
};
pub const TRACKMOUSEEVENT = extern struct {
    cbSize: DWORD = @sizeOf(TRACKMOUSEEVENT),
    dwFlags: DWORD = 0,
    hwndTrack: ?HWND = null,
    dwHoverTime: DWORD = 0,
};
pub const WM_SETCURSOR: UINT = 0x0020;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_TIMER: UINT = 0x0113;
pub const WM_CTLCOLOREDIT: UINT = 0x0133;
pub const WM_CTLCOLORSTATIC: UINT = 0x0138;
pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_MOUSEWHEEL: UINT = 0x020A;
pub const WM_MOUSELEAVE: UINT = 0x02A3;
pub const TME_LEAVE: DWORD = 0x2;
pub const HTCLIENT: u16 = 1;
pub const IDC_HAND: usize = 32649;
pub const VK_ESCAPE: WPARAM = 0x1B;
pub const SRCCOPY: DWORD = 0x00CC0020;
pub const TRANSPARENT: i32 = 1;
pub const DT_CENTER: UINT = 0x1;
pub const DT_RIGHT: UINT = 0x2;
pub const DT_VCENTER: UINT = 0x4;
pub const DT_WORDBREAK: UINT = 0x10;
pub const DT_SINGLELINE: UINT = 0x20;
pub const DT_NOPREFIX: UINT = 0x800;
pub const DT_END_ELLIPSIS: UINT = 0x8000;
pub const DT_PATH_ELLIPSIS: UINT = 0x4000;
pub const DT_CALCRECT: UINT = 0x400;
pub const EM_SETCUEBANNER: UINT = 0x1501;
pub const EM_SETMARGINS: UINT = 0xD3;
pub const SM_CXSCREEN: i32 = 0;
pub const SM_CYSCREEN: i32 = 1;

pub extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.winapi) ?HDC;
pub extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn InvalidateRect(HWND, ?*const RECT, BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn DrawTextW(HDC, [*]const u16, i32, *RECT, UINT) callconv(.winapi) i32;
pub extern "user32" fn TrackMouseEvent(*TRACKMOUSEEVENT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCursor(?HCURSOR) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn SetTimer(HWND, usize, UINT, ?*anyopaque) callconv(.winapi) usize;
pub extern "user32" fn KillTimer(HWND, usize) callconv(.winapi) BOOL;
pub extern "user32" fn SetCapture(HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
pub extern "user32" fn ScreenToClient(HWND, *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetFocus(?HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn GetWindowTextW(HWND, [*]u16, i32) callconv(.winapi) i32;
pub extern "user32" fn GetSystemMetrics(i32) callconv(.winapi) i32;
pub extern "user32" fn GetDpiForSystem() callconv(.winapi) UINT;
pub extern "user32" fn DrawIconEx(HDC, i32, i32, HICON, i32, i32, UINT, ?HBRUSH, UINT) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateCompatibleDC(?HDC) callconv(.winapi) ?HDC;
pub extern "gdi32" fn CreateCompatibleBitmap(HDC, i32, i32) callconv(.winapi) ?HBITMAP;
pub extern "gdi32" fn SelectObject(HDC, *anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn BitBlt(HDC, i32, i32, i32, i32, HDC, i32, i32, DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn DeleteDC(HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn SetBkMode(HDC, i32) callconv(.winapi) i32;
pub extern "gdi32" fn SetBkColor(HDC, DWORD) callconv(.winapi) DWORD;
pub extern "gdi32" fn SetTextColor(HDC, DWORD) callconv(.winapi) DWORD;
pub extern "gdi32" fn GetTextExtentPoint32W(HDC, [*]const u16, i32, *SIZE) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateSolidBrush(DWORD) callconv(.winapi) ?HBRUSH;
pub extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
pub extern "dwmapi" fn DwmSetWindowAttribute(HWND, DWORD, *const anyopaque, DWORD) callconv(.winapi) HRESULT;

// ---------------------------------------------------------------- GDI+ flat API (anti-aliased shapes)
pub const GpGraphics = opaque {};
pub const GpBrush = opaque {};
pub const GpPen = opaque {};
pub const GpPath = opaque {};
pub const GdiplusStartupInput = extern struct {
    GdiplusVersion: u32 = 1,
    DebugEventCallback: ?*anyopaque = null,
    SuppressBackgroundThread: BOOL = 0,
    SuppressExternalCodecs: BOOL = 0,
};
pub extern "gdiplus" fn GdiplusStartup(*usize, *const GdiplusStartupInput, ?*anyopaque) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipCreateFromHDC(HDC, *?*GpGraphics) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDeleteGraphics(*GpGraphics) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipFlush(*GpGraphics, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipSetSmoothingMode(*GpGraphics, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipSetPixelOffsetMode(*GpGraphics, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipCreateSolidFill(u32, *?*GpBrush) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDeleteBrush(*GpBrush) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipCreatePen1(u32, f32, i32, *?*GpPen) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDeletePen(*GpPen) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipSetPenStartCap(*GpPen, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipSetPenEndCap(*GpPen, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipSetPenLineJoin(*GpPen, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipCreatePath(i32, *?*GpPath) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDeletePath(*GpPath) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipAddPathArc(*GpPath, f32, f32, f32, f32, f32, f32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipClosePathFigure(*GpPath) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipFillPath(*GpGraphics, *GpBrush, *GpPath) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDrawPath(*GpGraphics, *GpPen, *GpPath) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipFillRectangle(*GpGraphics, *GpBrush, f32, f32, f32, f32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipFillEllipse(*GpGraphics, *GpBrush, f32, f32, f32, f32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDrawLine(*GpGraphics, *GpPen, f32, f32, f32, f32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDrawArc(*GpGraphics, *GpPen, f32, f32, f32, f32, f32, f32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipDrawEllipse(*GpGraphics, *GpPen, f32, f32, f32, f32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipSetClipRect(*GpGraphics, f32, f32, f32, f32, i32) callconv(.winapi) i32;
pub extern "gdiplus" fn GdipResetClip(*GpGraphics) callconv(.winapi) i32;
pub extern "gdi32" fn IntersectClipRect(HDC, i32, i32, i32, i32) callconv(.winapi) i32;
pub extern "gdi32" fn SelectClipRgn(HDC, ?*anyopaque) callconv(.winapi) i32;
pub extern "ole32" fn CoInitializeEx(?*anyopaque, DWORD) callconv(.winapi) HRESULT;
