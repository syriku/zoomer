#if !WINDOWS
using System.Runtime.InteropServices;

namespace Zoomer.App;

internal static unsafe class NativeMethods
{
    private const string Library = "libZoomerNative";

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeDisplayDescriptor
    {
        internal uint DisplayId;
        internal double X;
        internal double Y;
        internal double Width;
        internal double Height;
        internal double BackingScale;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct AppCallbacks
    {
        internal delegate* unmanaged[Cdecl]<nint, void> PresentRequested;
        internal delegate* unmanaged[Cdecl]<nint, void> PermissionRequested;
        internal delegate* unmanaged[Cdecl]<nint, void> QuitRequested;
        internal delegate* unmanaged[Cdecl]<nint, void> HotKeyTriggered;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct WindowCallbacks
    {
        internal delegate* unmanaged[Cdecl]<nint, void> DismissRequested;
        internal delegate* unmanaged[Cdecl]<nint, double, double, double, void> ZoomRequested;
        internal delegate* unmanaged[Cdecl]<nint, double, double, double, void> MagnifyRequested;
        internal delegate* unmanaged[Cdecl]<nint, double, double, void> PanRequested;
        internal delegate* unmanaged[Cdecl]<nint, void> ResetRequested;
        internal delegate* unmanaged[Cdecl]<nint, void> DisplayDisconnected;
        internal delegate* unmanaged[Cdecl]<nint, void> ToggleHorizontalFlipRequested;
    }

    [DllImport(Library, EntryPoint = "zmr_app_initialize")]
    internal static extern int AppInitialize(nint context, AppCallbacks callbacks);

    [DllImport(Library, EntryPoint = "zmr_app_run")]
    internal static extern int AppRun();

    [DllImport(Library, EntryPoint = "zmr_app_stop")]
    internal static extern void AppStop();

    [DllImport(Library, EntryPoint = "zmr_app_set_menu")]
    internal static extern void AppSetMenu([MarshalAs(UnmanagedType.I1)] bool canPresent,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string statusText,
        [MarshalAs(UnmanagedType.I1)] bool authorized);

    [DllImport(Library, EntryPoint = "zmr_permission_is_authorized")]
    [return: MarshalAs(UnmanagedType.I1)]
    internal static extern bool PermissionIsAuthorized();

    [DllImport(Library, EntryPoint = "zmr_permission_request")]
    [return: MarshalAs(UnmanagedType.I1)]
    internal static extern bool PermissionRequest();

    [DllImport(Library, EntryPoint = "zmr_permission_open_settings")]
    internal static extern void PermissionOpenSettings();

    [DllImport(Library, EntryPoint = "zmr_capture_display")]
    internal static extern void CaptureDisplay(long requestId, nint context,
        delegate* unmanaged[Cdecl]<nint, long, nint, NativeDisplayDescriptor, int, nint, void> callback);

    [DllImport(Library, EntryPoint = "zmr_image_release")]
    internal static extern void ImageRelease(nint image);

    [DllImport(Library, EntryPoint = "zmr_window_create")]
    internal static extern nint WindowCreate(nint context, WindowCallbacks callbacks,
        nint image, NativeDisplayDescriptor display);

    [DllImport(Library, EntryPoint = "zmr_window_show")]
    internal static extern void WindowShow(nint window);

    [DllImport(Library, EntryPoint = "zmr_window_update_transform")]
    internal static extern void WindowUpdateTransform(nint window, double scale,
        double offsetX, double offsetY,
        [MarshalAs(UnmanagedType.I1)] bool horizontallyFlipped,
        [MarshalAs(UnmanagedType.I1)] bool showHud);

    [DllImport(Library, EntryPoint = "zmr_window_destroy")]
    internal static extern void WindowDestroy(nint window);
}
#endif
