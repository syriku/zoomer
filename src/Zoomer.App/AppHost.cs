#if !WINDOWS
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Zoomer.Core;

namespace Zoomer.App;

internal sealed unsafe class AppHost : IDisposable
{
    private readonly NativePermissionService _permission = new();
    private readonly WorkspaceController _workspace;
    private readonly GCHandle _selfHandle;
    private bool _disposed;

    public AppHost()
    {
        _workspace = new WorkspaceController(_permission,
            new NativeScreenCaptureService(), new NativeWindowFactory());
        _workspace.StateChanged += _ => RefreshMenu();
        _selfHandle = GCHandle.Alloc(this);
    }

    public int Run()
    {
        var callbacks = new NativeMethods.AppCallbacks
        {
            PresentRequested = &OnPresent,
            PermissionRequested = &OnPermission,
            QuitRequested = &OnQuit,
            HotKeyTriggered = &OnPresent,
        };
        var result = NativeMethods.AppInitialize(GCHandle.ToIntPtr(_selfHandle), callbacks);
        if (result != 0) return result;
        RefreshMenu();
        return NativeMethods.AppRun();
    }

    private void RefreshMenu()
        => NativeMethods.AppSetMenu(_workspace.State == WorkspaceState.Idle,
            _workspace.StatusText, _permission.IsAuthorized);

    private static AppHost FromContext(nint context) => (AppHost)GCHandle.FromIntPtr(context).Target!;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnPresent(nint context) => FromContext(context)._workspace.RequestPresentation();

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnPermission(nint context)
    {
        var host = FromContext(context);
        if (!host._permission.IsAuthorized) host._permission.OpenSystemSettings();
        host.RefreshMenu();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnQuit(nint context)
    {
        FromContext(context)._workspace.Dispose();
        NativeMethods.AppStop();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _workspace.Dispose();
        if (_selfHandle.IsAllocated) _selfHandle.Free();
    }
}
#endif
