#if !WINDOWS
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Zoomer.Core;

namespace Zoomer.App;

internal sealed class MacCaptureFrame(nint handle) : ICaptureFrame
{
    internal nint Handle { get; private set; } = handle;

    internal void TransferOwnership() => Handle = 0;

    public void Dispose()
    {
        if (Handle == 0) return;
        NativeMethods.ImageRelease(Handle);
        Handle = 0;
    }
}

internal sealed class NativePermissionService : IPermissionService
{
    public bool IsAuthorized => NativeMethods.PermissionIsAuthorized();
    public bool RequestAuthorization() => NativeMethods.PermissionRequest();
    public void OpenSystemSettings() => NativeMethods.PermissionOpenSettings();
}

internal sealed unsafe class NativeScreenCaptureService : IScreenCaptureService
{
    private sealed record CompletionState(Action<CaptureResult> Completion);

    public void Capture(long requestId, Action<CaptureResult> completion)
    {
        var context = GCHandle.ToIntPtr(GCHandle.Alloc(new CompletionState(completion)));
        NativeMethods.CaptureDisplay(requestId, context, &CaptureCompleted);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void CaptureCompleted(nint context, long requestId, nint image,
        NativeMethods.NativeDisplayDescriptor nativeDisplay, int errorCode, nint errorMessage)
    {
        var handle = GCHandle.FromIntPtr(context);
        var state = (CompletionState)handle.Target!;
        handle.Free();
        var display = new DisplayDescriptor(nativeDisplay.DisplayId.ToString(), nativeDisplay.X, nativeDisplay.Y,
            nativeDisplay.Width, nativeDisplay.Height, nativeDisplay.BackingScale);
        var message = errorMessage == 0 ? null : Marshal.PtrToStringUTF8(errorMessage);
        state.Completion(new CaptureResult(requestId, image == 0 ? null : new MacCaptureFrame(image), display,
            errorCode == 0 ? null : (WorkspaceErrorCode)errorCode, message));
    }
}

internal sealed class NativeWindowFactory : INativeWorkspaceWindowFactory
{
    public INativeWorkspaceWindow Create() => new NativeWorkspaceWindow();
}

internal sealed unsafe class NativeWorkspaceWindow : INativeWorkspaceWindow
{
    private readonly GCHandle _selfHandle;
    private nint _handle;
    private bool _disposed;

    public NativeWorkspaceWindow() => _selfHandle = GCHandle.Alloc(this);

    public event Action? DismissRequested;
    public event Action<double, double, double>? ZoomRequested;
    public event Action<double, double, double>? MagnifyRequested;
    public event Action<double, double>? PanRequested;
    public event Action? ResetRequested;
    public event Action? FullResetRequested;
    public event Action<double, double>? CenterRequested;
    public event Action? ToggleHorizontalFlipRequested;
    public event Action? TargetDisplayDisconnected;

    public WindowShowResult Show(ICaptureFrame frame, DisplayDescriptor display)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (frame is not MacCaptureFrame macFrame ||
            !uint.TryParse(display.DisplayId, out var displayId))
            return WindowShowResult.Failure("无法显示工作窗口：截图或显示器信息无效");

        var callbacks = new NativeMethods.WindowCallbacks
        {
            DismissRequested = &OnDismiss,
            ZoomRequested = &OnZoom,
            MagnifyRequested = &OnMagnify,
            PanRequested = &OnPan,
            ResetRequested = &OnReset,
            FullResetRequested = &OnFullReset,
            CenterRequested = &OnCenter,
            DisplayDisconnected = &OnDisplayDisconnected,
            ToggleHorizontalFlipRequested = &OnToggleHorizontalFlip,
        };
        var nativeDisplay = new NativeMethods.NativeDisplayDescriptor
        {
            DisplayId = displayId,
            X = display.X,
            Y = display.Y,
            Width = display.Width,
            Height = display.Height,
            BackingScale = display.BackingScale,
        };
        _handle = NativeMethods.WindowCreate(GCHandle.ToIntPtr(_selfHandle), callbacks, macFrame.Handle, nativeDisplay);
        if (_handle == 0)
            return WindowShowResult.Failure("无法显示工作窗口：原生窗口创建失败");
        macFrame.TransferOwnership();
        NativeMethods.WindowShow(_handle);
        return WindowShowResult.Success;
    }

    public void UpdateTransform(TransformState transform, bool showHud)
    {
        if (_handle != 0)
            NativeMethods.WindowUpdateTransform(_handle, transform.Scale,
                transform.OffsetX, transform.OffsetY, transform.IsHorizontallyFlipped, showHud);
    }

    private static NativeWorkspaceWindow FromContext(nint context)
        => (NativeWorkspaceWindow)GCHandle.FromIntPtr(context).Target!;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnDismiss(nint context) => FromContext(context).DismissRequested?.Invoke();

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnZoom(nint context, double delta, double x, double y)
        => FromContext(context).ZoomRequested?.Invoke(delta, x, y);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnMagnify(nint context, double magnification, double x, double y)
        => FromContext(context).MagnifyRequested?.Invoke(magnification, x, y);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnPan(nint context, double dx, double dy)
        => FromContext(context).PanRequested?.Invoke(dx, dy);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnReset(nint context) => FromContext(context).ResetRequested?.Invoke();

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnFullReset(nint context) => FromContext(context).FullResetRequested?.Invoke();

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnCenter(nint context, double width, double height)
        => FromContext(context).CenterRequested?.Invoke(width, height);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnDisplayDisconnected(nint context)
        => FromContext(context).TargetDisplayDisconnected?.Invoke();

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnToggleHorizontalFlip(nint context)
        => FromContext(context).ToggleHorizontalFlipRequested?.Invoke();

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_handle != 0)
        {
            NativeMethods.WindowDestroy(_handle);
            _handle = 0;
        }
        if (_selfHandle.IsAllocated) _selfHandle.Free();
    }
}
#endif
