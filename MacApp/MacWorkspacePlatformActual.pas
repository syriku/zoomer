namespace MacApp;

uses
  AppKit,
  CoreGraphics,
  Foundation,
  RemObjects.Elements.RTL,
  ScreenCaptureKit,
  Core;

type
  MacWorkspacePlatformActual = public class(IWorkspacePlatformActual)
  private
    method screenContainingPointer: NSScreen;
    begin
      var pointerLocation := NSEvent.mouseLocation;
      for each screen: NSScreen in NSScreen.screens do begin
        if NSPointInRect(pointerLocation, screen.frame) then
          exit screen;
      end;

      result := nil;
    end;
    method workspaceDisplayForScreen(screen: NSScreen): WorkspaceDisplay;
    begin
      var identifier := identifierForScreen(screen);
      if identifier = nil then begin
        result := nil;
        exit;
      end;

      var nativeFrame := screen.frame;
      result := new WorkspaceDisplay(identifier) originX(nativeFrame.origin.x) originY(nativeFrame.origin.y) width(nativeFrame.size.width) height(nativeFrame.size.height) backingScale(screen.backingScaleFactor);
    end;
    method identifierForScreen(screen: NSScreen): String;
    begin
      var displayNumber := screen.deviceDescription.objectForKey('NSScreenNumber') as NSNumber;
      if displayNumber = nil then begin
        result := nil;
        exit;
      end;

      result := displayNumber.stringValue;
    end;
    method shareableDisplayInContent(content: SCShareableContent) atPoint(pointerLocation: NSPoint): SCDisplay;
    begin
      for each candidate: SCDisplay in content.displays do begin
        if CGRectContainsPoint(candidate.frame, pointerLocation) then
          exit candidate;
      end;

      result := nil;
    end;
    method completeFailureWithRequestId(requestId: Int64) code(failureCode: WorkspaceFailureCode) message(failureMessage: String) completion(completion: WorkspaceCaptureCompletion);
    begin
      var failure := new WorkspaceFailure(failureCode) message(failureMessage);
      completeCaptureWithCompletion(completion) captureResult(WorkspaceCaptureResult.failedWithRequestId(requestId) failure(failure));
    end;
    method completeCaptureWithCompletion(completion: WorkspaceCaptureCompletion) captureResult(captureResult: WorkspaceCaptureResult);
    begin
      if NSThread.isMainThread then begin
        completion(captureResult);
        exit;
      end;

      NSOperationQueue.mainQueue.addOperationWithBlock(method
        begin
          completion(captureResult);
        end);
    end;
  public
    method screenRecordingPermission: WorkspacePermissionState;
    begin
      if CGPreflightScreenCaptureAccess then
        exit WorkspacePermissionState.Granted;

      // CGPreflightScreenCaptureAccess does not distinguish a first request from a
      // prior denial. Treating it as NotDetermined keeps the shared layer able to
      // request permission, while the status-menu action provides Settings access.
      result := WorkspacePermissionState.NotDetermined;
    end;
    method requestScreenRecordingPermission;
    begin
      if not NSThread.isMainThread then begin
        NSOperationQueue.mainQueue.addOperationWithBlock(method
          begin
            requestScreenRecordingPermission;
          end);
        exit;
      end;

      if CGRequestScreenCaptureAccess then
        exit;
    end;
    method openScreenRecordingSettings;
    begin
      if not NSThread.isMainThread then begin
        NSOperationQueue.mainQueue.addOperationWithBlock(method
          begin
            openScreenRecordingSettings;
          end);
        exit;
      end;

      var settingsUrl := NSURL.URLWithString('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture');
      if settingsUrl <> nil then
        NSWorkspace.sharedWorkspace.openURL(settingsUrl);
    end;
    method captureDisplayWithRequestId(requestId: Int64) completion(completion: WorkspaceCaptureCompletion);
    begin
      if completion = nil then
        exit;

      if not NSThread.isMainThread then begin
        NSOperationQueue.mainQueue.addOperationWithBlock(method
          begin
            captureDisplayWithRequestId(requestId) completion(completion);
          end);
        exit;
      end;

      if screenRecordingPermission <> WorkspacePermissionState.Granted then begin
        completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.PermissionDenied) message('需要屏幕录制权限') completion(completion);
        exit;
      end;

      var screen := screenContainingPointer;
      if screen = nil then begin
        completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.TargetDisplayUnavailable) message('无法找到鼠标所在的显示器') completion(completion);
        exit;
      end;

      var display := workspaceDisplayForScreen(screen);
      if display = nil then begin
        completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.TargetDisplayUnavailable) message('无法读取当前显示器的信息') completion(completion);
        exit;
      end;

      var pointerLocation := NSEvent.mouseLocation;
      SCShareableContent.getShareableContentWithCompletionHandler(method(content: SCShareableContent; contentError: NSError)
        begin
          if (content = nil) or (contentError <> nil) then begin
            completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.TargetDisplayUnavailable) message('无法读取可截取的显示器') completion(completion);
            exit;
          end;

          var shareableDisplay := shareableDisplayInContent(content) atPoint(pointerLocation);
          if shareableDisplay = nil then begin
            completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.TargetDisplayUnavailable) message('当前显示器不可用于截屏') completion(completion);
            exit;
          end;

          var filter := new SCContentFilter withDisplay(shareableDisplay) excludingWindows(new NSArray);
          var configuration := new SCStreamConfiguration;
          // ScreenCaptureKit defaults to a logical-size image. Request native backing
          // pixels explicitly so a Retina display is not captured at half resolution.
          configuration.width := UInt64(Math.Round(display.Width * display.BackingScale));
          configuration.height := UInt64(Math.Round(display.Height * display.BackingScale));
          configuration.showsCursor := false;
          configuration.backgroundColor := NSColor.blackColor.CGColor;

          SCScreenshotManager.captureImageWithFilter(filter) configuration(configuration) completionHandler(method(image: CGImage; captureError: NSError)
            begin
              if (image = nil) or (captureError <> nil) then begin
                completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.CaptureFailed) message('无法截取当前显示器') completion(completion);
                exit;
              end;

              // NSImage retains the CGImage. Keep the capture in ARC-managed Objective-C
              // objects before moving the result to the main queue; do not manually retain
              // and release a Core Graphics image across the asynchronous handoff.
              var nativeImage := new NSImage withCGImage(image) size(NSMakeSize(0.0, 0.0));
              if nativeImage = nil then begin
                completeFailureWithRequestId(requestId) code(WorkspaceFailureCode.CaptureFailed) message('无法创建截图图像') completion(completion);
                exit;
              end;

              NSOperationQueue.mainQueue.addOperationWithBlock(method
                begin
                  var frame := new MacWorkspaceFrame(nativeImage);
                  completeCaptureWithCompletion(completion) captureResult(WorkspaceCaptureResult.succeededWithRequestId(requestId) frame(frame) onDisplay(display));
                end);
            end);
        end);
    end;
    method createWorkspaceSurface: IWorkspaceSurfaceActual;
    begin
      result := new MacWorkspaceSurfaceActual;
    end;
  end;

end.
