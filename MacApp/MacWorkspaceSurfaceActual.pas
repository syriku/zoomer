namespace MacApp;

interface

uses
  AppKit,
  CoreGraphics,
  Foundation,
  QuartzCore,
  RemObjects.Elements.RTL,
  Core;

type
  MacWorkspaceSurfaceActual = public class(IWorkspaceSurfaceActual)
  private
    fCommandRequested: WorkspaceCommandRequested;
    fDismissRequested: WorkspaceSurfaceRequested;
    fTargetDisplayDisconnected: WorkspaceSurfaceRequested;
    fWindow: MacWorkspaceWindow;
    fImageView: MacWorkspaceImageView;
    fHudLabel: NSTextField;
    fOwnedFrame: MacWorkspaceFrame;
    fTargetDisplayId: String;
    fScreenObserver: NSObject;
    fWindowCloseObserver: NSObject;
    fHudFadeTimer: NSTimer;
    fIsDismissing: Boolean;
    fDidRequestDisplayDismissal: Boolean;

    method workspaceCommandRequested(command: WorkspaceCommand);
    method showHudTemporarily;
    method stopHudFadeTimer;
    method workspaceDismissRequested;
    method beginObservingDisplayForWindow(window: NSWindow) displayId(targetDisplayId: String);
    method stopObservingDisplayChanges;
    method checkTargetDisplayAvailability;
    method screenWithIdentifier(displayId: String): NSScreen;
    method identifierForScreen(screen: NSScreen): String;
    method failedPresentationWithMessage(message: String): WorkspacePresentationResult;
    method releaseOwnedFrame;
    method clearPresentationWithoutReleasingFrame;
    method requestDismissal;
  public
    property CommandRequested: WorkspaceCommandRequested read fCommandRequested write fCommandRequested;
    property DismissRequested: WorkspaceSurfaceRequested read fDismissRequested write fDismissRequested;
    property TargetDisplayDisconnected: WorkspaceSurfaceRequested read fTargetDisplayDisconnected write fTargetDisplayDisconnected;

    method presentFrame(workspaceFrame: IWorkspaceFrame) onDisplay(display: WorkspaceDisplay): WorkspacePresentationResult;
    method renderTransform(transform: WorkspaceTransform) showHud(showHud: Boolean);
    method dismissPresentation;
  end;

implementation

method MacWorkspaceSurfaceActual.presentFrame(workspaceFrame: IWorkspaceFrame) onDisplay(display: WorkspaceDisplay): WorkspacePresentationResult;
begin
  if not NSThread.isMainThread then
    exit failedPresentationWithMessage('工作区界面必须在主线程显示');

  if fWindow <> nil then
    exit failedPresentationWithMessage('工作区已经显示');

  var nativeFrame := workspaceFrame as MacWorkspaceFrame;
  if (nativeFrame = nil) or nativeFrame.IsReleased then
    exit failedPresentationWithMessage('无法显示工作区：截图无效');

  if display = nil then
    exit failedPresentationWithMessage('无法显示工作区：显示器信息无效');

  var targetScreen := screenWithIdentifier(display.DisplayId);
  if targetScreen = nil then
    exit failedPresentationWithMessage('无法显示工作区：目标显示器不可用');

  var image := nativeFrame.imageForPresentation;
  if image = nil then
    exit failedPresentationWithMessage('无法显示工作区：截图已经释放');

  var newWindow: MacWorkspaceWindow := nil;
  try
    var screenFrame := targetScreen.frame;
    newWindow := new MacWorkspaceWindow withContentRect(screenFrame) styleMask(NSWindowStyleMask.Borderless) backing(NSBackingStoreType.Buffered) defer(false) screen(targetScreen);
    // The surface keeps the window in a strong ARC field until dismissal has
    // completed. Match the original Cocoa implementation and prevent close()
    // from scheduling a second ownership release for that same window.
    newWindow.releasedWhenClosed := false;
    newWindow.backgroundColor := NSColor.blackColor;
    newWindow.opaque := true;
    newWindow.acceptsMouseMovedEvents := true;
    newWindow.level := NSMainMenuWindowLevel;
    newWindow.collectionBehavior := NSWindowCollectionBehavior.CanJoinAllSpaces or
      NSWindowCollectionBehavior.FullScreenAuxiliary;

    var contentFrame := NSMakeRect(0.0, 0.0, screenFrame.size.width, screenFrame.size.height);
    var contentView := new NSView withFrame(contentFrame);
    var imageView := new MacWorkspaceImageView withFrame(contentFrame);
    imageView.Image := image;
    imageView.wantsLayer := true;
    contentView.addSubview(imageView);

    var hudLabel := NSTextField.labelWithString('100%');
    hudLabel.frame := NSMakeRect(16.0, 16.0, 88.0, 36.0);
    hudLabel.font := NSFont.monospacedDigitSystemFontOfSize(18.0) weight(NSFontWeightSemibold);
    hudLabel.textColor := NSColor.whiteColor;
    hudLabel.alignment := NSTextAlignment.Center;
    hudLabel.wantsLayer := true;
    hudLabel.layer.backgroundColor := NSColor.colorWithWhite(0.0) alpha(0.72).CGColor;
    hudLabel.layer.cornerRadius := 7.0;
    hudLabel.hidden := true;
    contentView.addSubview(hudLabel);

    newWindow.contentView := contentView;
    imageView.CommandRequested := @workspaceCommandRequested;
    imageView.DismissRequested := @workspaceDismissRequested;

    fWindow := newWindow;
    fImageView := imageView;
    fHudLabel := hudLabel;
    fOwnedFrame := nativeFrame;
    fTargetDisplayId := display.DisplayId;
    fDidRequestDisplayDismissal := false;
    beginObservingDisplayForWindow(newWindow) displayId(fTargetDisplayId);

    NSApplication.sharedApplication.activateIgnoringOtherApps(true);
    newWindow.makeKeyAndOrderFront(nil);
    newWindow.makeFirstResponder(imageView);
    result := WorkspacePresentationResult.succeeded;
  except
    on caughtError: Exception do begin
      fIsDismissing := true;
      stopObservingDisplayChanges;
      if newWindow <> nil then
        newWindow.close;

      clearPresentationWithoutReleasingFrame;
      fIsDismissing := false;
      result := failedPresentationWithMessage('无法显示工作区');
    end;
  end;
end;

method MacWorkspaceSurfaceActual.renderTransform(transform: WorkspaceTransform) showHud(showHud: Boolean);
begin
  if not NSThread.isMainThread then begin
    NSOperationQueue.mainQueue.addOperationWithBlock(method
      begin
        renderTransform(transform) showHud(showHud);
      end);
    exit;
  end;

  if (fWindow = nil) or (fImageView = nil) or (transform = nil) then
    exit;

  fImageView.renderTransform(transform);

  if fHudLabel <> nil then begin
    fHudLabel.stringValue := NSString.stringWithFormat('%.0f%%', transform.Scale * 100.0);
    if showHud then
      showHudTemporarily;
  end;
end;

method MacWorkspaceSurfaceActual.dismissPresentation;
begin
  if not NSThread.isMainThread then begin
    NSOperationQueue.mainQueue.addOperationWithBlock(method
      begin
        dismissPresentation;
      end);
    exit;
  end;

  fIsDismissing := true;
  NSLog('Zoomer: beginning workspace window dismissal');
  stopObservingDisplayChanges;
  stopHudFadeTimer;

  if fImageView <> nil then begin
    fImageView.CommandRequested := nil;
    fImageView.DismissRequested := nil;
  end;

  if fWindow <> nil then begin
    NSLog('Zoomer: closing workspace window');
    fWindow.orderOut(nil);
    fWindow.close;
    NSLog('Zoomer: workspace window close returned');
  end;

  releaseOwnedFrame;
  clearPresentationWithoutReleasingFrame;
  fIsDismissing := false;
  NSLog('Zoomer: workspace dismissal completed');
end;

method MacWorkspaceSurfaceActual.workspaceCommandRequested(command: WorkspaceCommand);
begin
  var commandListener := fCommandRequested;
  if assigned(commandListener) then
    commandListener(command);
end;

method MacWorkspaceSurfaceActual.showHudTemporarily;
begin
  stopHudFadeTimer;
  fHudLabel.hidden := false;
  fHudLabel.alphaValue := 1.0;
  fHudFadeTimer := NSTimer.scheduledTimerWithTimeInterval(0.8) repeats(false) &block(method(aTimer: NSTimer)
    begin
      fHudFadeTimer := nil;
      if fHudLabel <> nil then begin
        NSAnimationContext.runAnimationGroup(method(animation: NSAnimationContext)
          begin
            animation.duration := 0.2;
            fHudLabel.animator.alphaValue := 0.0;
          end) completionHandler(nil);
      end;
    end);
end;

method MacWorkspaceSurfaceActual.stopHudFadeTimer;
begin
  if fHudFadeTimer <> nil then begin
    fHudFadeTimer.invalidate;
    fHudFadeTimer := nil;
  end;
end;

method MacWorkspaceSurfaceActual.workspaceDismissRequested;
begin
  requestDismissal;
end;

method MacWorkspaceSurfaceActual.beginObservingDisplayForWindow(window: NSWindow) displayId(targetDisplayId: String);
begin
  var center := NSNotificationCenter.defaultCenter;
  fScreenObserver := center.addObserverForName(NSApplicationDidChangeScreenParametersNotification) object(nil) queue(NSOperationQueue.mainQueue) usingBlock(method(notification: NSNotification)
    begin
      checkTargetDisplayAvailability;
    end);
  fWindowCloseObserver := center.addObserverForName(NSWindowWillCloseNotification) object(window) queue(NSOperationQueue.mainQueue) usingBlock(method(notification: NSNotification)
    begin
      if not fIsDismissing then
        requestDismissal;
    end);
end;

method MacWorkspaceSurfaceActual.stopObservingDisplayChanges;
begin
  var center := NSNotificationCenter.defaultCenter;
  if fScreenObserver <> nil then begin
    center.removeObserver(fScreenObserver);
    fScreenObserver := nil;
  end;

  if fWindowCloseObserver <> nil then begin
    center.removeObserver(fWindowCloseObserver);
    fWindowCloseObserver := nil;
  end;
end;

method MacWorkspaceSurfaceActual.checkTargetDisplayAvailability;
begin
  if (fTargetDisplayId = nil) or fDidRequestDisplayDismissal then
    exit;

  if screenWithIdentifier(fTargetDisplayId) <> nil then
    exit;

  fDidRequestDisplayDismissal := true;
  var disconnectListener := fTargetDisplayDisconnected;
  if assigned(disconnectListener) then
    disconnectListener();
end;

method MacWorkspaceSurfaceActual.screenWithIdentifier(displayId: String): NSScreen;
begin
  if displayId = nil then begin
    result := nil;
    exit;
  end;

  for each screen: NSScreen in NSScreen.screens do begin
    if identifierForScreen(screen) = displayId then
      exit screen;
  end;

  result := nil;
end;

method MacWorkspaceSurfaceActual.identifierForScreen(screen: NSScreen): String;
begin
  var displayNumber := screen.deviceDescription.objectForKey('NSScreenNumber') as NSNumber;
  if displayNumber = nil then begin
    result := nil;
    exit;
  end;

  result := displayNumber.stringValue;
end;

method MacWorkspaceSurfaceActual.failedPresentationWithMessage(message: String): WorkspacePresentationResult;
begin
  result := WorkspacePresentationResult.failedWithFailure(new WorkspaceFailure(WorkspaceFailureCode.PresentationFailed) message(message));
end;

method MacWorkspaceSurfaceActual.releaseOwnedFrame;
begin
  if fOwnedFrame <> nil then begin
    fOwnedFrame.releaseFrame;
    fOwnedFrame := nil;
  end;
end;

method MacWorkspaceSurfaceActual.clearPresentationWithoutReleasingFrame;
begin
  fWindow := nil;
  fImageView := nil;
  fHudLabel := nil;
  fOwnedFrame := nil;
  fTargetDisplayId := nil;
  fDidRequestDisplayDismissal := false;
end;

method MacWorkspaceSurfaceActual.requestDismissal;
begin
  var dismissListener := fDismissRequested;
  if assigned(dismissListener) then
    dismissListener();
end;

end.
