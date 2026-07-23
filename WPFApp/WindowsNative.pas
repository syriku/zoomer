namespace WPFApp;

uses
  System,
  System.Runtime.InteropServices,
  Core;

type
  [StructLayout(LayoutKind.Sequential)]
  WindowsPoint = public record
  public
    X: Int32;
    Y: Int32;
  end;

  [StructLayout(LayoutKind.Sequential)]
  WindowsRect = public record
  private
    method get_Width: Int32;
    begin
      result := Right - Left;
    end;
    method get_Height: Int32;
    begin
      result := Bottom - Top;
    end;
  public
    Left: Int32;
    Top: Int32;
    Right: Int32;
    Bottom: Int32;

    property Width: Int32 read get_Width;
    property Height: Int32 read get_Height;
  end;

  [StructLayout(LayoutKind.Sequential, CharSet := CharSet.Unicode)]
  WindowsMonitorInfo = public record
  public
    Size: UInt32;
    MonitorBounds: WindowsRect;
    WorkBounds: WindowsRect;
    Flags: UInt32;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst := 32)]
    DeviceName: String;
  end;

  [StructLayout(LayoutKind.Sequential, CharSet := CharSet.Unicode)]
  WindowsNotifyIconData = public record
  public
    Size: UInt32;
    WindowHandle: IntPtr;
    Identifier: UInt32;
    Flags: UInt32;
    CallbackMessage: UInt32;
    IconHandle: IntPtr;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst := 128)]
    ToolTip: String;
    State: UInt32;
    StateMask: UInt32;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst := 256)]
    Information: String;
    VersionOrTimeout: UInt32;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst := 64)]
    InformationTitle: String;
    InformationFlags: UInt32;
    ItemGuid: Guid;
    BalloonIconHandle: IntPtr;
  end;

  WindowsNative = public static class
  public
    const
      MonitorDefaultToNull: UInt32 = 0;
      SourceCopy: UInt32 = $00CC0020;
      CaptureBlt: UInt32 = $40000000;
      ScreenDevice: String = 'DISPLAY';

      NotifyIconAdd: UInt32 = 0;
      NotifyIconModify: UInt32 = 1;
      NotifyIconDelete: UInt32 = 2;
      NotifyIconMessage: UInt32 = 1;
      NotifyIconIcon: UInt32 = 2;
      NotifyIconTip: UInt32 = 4;

      WindowMessageApp: UInt32 = $8000;
      WindowMessageHotKey: Int32 = $0312;
      WindowMessageMouseHorizontalWheel: Int32 = $020E;
      WindowMessageDisplayChange: Int32 = $007E;
      WindowMessageLeftButtonDoubleClick: Int32 = $0203;
      WindowMessageRightButtonUp: Int32 = $0205;
      WindowMessageContextMenu: Int32 = $007B;

      ModifierAlt: UInt32 = $0001;
      ModifierControl: UInt32 = $0002;
      ModifierNoRepeat: UInt32 = $4000;
      VirtualKeyZ: UInt32 = $5A;

      MenuString: UInt32 = $0000;
      MenuGrayed: UInt32 = $0001;
      MenuSeparator: UInt32 = $0800;
      TrackPopupRightButton: UInt32 = $0002;
      TrackPopupReturnCommand: UInt32 = $0100;

      SetWindowPosNoOwnerZOrder: UInt32 = $0200;
      SetWindowPosShowWindow: UInt32 = $0040;

    class method enablePerMonitorDpiAwareness;
    begin
      try
        setProcessDpiAwarenessContext(new IntPtr(-4));
      except
        // Windows 10 之前的系统不提供 Per-Monitor V2；目标系统最低为 Windows 10。
      end;
    end;
    class method displayUnderPointer: WorkspaceDisplay;
    begin
      var point: WindowsPoint;
      var monitorInfo: WindowsMonitorInfo;
      if not getCursorPosition(var point) then
        exit nil;

      if not monitorInfoAtPoint(point) info(var monitorInfo) then
        exit nil;

      result := new WorkspaceDisplay(monitorInfo.DeviceName)
        originX(monitorInfo.MonitorBounds.Left)
        originY(monitorInfo.MonitorBounds.Top)
        width(monitorInfo.MonitorBounds.Width)
        height(monitorInfo.MonitorBounds.Height)
        backingScale(1.0);
    end;
    class method boundsForDisplay(display: WorkspaceDisplay) rectangle(var bounds: WindowsRect): Boolean;
    begin
      var point: WindowsPoint;
      var monitorInfo: WindowsMonitorInfo;
      if not assigned(display) then
        exit false;

      point.X := Int32(Math.Round(display.OriginX)) + 1;
      point.Y := Int32(Math.Round(display.OriginY)) + 1;
      if not monitorInfoAtPoint(point) info(var monitorInfo) then
        exit false;

      if not String.Equals(monitorInfo.DeviceName, display.DisplayId, StringComparison.OrdinalIgnoreCase) then
        exit false;

      bounds := monitorInfo.MonitorBounds;
      result := true;
    end;
    class method monitorInfoAtPoint(point: WindowsPoint) info(var monitorInfo: WindowsMonitorInfo): Boolean;
    begin
      var monitor := monitorFromPoint(point) options(MonitorDefaultToNull);
      if monitor = IntPtr.Zero then
        exit false;

      monitorInfo := default(WindowsMonitorInfo);
      monitorInfo.Size := UInt32(Marshal.SizeOf(typeOf(WindowsMonitorInfo)));
      result := getMonitorInfo(monitor) info(var monitorInfo);
    end;
    class method signedHighWord(value: IntPtr): Int32;
    begin
      var wordValue := Int32((value.ToInt64 shr 16) and $FFFF);
      if wordValue >= $8000 then
        wordValue := wordValue - $10000;
      result := wordValue;
    end;
    class method topmostWindowHandle: IntPtr;
    begin
      result := new IntPtr(-1);
    end;

    [DllImport('user32.dll', EntryPoint := 'SetProcessDpiAwarenessContext')]
    class method setProcessDpiAwarenessContext(context: IntPtr): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'GetCursorPos', SetLastError := true)]
    class method getCursorPosition(var cursorPoint: WindowsPoint): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'MonitorFromPoint')]
    class method monitorFromPoint(point: WindowsPoint) options(defaultFlags: UInt32): IntPtr; external;

    [DllImport('user32.dll', EntryPoint := 'GetMonitorInfoW', CharSet := CharSet.Unicode, SetLastError := true)]
    class method getMonitorInfo(monitorHandle: IntPtr) info(var monitorInfo: WindowsMonitorInfo): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'GetDC', SetLastError := true)]
    class method getDeviceContext(windowHandle: IntPtr): IntPtr; external;

    [DllImport('user32.dll', EntryPoint := 'ReleaseDC')]
    class method releaseDeviceContext(windowHandle: IntPtr) deviceContext(context: IntPtr): Int32; external;

    [DllImport('gdi32.dll', EntryPoint := 'CreateCompatibleDC', SetLastError := true)]
    class method createCompatibleDeviceContext(sourceContext: IntPtr): IntPtr; external;

    [DllImport('gdi32.dll', EntryPoint := 'CreateCompatibleBitmap', SetLastError := true)]
    class method createCompatibleBitmap(sourceContext: IntPtr) width(pixelWidth: Int32) height(pixelHeight: Int32): IntPtr; external;

    [DllImport('gdi32.dll', EntryPoint := 'SelectObject')]
    class method selectGraphicsObject(deviceContext: IntPtr) graphicsObject(objectHandle: IntPtr): IntPtr; external;

    [DllImport('gdi32.dll', EntryPoint := 'BitBlt', SetLastError := true)]
    class method copyPixels(destinationContext: IntPtr) destinationX(x: Int32) destinationY(y: Int32) width(pixelWidth: Int32) height(pixelHeight: Int32) sourceContext(source: IntPtr) sourceX(sourceOriginX: Int32) sourceY(sourceOriginY: Int32) operation(rasterOperation: UInt32): Boolean; external;

    [DllImport('gdi32.dll', EntryPoint := 'DeleteObject')]
    class method deleteGraphicsObject(graphicsObject: IntPtr): Boolean; external;

    [DllImport('gdi32.dll', EntryPoint := 'DeleteDC')]
    class method deleteDeviceContext(deviceContext: IntPtr): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'RegisterHotKey', SetLastError := true)]
    class method registerHotKey(windowHandle: IntPtr) identifier(id: Int32) modifiers(modifierFlags: UInt32) virtualKey(key: UInt32): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'UnregisterHotKey')]
    class method unregisterHotKey(windowHandle: IntPtr) identifier(id: Int32): Boolean; external;

    [DllImport('shell32.dll', EntryPoint := 'Shell_NotifyIconW', CharSet := CharSet.Unicode)]
    class method updateNotifyIcon(action: UInt32) data(var iconData: WindowsNotifyIconData): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'LoadIconW')]
    class method loadIcon(instanceHandle: IntPtr) resourceName(resourceIdentifier: IntPtr): IntPtr; external;

    [DllImport('user32.dll', EntryPoint := 'CreatePopupMenu')]
    class method createPopupMenu: IntPtr; external;

    [DllImport('user32.dll', EntryPoint := 'AppendMenuW', CharSet := CharSet.Unicode)]
    class method appendMenu(menuHandle: IntPtr) options(menuFlags: UInt32) identifier(itemIdentifier: UIntPtr) text(itemText: String): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'TrackPopupMenu')]
    class method trackPopupMenu(menuHandle: IntPtr) options(menuFlags: UInt32) x(screenX: Int32) y(screenY: Int32) reserved(reservedValue: Int32) ownerWindow(ownerHandle: IntPtr) rectangle(reservedRectangle: IntPtr): UInt32; external;

    [DllImport('user32.dll', EntryPoint := 'DestroyMenu')]
    class method destroyMenu(menuHandle: IntPtr): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'SetForegroundWindow')]
    class method setForegroundWindow(windowHandle: IntPtr): Boolean; external;

    [DllImport('user32.dll', EntryPoint := 'SetWindowPos', SetLastError := true)]
    class method setWindowPosition(windowHandle: IntPtr) insertAfterWindow(insertAfterHandle: IntPtr) x(left: Int32) y(top: Int32) width(pixelWidth: Int32) height(pixelHeight: Int32) options(positionFlags: UInt32): Boolean; external;
  end;

end.
