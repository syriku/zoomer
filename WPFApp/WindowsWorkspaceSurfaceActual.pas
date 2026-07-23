namespace WPFApp;

uses
  System,
  System.Windows.Threading,
  Core;

type
  WindowsWorkspaceSurfaceActual = public class(IWorkspaceSurfaceActual)
  private
    fDispatcher: Dispatcher;
    fCommandRequested: WorkspaceCommandRequested;
    fDismissRequested: WorkspaceSurfaceRequested;
    fTargetDisplayDisconnected: WorkspaceSurfaceRequested;
    fWindow: WindowsWorkspaceWindow;
    fOwnedFrame: WindowsWorkspaceFrame;
    fTargetDisplay: WorkspaceDisplay;
    fIsDismissing: Boolean;
    fDidRequestDisplayDismissal: Boolean;

    method workspaceCommandRequested(command: WorkspaceCommand);
    begin
      var listener := fCommandRequested;
      if assigned(listener) then
        listener(command);
    end;
    method workspaceDismissRequested;
    begin
      var listener := fDismissRequested;
      if assigned(listener) then
        listener();
    end;
    method workspaceDisplayChanged;
    begin
      fDispatcher.BeginInvoke(new Action(method
        begin
          checkTargetDisplayAvailability;
        end));
    end;
    method checkTargetDisplayAvailability;
    begin
      var currentBounds: WindowsRect;
      if fIsDismissing or fDidRequestDisplayDismissal or (not assigned(fTargetDisplay)) then
        exit;

      if WindowsNative.boundsForDisplay(fTargetDisplay) rectangle(var currentBounds) and
        (currentBounds.Left = Int32(Math.Round(fTargetDisplay.OriginX))) and
        (currentBounds.Top = Int32(Math.Round(fTargetDisplay.OriginY))) and
        (currentBounds.Width = Int32(Math.Round(fTargetDisplay.Width))) and
        (currentBounds.Height = Int32(Math.Round(fTargetDisplay.Height))) then
        exit;

      fDidRequestDisplayDismissal := true;
      var listener := fTargetDisplayDisconnected;
      if assigned(listener) then
        listener();
    end;
    method releaseOwnedFrame;
    begin
      if not assigned(fOwnedFrame) then
        exit;
      fOwnedFrame.releaseFrame;
      fOwnedFrame := nil;
    end;
    method clearPresentationWithoutReleasingFrame;
    begin
      fWindow := nil;
      fOwnedFrame := nil;
      fTargetDisplay := nil;
      fDidRequestDisplayDismissal := false;
    end;
    method failedPresentationWithMessage(message: String): WorkspacePresentationResult;
    begin
      result := WorkspacePresentationResult.failedWithFailure(
        new WorkspaceFailure(WorkspaceFailureCode.PresentationFailed) message(message));
    end;
  public
    constructor(dispatcher: Dispatcher);
    begin
      if not assigned(dispatcher) then
        raise new ArgumentNullException('dispatcher');
      fDispatcher := dispatcher;
    end;

    property CommandRequested: WorkspaceCommandRequested read fCommandRequested write fCommandRequested;
    property DismissRequested: WorkspaceSurfaceRequested read fDismissRequested write fDismissRequested;
    property TargetDisplayDisconnected: WorkspaceSurfaceRequested read fTargetDisplayDisconnected write fTargetDisplayDisconnected;

    method presentFrame(workspaceFrame: IWorkspaceFrame) onDisplay(display: WorkspaceDisplay): WorkspacePresentationResult;
    begin
      if not fDispatcher.CheckAccess then
        exit failedPresentationWithMessage('工作区界面必须在 WPF 界面线程显示');
      if assigned(fWindow) then
        exit failedPresentationWithMessage('工作区已经显示');

      var nativeFrame := workspaceFrame as WindowsWorkspaceFrame;
      if (not assigned(nativeFrame)) or nativeFrame.IsReleased then
        exit failedPresentationWithMessage('无法显示工作区：截图无效');
      if not assigned(display) then
        exit failedPresentationWithMessage('无法显示工作区：显示器信息无效');

      var source := nativeFrame.sourceForPresentation;
      if not assigned(source) then
        exit failedPresentationWithMessage('无法显示工作区：截图已经释放');

      var newWindow: WindowsWorkspaceWindow := nil;
      try
        newWindow := new WindowsWorkspaceWindow;
        newWindow.CommandRequested := @workspaceCommandRequested;
        newWindow.DismissRequested := @workspaceDismissRequested;
        newWindow.DisplayChanged := @workspaceDisplayChanged;
        newWindow.setCapturedImage(source);
        newWindow.showOnDisplay(display);

        fWindow := newWindow;
        fOwnedFrame := nativeFrame;
        fTargetDisplay := display;
        fDidRequestDisplayDismissal := false;
        result := WorkspacePresentationResult.succeeded;
      except
        on presentationError: Exception do begin
          if assigned(newWindow) then begin
            newWindow.CommandRequested := nil;
            newWindow.DismissRequested := nil;
            newWindow.DisplayChanged := nil;
            try
              newWindow.closeForDismissal;
            except
              // Shared still owns the frame on a failed presentation.
            end;
          end;
          clearPresentationWithoutReleasingFrame;
          result := failedPresentationWithMessage('无法显示工作区：' + presentationError.Message);
        end;
      end;
    end;
    method renderTransform(transform: WorkspaceTransform) showHud(showHud: Boolean);
    begin
      if not fDispatcher.CheckAccess then begin
        fDispatcher.BeginInvoke(new Action(method
          begin
            renderTransform(transform) showHud(showHud);
          end));
        exit;
      end;

      if (not assigned(fWindow)) or (not assigned(transform)) then
        exit;
      fWindow.renderTransform(transform) showHud(showHud);
    end;
    method dismissPresentation;
    begin
      if not fDispatcher.CheckAccess then begin
        fDispatcher.BeginInvoke(new Action(method
          begin
            dismissPresentation;
          end));
        exit;
      end;
      if fIsDismissing then
        exit;

      fIsDismissing := true;
      if assigned(fWindow) then begin
        fWindow.CommandRequested := nil;
        fWindow.DismissRequested := nil;
        fWindow.DisplayChanged := nil;
        try
          fWindow.closeForDismissal;
        except
          // The surface still owns and releases the successfully presented frame.
        end;
      end;

      releaseOwnedFrame;
      clearPresentationWithoutReleasingFrame;
      fIsDismissing := false;
    end;
  end;

end.
