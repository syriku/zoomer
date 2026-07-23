namespace MacApp;

uses
  AppKit,
  Carbon.HIToolbox,
  Foundation,
  Core;

type
  [NSApplicationMain, IBObject]
  AppDelegate = public class(INSApplicationDelegate)
  private
    fPlatformActual: MacWorkspacePlatformActual;
    fWorkspaceSession: WorkspaceSession;
    fStatusItem: NSStatusItem;
    fPresentItem: NSMenuItem;
    fPermissionItem: NSMenuItem;
    fStatusTextItem: NSMenuItem;
    fGlobalHotKey: MacGlobalHotKey;
    fHotKeyRegistrationStatus: OSStatus;

    method configureStatusMenu;
    begin
      fStatusItem := NSStatusBar.systemStatusBar.statusItemWithLength(NSVariableStatusItemLength);
      var statusImage: NSImage := NSImage.imageWithSystemSymbolName('magnifyingglass.circle') accessibilityDescription('Zoomer');
      if statusImage <> nil then begin
        statusImage.template := true;
        fStatusItem.button.image := statusImage;
        fStatusItem.button.title := '';
      end
      else begin
        fStatusItem.button.title := 'Z';
      end;

      var menu := new NSMenu;
      fPresentItem := new NSMenuItem withTitle('进入工作模式') action(NSSelectorFromString('requestPresentation:')) keyEquivalent('');
      fPresentItem.target := self;
      menu.addItem(fPresentItem);

      fPermissionItem := new NSMenuItem withTitle('屏幕录制权限…') action(NSSelectorFromString('requestScreenRecordingPermission:')) keyEquivalent('');
      fPermissionItem.target := self;
      menu.addItem(fPermissionItem);

      fStatusTextItem := new NSMenuItem withTitle('空闲') action(nil) keyEquivalent('');
      fStatusTextItem.enabled := false;
      menu.addItem(fStatusTextItem);

      menu.addItem(NSMenuItem.separatorItem);

      var quitItem := new NSMenuItem withTitle('退出 Zoomer') action(NSSelectorFromString('quitApplication:')) keyEquivalent('q');
      quitItem.target := self;
      menu.addItem(quitItem);

      fStatusItem.menu := menu;
    end;
    method configureGlobalHotKey;
    begin
      if fGlobalHotKey <> nil then
        exit;

      fGlobalHotKey := new MacGlobalHotKey;
      fGlobalHotKey.Triggered := @globalHotKeyTriggered;
      if not fGlobalHotKey.registerHotKey then begin
        fHotKeyRegistrationStatus := fGlobalHotKey.RegistrationStatus;
        fGlobalHotKey.Triggered := nil;
        fGlobalHotKey := nil;
      end;
    end;
    method globalHotKeyTriggered;
    begin
      if fWorkspaceSession = nil then begin
        NSLog('Zoomer: ⌥⌘Z ignored because the workspace session is unavailable');
        exit;
      end;

      NSLog('Zoomer: ⌥⌘Z reached AppDelegate in state %d', fWorkspaceSession.State);
      if fWorkspaceSession.State = WorkspaceState.Idle then
        fWorkspaceSession.requestPresentation;
      refreshStatusMenu;
    end;
    method workspaceStateDidChange(snapshot: WorkspaceStateSnapshot);
    begin
      refreshStatusMenu;
    end;
    method refreshStatusMenu;
    begin
      if (fStatusItem = nil) or (fWorkspaceSession = nil) or (fPlatformActual = nil) then
        exit;

      fPresentItem.enabled := fWorkspaceSession.State = WorkspaceState.Idle;
      if fGlobalHotKey = nil then
        fStatusTextItem.title := NSString.stringWithFormat('无法注册快捷键 ⌥⌘Z（%d）', fHotKeyRegistrationStatus)
      else
        fStatusTextItem.title := fWorkspaceSession.StatusText;

      if fPlatformActual.screenRecordingPermission = WorkspacePermissionState.Granted then
        fPermissionItem.title := '屏幕录制权限：已授权'
      else
        fPermissionItem.title := '屏幕录制权限…';
    end;
    method shutdownWorkspace;
    begin
      if fGlobalHotKey <> nil then begin
        fGlobalHotKey.Triggered := nil;
        fGlobalHotKey.unregisterHotKey;
        fGlobalHotKey := nil;
      end;

      if fWorkspaceSession <> nil then begin
        fWorkspaceSession.StateChanged := nil;
        fWorkspaceSession.disposeSession;
        fWorkspaceSession := nil;
      end;

      if fStatusItem <> nil then begin
        NSStatusBar.systemStatusBar.removeStatusItem(fStatusItem);
        fStatusItem := nil;
      end;
    end;

    [IBAction]
    method requestPresentation(sender: NSObject);
    begin
      if fWorkspaceSession = nil then
        exit;

      fWorkspaceSession.requestPresentation;
      refreshStatusMenu;
    end;

    [IBAction]
    method requestScreenRecordingPermission(sender: NSObject);
    begin
      if fPlatformActual = nil then
        exit;

      if fPlatformActual.screenRecordingPermission <> WorkspacePermissionState.Granted then
        fPlatformActual.openScreenRecordingSettings;
      refreshStatusMenu;
    end;

    [IBAction]
    method quitApplication(sender: NSObject);
    begin
      shutdownWorkspace;
      NSApplication.sharedApplication.terminate(nil);
    end;
  public
    method applicationDidFinishLaunching(notification: NSNotification);
    begin
      NSApplication.sharedApplication.setActivationPolicy(NSApplicationActivationPolicy.Accessory);

      fPlatformActual := new MacWorkspacePlatformActual;
      WorkspaceActuals.registerPlatformActual(fPlatformActual);
      fWorkspaceSession := WorkspaceActuals.createSessionUsingRegisteredPlatform;
      fWorkspaceSession.StateChanged := @workspaceStateDidChange;

      configureStatusMenu;
      configureGlobalHotKey;
      refreshStatusMenu;
    end;
    method applicationWillTerminate(notification: NSNotification);
    begin
      shutdownWorkspace;
    end;
  end;

end.
