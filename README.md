# JunkCleaner

A small, native Windows disk cleaner and app uninstaller written in [Zig](https://ziglang.org/). It's a single executable with a Win32/GDI+ GUI and no runtime dependencies.

> The user interface is in Vietnamese.

## Features

- **System cleanup:** user and Windows temp files (older than N days), the Windows Update download cache, the Delivery Optimization cache, crash dumps and WER reports, old Windows logs, the thumbnail and icon cache, the Recycle Bin, and an optional WinSxS cleanup through DISM.
- **Browser caches:** Chrome, Edge, Cốc Cốc, Brave, Opera and Firefox. It removes caches only and never touches passwords, history or cookies.
- **Developer caches:** npm, Yarn, NuGet (HTTP cache and packages), pip, VS Code and Gradle.
- **Stale apps:** it finds apps whose AppData folders haven't been written for N days and offers to clear only their cache folders.
- **Uninstaller:** it lists installed apps from the registry, runs their (silent, where possible) uninstaller, then scans for leftover folders, files and registry keys.
- **Scheduled cleanup:** it can run `--auto` daily, weekly or at logon through Task Scheduler (or the HKCU `Run` key when not elevated).

Items that need administrator rights are skipped when the app isn't elevated.

## Build

You need Zig 0.17.x.

```sh
zig build                          # ReleaseSmall by default
zig build -Doptimize=Debug         # debug build
```

The executable is written to `zig-out/bin/JunkCleaner.exe`.

## Usage

Run `JunkCleaner.exe` with no arguments to open the GUI. Command-line modes:

| Flag | Description |
| --- | --- |
| `--auto` | Clean the saved selection without UI (used by the scheduler) |
| `--scan` | Print a read-only size report for every target |
| `--apps` | List installed applications |
| `--uninstall-cmd` | Print the uninstall command that would be used for each app (read-only) |
| `--leftovers <name>` | Show leftover files and registry keys for an app (read-only) |

Settings and logs are stored in `%LOCALAPPDATA%\JunkCleaner`.

## Disclaimer

This tool deletes files. Review what's selected before cleaning. Items such as the Recycle Bin can't be recovered afterwards.

## License

[MIT](LICENSE)
