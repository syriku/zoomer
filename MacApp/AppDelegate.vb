Imports AppKit
Imports Carbon.HIToolbox
Imports Foundation
Imports [Shared].Core

Namespace Application

  <NSApplicationMain> <IBObject>
  Public Class AppDelegate
    Inherits INSApplicationDelegate

    Private _platformActual As MacWorkspacePlatformActual
    Private _workspaceSession As WorkspaceSession
    Private _statusItem As NSStatusItem
    Private _presentItem As NSMenuItem
    Private _permissionItem As NSMenuItem
    Private _statusTextItem As NSMenuItem
    Private _globalHotKey As MacGlobalHotKey
    Private _hotKeyRegistrationStatus As OSStatus

    Public Sub applicationDidFinishLaunching(notification As NSNotification)
      NSApplication.sharedApplication().setActivationPolicy(NSApplicationActivationPolicy.Accessory)

      _platformActual = New MacWorkspacePlatformActual()
      WorkspaceActuals.registerPlatformActual(_platformActual)
      _workspaceSession = WorkspaceActuals.createSessionUsingRegisteredPlatform()
      _workspaceSession.StateChanged = AddressOf workspaceStateDidChange

      configureStatusMenu()
      configureGlobalHotKey()
      refreshStatusMenu()
    End Sub

    Public Sub applicationWillTerminate(notification As NSNotification)
      shutdownWorkspace()
    End Sub

    Private Sub configureStatusMenu()
      _statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
      Dim statusImage As NSImage = NSImage.imageWithSystemSymbolName("magnifyingglass.circle", accessibilityDescription: "Zoomer")
      If statusImage IsNot Null Then
        statusImage.template = True
        _statusItem.button.image = statusImage
        _statusItem.button.title = ""
      Else
        _statusItem.button.title = "Z"
      End If

      Dim menu As NSMenu = New NSMenu()
      _presentItem = New NSMenuItem(Title: "进入工作模式", action: NSSelectorFromString("requestPresentation:"), keyEquivalent: "")
      _presentItem.target = Me
      menu.addItem(_presentItem)

      _permissionItem = New NSMenuItem(Title: "屏幕录制权限…", action: NSSelectorFromString("requestScreenRecordingPermission:"), keyEquivalent: "")
      _permissionItem.target = Me
      menu.addItem(_permissionItem)

      _statusTextItem = New NSMenuItem(Title: "空闲", action: Null, keyEquivalent: "")
      _statusTextItem.enabled = False
      menu.addItem(_statusTextItem)

      menu.addItem(NSMenuItem.separatorItem())

      Dim quitItem As NSMenuItem = New NSMenuItem(Title: "退出 Zoomer", action: NSSelectorFromString("quitApplication:"), keyEquivalent: "q")
      quitItem.target = Me
      menu.addItem(quitItem)

      _statusItem.menu = menu
    End Sub

    Private Sub configureGlobalHotKey()
      _globalHotKey = New MacGlobalHotKey()
      _globalHotKey.Triggered = AddressOf globalHotKeyTriggered
      If Not _globalHotKey.registerHotKey() Then
        _hotKeyRegistrationStatus = _globalHotKey.RegistrationStatus()
        _globalHotKey.Triggered = Null
        _globalHotKey = Null
      End If
    End Sub

    Private Sub globalHotKeyTriggered()
      If _workspaceSession Is Null Then
        NSLog("Zoomer: ⌥⌘Z ignored because the workspace session is unavailable")
        Exit Sub
      End If

      NSLog("Zoomer: ⌥⌘Z reached AppDelegate in state %d", _workspaceSession.State())
      If _workspaceSession.State() = WorkspaceState.Idle Then
        _workspaceSession.requestPresentation()
      End If
      refreshStatusMenu()
    End Sub

    Private Sub workspaceStateDidChange(snapshot As WorkspaceStateSnapshot)
      refreshStatusMenu()
    End Sub

    Private Sub refreshStatusMenu()
      If _statusItem Is Null OrElse _workspaceSession Is Null OrElse _platformActual Is Null Then
        Exit Sub
      End If

      _presentItem.enabled = _workspaceSession.State() = WorkspaceState.Idle
      If _globalHotKey Is Null Then
        _statusTextItem.title = NSString.stringWithFormat("无法注册快捷键 ⌥⌘Z（%d）", _hotKeyRegistrationStatus)
      Else
        _statusTextItem.title = _workspaceSession.StatusText()
      End If

      If _platformActual.screenRecordingPermission() = WorkspacePermissionState.Granted Then
        _permissionItem.title = "屏幕录制权限：已授权"
      Else
        _permissionItem.title = "屏幕录制权限…"
      End If
    End Sub

    <IBAction>
    Private Sub requestPresentation(sender As NSObject)
      If _workspaceSession Is Null Then
        Exit Sub
      End If

      _workspaceSession.requestPresentation()
      refreshStatusMenu()
    End Sub

    <IBAction>
    Private Sub requestScreenRecordingPermission(sender As NSObject)
      If _platformActual Is Null Then
        Exit Sub
      End If

      If _platformActual.screenRecordingPermission() <> WorkspacePermissionState.Granted Then
        _platformActual.openScreenRecordingSettings()
      End If
      refreshStatusMenu()
    End Sub

    <IBAction>
    Private Sub quitApplication(sender As NSObject)
      shutdownWorkspace()
      NSApplication.sharedApplication().terminate(Null)
    End Sub

    Private Sub shutdownWorkspace()
      If _globalHotKey IsNot Null Then
        _globalHotKey.Triggered = Null
        _globalHotKey.unregisterHotKey()
        _globalHotKey = Null
      End If

      If _workspaceSession IsNot Null Then
        _workspaceSession.StateChanged = Null
        _workspaceSession.disposeSession()
        _workspaceSession = Null
      End If

      If _statusItem IsNot Null Then
        NSStatusBar.systemStatusBar().removeStatusItem(_statusItem)
        _statusItem = Null
      End If
    End Sub

  End Class

End Namespace
