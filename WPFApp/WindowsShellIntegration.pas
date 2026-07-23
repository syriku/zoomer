namespace WPFApp;

uses
  System,
  System.Runtime.InteropServices,
  System.Windows.Interop,
  Core;

type
  WindowsShellIntegration = public class
  private
    const
      HotKeyIdentifier: Int32 = 1;
      TrayIconIdentifier: UInt32 = 1;
      TrayCallbackMessage: UInt32 = WindowsNative.WindowMessageApp + 42;
      MenuPresentIdentifier: UInt32 = 1001;
      MenuQuitIdentifier: UInt32 = 1002;

    var
    fMessageSource: HwndSource;
    fTrayData: WindowsNotifyIconData;
    fPresentationRequested: WorkspaceSurfaceRequested;
    fQuitRequested: WorkspaceSurfaceRequested;
    fWorkspaceState: WorkspaceState := WorkspaceState.Idle;
    fStatusText: String := '空闲';
    fHotKeyRegistered: Boolean;
    fTrayIconAdded: Boolean;

    method windowMessageHook(windowHandle: IntPtr) message(message: Int32) wParam(wParam: IntPtr) lParam(lParam: IntPtr) handled(var handled: Boolean): IntPtr;
    begin
      if (message = WindowsNative.WindowMessageHotKey) and (wParam.ToInt32 = HotKeyIdentifier) then begin
        handled := true;
        notifyPresentationRequested;
        exit IntPtr.Zero;
      end;

      if message = TrayCallbackMessage then begin
        case lParam.ToInt32 of
          WindowsNative.WindowMessageLeftButtonDoubleClick:
            notifyPresentationRequested;
          WindowsNative.WindowMessageRightButtonUp,
          WindowsNative.WindowMessageContextMenu:
            showContextMenu;
        end;
        handled := true;
      end;
      result := IntPtr.Zero;
    end;
    method showContextMenu;
    begin
      var cursorPoint: WindowsPoint;
      if not assigned(fMessageSource) then
        exit;

      var menu := WindowsNative.createPopupMenu;
      if menu = IntPtr.Zero then
        exit;

      try
        var presentFlags := WindowsNative.MenuString;
        if fWorkspaceState <> WorkspaceState.Idle then
          presentFlags := presentFlags or WindowsNative.MenuGrayed;

        WindowsNative.appendMenu(menu) options(presentFlags) identifier(new UIntPtr(MenuPresentIdentifier)) text('进入工作模式');
        WindowsNative.appendMenu(menu) options(WindowsNative.MenuGrayed) identifier(UIntPtr.Zero) text(displayStatusText);
        WindowsNative.appendMenu(menu) options(WindowsNative.MenuSeparator) identifier(UIntPtr.Zero) text(nil);
        WindowsNative.appendMenu(menu) options(WindowsNative.MenuString) identifier(new UIntPtr(MenuQuitIdentifier)) text('退出 Zoomer');

        if not WindowsNative.getCursorPosition(var cursorPoint) then
          exit;

        WindowsNative.setForegroundWindow(fMessageSource.Handle);
        var selected := WindowsNative.trackPopupMenu(menu)
          options(WindowsNative.TrackPopupRightButton or WindowsNative.TrackPopupReturnCommand)
          x(cursorPoint.X)
          y(cursorPoint.Y)
          reserved(0)
          ownerWindow(fMessageSource.Handle)
          rectangle(IntPtr.Zero);

        case selected of
          MenuPresentIdentifier: notifyPresentationRequested;
          MenuQuitIdentifier: notifyQuitRequested;
        end;
      finally
        WindowsNative.destroyMenu(menu);
      end;
    end;
    method notifyPresentationRequested;
    begin
      if fWorkspaceState <> WorkspaceState.Idle then
        exit;

      var listener := fPresentationRequested;
      if assigned(listener) then
        listener();
    end;
    method notifyQuitRequested;
    begin
      var listener := fQuitRequested;
      if assigned(listener) then
        listener();
    end;
    method displayStatusText: String;
    begin
      if fHotKeyRegistered then
        exit fStatusText;
      result := fStatusText + '；快捷键 Ctrl+Alt+Z 注册失败';
    end;
    method removeTrayIcon;
    begin
      if not fTrayIconAdded then
        exit;

      WindowsNative.updateNotifyIcon(WindowsNative.NotifyIconDelete) data(var fTrayData);
      fTrayIconAdded := false;
    end;
  public
    property PresentationRequested: WorkspaceSurfaceRequested read fPresentationRequested write fPresentationRequested;
    property QuitRequested: WorkspaceSurfaceRequested read fQuitRequested write fQuitRequested;
    property HotKeyRegistered: Boolean read fHotKeyRegistered;

    method startShell;
    begin
      if assigned(fMessageSource) then
        exit;

      var parameters := new HwndSourceParameters('Zoomer 消息窗口');
      parameters.Width := 0;
      parameters.Height := 0;
      parameters.WindowStyle := 0;
      fMessageSource := new HwndSource(parameters);
      fMessageSource.AddHook(@windowMessageHook);

      fTrayData := default(WindowsNotifyIconData);
      fTrayData.Size := UInt32(Marshal.SizeOf(typeOf(WindowsNotifyIconData)));
      fTrayData.WindowHandle := fMessageSource.Handle;
      fTrayData.Identifier := TrayIconIdentifier;
      fTrayData.Flags := WindowsNative.NotifyIconMessage or WindowsNative.NotifyIconIcon or WindowsNative.NotifyIconTip;
      fTrayData.CallbackMessage := TrayCallbackMessage;
      fTrayData.IconHandle := WindowsNative.loadIcon(IntPtr.Zero) resourceName(new IntPtr(32512));
      fTrayData.ToolTip := 'Zoomer';
      fTrayIconAdded := WindowsNative.updateNotifyIcon(WindowsNative.NotifyIconAdd) data(var fTrayData);

      fHotKeyRegistered := WindowsNative.registerHotKey(fMessageSource.Handle)
        identifier(HotKeyIdentifier)
        modifiers(WindowsNative.ModifierControl or WindowsNative.ModifierAlt or WindowsNative.ModifierNoRepeat)
        virtualKey(WindowsNative.VirtualKeyZ);
    end;
    method updateWorkspaceState(state: WorkspaceState) statusText(text: String);
    begin
      fWorkspaceState := state;
      if assigned(text) and (text <> '') then
        fStatusText := text
      else
        fStatusText := '空闲';

      if fTrayIconAdded then begin
        fTrayData.ToolTip := displayStatusText;
        WindowsNative.updateNotifyIcon(WindowsNative.NotifyIconModify) data(var fTrayData);
      end;
    end;
    method stopShell;
    begin
      if not assigned(fMessageSource) then
        exit;

      if fHotKeyRegistered then begin
        WindowsNative.unregisterHotKey(fMessageSource.Handle) identifier(HotKeyIdentifier);
        fHotKeyRegistered := false;
      end;

      removeTrayIcon;
      fMessageSource.RemoveHook(@windowMessageHook);
      fMessageSource.Dispose;
      fMessageSource := nil;
    end;
  end;

end.
