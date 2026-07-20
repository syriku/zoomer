# Repository Guide

## Technology Stack

- This branch is a rewrite of `main` using RemObjects Elements. Use Mercury (`.vb`) for all new source code; do not reintroduce the C# projects or the Objective-C native bridge from `main`.
- Use Elements project and solution files (`.elements` and `Zoomer.sln`). Fire is the primary macOS IDE, Water or Visual Studio with Elements is used on Windows, and EBuild is the command-line build system.
- `MacApp` targets Cocoa through the Toffee backend. Implement the macOS application layer and the responsibilities of the former `native/Zoomer.Native` library directly in Mercury with Cocoa frameworks.
- `WPFApp` is the Windows application layer and targets WPF through the Echoes/.NET backend. The scaffold is currently named `WPFApplication`; rename it to `WPFApp` when implementation work begins.
- `Shared` replaces the former `Zoomer.Core`. Keep reusable state, transforms, controller flow, and platform contracts there. It must not depend on Cocoa, WPF, or other platform UI APIs.
- Keep project references and target settings compatible across the Toffee and Echoes consumers. Do not add targets to `Shared` unless an application or test project actually needs them.
- `global.json` is inherited migration scaffolding and does not define the primary toolchain for this branch. Review or remove it when the final Echoes target framework is selected.

## Architecture Boundaries

- Treat `../zoomer` (the `main` worktree) as the behavioral reference. Port behavior deliberately instead of copying its C# and C ABI structure into the Elements solution.
- `Shared` owns platform-independent workspace state, zoom/pan/flip transforms, preset/reset behavior, drawing state, and interfaces for capture, display selection, hotkeys, and workspace windows.
- `MacApp` owns the macOS lifecycle, menus, global shortcut, permissions, display discovery, ScreenCaptureKit capture, AppKit window/view rendering, input, cursor handling, packaging, signing, and notarization.
- `WPFApp` owns the Windows lifecycle, tray UI, global shortcut, screen capture, WPF rendering and input, cursor handling, packaging, and Windows-specific error reporting.
- Preserve capture ownership explicitly: document which layer owns a captured frame before and after a successful window update, and release it on stale, failed, and closed paths.
- Marshal macOS UI and capture callbacks onto the main queue. Keep WPF UI work on its dispatcher thread.
- User-facing UI, status, and error text, as well as the README, use Simplified Chinese.

## Commands and Verification

- The root `Makefile` currently contains command names only. Its targets are placeholders and must not be treated as successful verification until their recipes are implemented.
- The intended command surface is `make build`, `make test`, `make macapp`, `make wpfapp`, `make run-macapp`, `make run-wpfapp`, and `make clean`.
- When the external Elements compiler is installed, use `ebuild Zoomer.sln` as the starting point for manual solution builds. A command-line compiler is separate from the compiler bundled with Fire on macOS.
- Before implementing a Make target, copy the relevant EBuild invocation from the Fire or Water build log and verify it on the target operating system.
- Shared changes require tests for the shared behavior plus builds of both consumers. macOS behavior must be validated on macOS; WPF runtime behavior must be validated on Windows.
- There is no migrated test project yet. Add one before claiming functional parity with `main`.

## Commit Messages

- Every commit subject on this branch must start with a square-bracketed type: `[type] Subject`.
- Use one of `[feat]`, `[fix]`, `[refactor]`, `[docs]`, `[test]`, `[build]`, or `[chore]`.
- Write the subject in English with a capitalized imperative phrase and no trailing period, for example `[docs] Describe Elements project boundaries`.
- Choose the type for the primary purpose of the commit; do not combine multiple type tags.
