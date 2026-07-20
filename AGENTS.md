# Repository Guide

## Toolchain and Commands

- Use the .NET SDK selected by `global.json` (`10.0.301`, latest patch roll-forward). All C# warnings are errors via `Directory.Build.props`.
- `make build` builds the solution, including both app targets: macOS-oriented `net10.0` and Windows `net10.0-windows10.0.19041.0`.
- `make test` runs the entire test suite. Tests are a custom console executable in `tests/Zoomer.Core.Tests/Program.cs`, not a test-framework project; do not replace this with `dotnet test`. There is no single-test filter.
- For a focused core check, run `dotnet build src/Zoomer.Core/Zoomer.Core.csproj` followed by `make test`. To compile one app target, pass `-f net10.0` or `-f net10.0-windows10.0.19041.0` to `dotnet build src/Zoomer.App/Zoomer.App.csproj`.
- `make native` builds the current architecture's Debug macOS dylib. Use `./scripts/build-native.sh arm64 Release` (or `x86_64`) when an explicit architecture/configuration matters.
- `make app` is macOS-only and builds an AOT universal2 app at `artifacts/app/Zoomer.app`; it requires the macOS 14+ SDK/Xcode command-line tools and builds both architectures. `CONFIGURATION`, `VERSION`, `BUILD_NUMBER`, and optional `CODESIGN_IDENTITY` control packaging; signing is ad hoc when the identity is unset.
- `make windows` publishes the framework-dependent x64 single-file Windows app to `artifacts/windows/win-x64/Release`; the target machine still needs the .NET 10 Desktop Runtime x64.

## Architecture Boundaries

- Keep platform-independent state, transforms, and capture/window contracts in `src/Zoomer.Core`. `WorkspaceController` is the shared execution flow; platform hosts adapt its interfaces rather than duplicating that logic.
- `src/Zoomer.App` contains two implementations selected by `#if WINDOWS`: `AppHost.cs`/`NativeServices.cs` for macOS and `WindowsAppHost.cs`/`WindowsServices.cs` for Windows. The Windows UI is programmatic WPF plus WinForms tray/screen APIs; there is no XAML entrypoint.
- The macOS path crosses a C ABI: `native/Zoomer.Native/ZoomerNative.h` and `.m` must remain layout-compatible with `NativeMethods.cs`. Mirror callback field order, Cdecl signatures, boolean marshalling, display struct layout, exported names, and numeric error codes when changing this boundary.
- Preserve capture-frame ownership: `INativeWorkspaceWindow.Show` takes ownership only on success. On macOS, success transfers the `CGImage` into the native view; on failure, `WorkspaceController` disposes it. Tests explicitly cover stale, failed, and disposed capture paths.
- macOS capture and UI callbacks are marshalled onto the main queue. Do not invoke AppKit window operations from background callbacks.
- User-facing UI/status/error text and the README are in Simplified Chinese; keep new user-visible text consistent.

## Verification

- Shared/core changes: `make build` and `make test`.
- macOS bridge changes: also run `make native`; packaging, architecture, rpath, or signing changes require `make app`.
- `make build` cross-compiles the Windows target on macOS because `EnableWindowsTargeting` is set, but it does not validate Windows runtime behavior.

## Commit Messages

- Write commit subjects in English, matching the repository's existing concise imperative style (for example, `Add center and reset shortcuts`).
- Start with a capitalized verb, omit a trailing period, and do not use Conventional Commits prefixes unless the repository adopts them consistently.
