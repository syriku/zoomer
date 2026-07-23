# Repository Guide

## Technology Stack

- This branch is a rewrite of `main` using RemObjects Elements. Use Oxygene (`.pas`) for all new source code; do not reintroduce the C# projects or the Objective-C native bridge from `main`.
- Use Elements project and solution files (`.elements` and `Zoomer.sln`). Fire is the primary macOS IDE, and Water or Visual Studio with Elements is used on Windows.
- `MacApp` targets Cocoa through the Toffee backend. Implement the macOS application layer and the responsibilities of the former `native/Zoomer.Native` library directly in Oxygene with Cocoa frameworks.
- `WPFApp` is the Windows application layer and targets WPF through the Echoes/.NET backend.
- `Shared` replaces the former `Zoomer.Core`. Keep reusable state, transforms, controller flow, and platform contracts there. It must not depend on Cocoa, WPF, or other platform UI APIs.
- Keep project references and target settings compatible across the Toffee and Echoes consumers. Do not add targets to `Shared` unless an application or test project actually needs them.
- `global.json` is inherited migration scaffolding and does not define the primary toolchain for this branch. Review or remove it when the final Echoes target framework is selected.

## Architecture Boundaries

- Treat `../zoomer` (the `main` worktree) as the behavioral reference. Port behavior deliberately instead of copying its C# and C ABI structure into the Elements solution.
- `Shared` owns platform-independent workspace state, zoom/pan/flip transforms, preset/reset behavior, drawing state, and the public workspace contract. Its API is intentionally not a mechanical port of the old C# service interfaces.
- Model platform-specific code as a Kotlin Multiplatform-style expect/actual boundary: `Shared` declares the `IWorkspacePlatformActual` and `IWorkspaceSurfaceActual` contracts plus `WorkspaceActuals.registerPlatformActual(...)`; each application registers exactly one platform actual during startup before creating a `WorkspaceSession`.
- Keep app lifecycle, menus, status UI, global shortcuts, settings navigation, display discovery, capture implementation, and native rendering in the application project. `Shared` must not acquire a Cocoa, WPF, or other platform reference to provide those features.
- `MacApp` owns the macOS lifecycle, menus, global shortcut, permissions, display discovery, ScreenCaptureKit capture, AppKit window/view rendering, input, cursor handling, packaging, signing, and notarization.
- `WPFApp` owns the Windows lifecycle, tray UI, global shortcut, screen capture, WPF rendering and input, cursor handling, packaging, and Windows-specific error reporting.
- Preserve capture ownership explicitly: document which layer owns a captured frame before and after a successful window update, and release it on stale, failed, and closed paths.
- Marshal macOS UI and capture callbacks onto the main queue. Keep WPF UI work on its dispatcher thread.
- User-facing UI, status, and error text, as well as the README, use Simplified Chinese.

## Oxygene Source Conventions

- Set each project's root namespace with its `.elements` `RootNamespace` property. Each `.pas` source file declares its namespace explicitly and ends with `end.`; `MacApp` and `WPFApp` use their project names, while `Shared` continues to expose `Core`.
- Use Oxygene multi-part method names for every API with two or more parameters in every project, not only `MacApp`. Preserve the existing parameter identifiers and semantic labels at declaration and call sites, for example `method presentFrame(workspaceFrame: IWorkspaceFrame) onDisplay(display: WorkspaceDisplay): WorkspacePresentationResult;` and `surface.presentFrame(frame) onDisplay(display);`.
- Prefer selector-shaped public APIs such as `captureDisplayWithRequestId(requestId) completion(completion)` and `renderTransform(transform) showHud(showHud)`. Do not replace their labels with positional-only overloads.
- Keep public shared contract types in `Core`; Mac-specific implementations belong directly under the `MacApp` root namespace unless a nested namespace is explicitly required.

## Build and Verification

- Build, run, and package `MacApp` with Fire on macOS. Build and run `WPFApp` with Water or Visual Studio with Elements on Windows.
- Shared changes require tests for the shared behavior plus builds of both consumers. macOS behavior must be validated on macOS; WPF runtime behavior must be validated on Windows.
- There is no migrated test project yet. Add one before claiming functional parity with `main`.

## Commit Messages

- Every commit subject on this branch must start with a square-bracketed type: `[type] Subject`.
- Use one of `[feat]`, `[fix]`, `[refactor]`, `[docs]`, `[test]`, `[build]`, or `[chore]`.
- Write the subject in English with a capitalized imperative phrase and no trailing period, for example `[docs] Describe Elements project boundaries`.
- Choose the type for the primary purpose of the commit; do not combine multiple type tags.
