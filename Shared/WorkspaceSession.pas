namespace Core;

interface

uses
  RemObjects.Elements.RTL;

type
  WorkspaceSession = public class
  private
    fPlatformActual: IWorkspacePlatformActual;
    fTransformModel: WorkspaceTransformModel := new WorkspaceTransformModel();
    fSurface: IWorkspaceSurfaceActual;
    fRequestId: Int64;
    fState: WorkspaceState := WorkspaceState.Idle;
    fStatusText: String := '空闲';
    fIsDisposed: Boolean;

    method get_State: WorkspaceState;
    method get_StatusText: String;
    method get_RequestId: Int64;
    method get_Transform: WorkspaceTransform;
    method get_RenderState: WorkspaceRenderState;
    method get_IsDisposed: Boolean;
    method captureDidComplete(captureResult: WorkspaceCaptureResult);
    method presentCapture(captureResult: WorkspaceCaptureResult);
    method wireSurface(surface: IWorkspaceSurfaceActual);
    method dismissUnownedSurface(surface: IWorkspaceSurfaceActual);
    method dismissCurrentSurface;
    method unwireSurface(surface: IWorkspaceSurfaceActual);
    method renderCurrentTransform(showHud: Boolean);
    method releaseFrameIfPresent(workspaceFrame: IWorkspaceFrame);
    method setState(aState: WorkspaceState) statusText(text: String);
    method statusTextForPermission(permission: WorkspacePermissionState): String;
    method statusTextForFailure(failure: WorkspaceFailure) fallback(fallbackText: String): String;
    method ensureNotDisposed;
  public
    constructor(platformActual: IWorkspacePlatformActual);

    property StateChanged: WorkspaceStateChanged;
    property State: WorkspaceState read get_State;
    property StatusText: String read get_StatusText;
    property RequestId: Int64 read get_RequestId;
    property Transform: WorkspaceTransform read get_Transform;
    property RenderState: WorkspaceRenderState read get_RenderState;
    property IsDisposed: Boolean read get_IsDisposed;

    method requestPresentation;
    method dismissWorkspace;
    method handleCommand(command: WorkspaceCommand);
    method disposeSession;
  end;

implementation

constructor WorkspaceSession(platformActual: IWorkspacePlatformActual);
begin
  if not assigned(platformActual) then
    raise new Exception('平台工作区实现不能为空');

  fPlatformActual := platformActual;
end;

method WorkspaceSession.get_State: WorkspaceState;
begin
  result := fState;
end;

method WorkspaceSession.get_StatusText: String;
begin
  result := fStatusText;
end;

method WorkspaceSession.get_RequestId: Int64;
begin
  result := fRequestId;
end;

method WorkspaceSession.get_Transform: WorkspaceTransform;
begin
  result := fTransformModel.Transform;
end;

method WorkspaceSession.get_RenderState: WorkspaceRenderState;
begin
  result := new WorkspaceRenderState(Transform) showHud(false);
end;

method WorkspaceSession.get_IsDisposed: Boolean;
begin
  result := fIsDisposed;
end;

method WorkspaceSession.requestPresentation;
var
  permission: WorkspacePermissionState;
  captureRequestId: Int64;
begin
  ensureNotDisposed();
  if fState <> WorkspaceState.Idle then
    exit;

  try
    permission := fPlatformActual.screenRecordingPermission();
  except
    setState(WorkspaceState.Idle) statusText('无法检查屏幕录制权限');
    exit;
  end;

  if permission <> WorkspacePermissionState.Granted then begin
    try
      fPlatformActual.requestScreenRecordingPermission();
    except
      setState(WorkspaceState.Idle) statusText('无法请求屏幕录制权限');
      exit;
    end;

    setState(WorkspaceState.Idle) statusText(statusTextForPermission(permission));
    exit;
  end;

  fRequestId := fRequestId + 1;
  captureRequestId := fRequestId;
  setState(WorkspaceState.Capturing) statusText('正在截屏');

  try
    fPlatformActual.captureDisplayWithRequestId(captureRequestId) completion(@captureDidComplete);
  except
    if (not fIsDisposed) and (fState = WorkspaceState.Capturing) and (captureRequestId = fRequestId) then
      setState(WorkspaceState.Idle) statusText('无法截取当前显示器');
  end;
end;

method WorkspaceSession.dismissWorkspace;
begin
  if (fState = WorkspaceState.Idle) or (fState = WorkspaceState.Dismissing) then
    exit;

  fRequestId := fRequestId + 1;
  setState(WorkspaceState.Dismissing) statusText('正在关闭');
  dismissCurrentSurface();
  fTransformModel.resetTransform();
  setState(WorkspaceState.Idle) statusText('空闲');
end;

method WorkspaceSession.handleCommand(command: WorkspaceCommand);
begin
  if fIsDisposed or (fState <> WorkspaceState.Presenting) or not assigned(command) then
    exit;

  case command.Kind of
    WorkspaceCommandKind.Dismiss:
      dismissWorkspace();

    WorkspaceCommandKind.ScrollZoom:
      if fTransformModel.zoomByScrollDelta(command.FirstValue) atX(command.SecondValue) atY(command.ThirdValue) then
        renderCurrentTransform(true);

    WorkspaceCommandKind.Magnify:
      if fTransformModel.zoomByMagnification(command.FirstValue) atX(command.SecondValue) atY(command.ThirdValue) then
        renderCurrentTransform(true);

    WorkspaceCommandKind.Pan:
      if fTransformModel.translateBy(command.FirstValue) deltaY(command.SecondValue) then
        renderCurrentTransform(false);

    WorkspaceCommandKind.ResetScale:
      begin
        fTransformModel.resetScale();
        renderCurrentTransform(true);
      end;

    WorkspaceCommandKind.ResetWorkspace:
      begin
        fTransformModel.resetTransform();
        renderCurrentTransform(true);
      end;

    WorkspaceCommandKind.Center:
      if fTransformModel.centerInViewport(command.FirstValue) height(command.SecondValue) then
        renderCurrentTransform(false);

    WorkspaceCommandKind.PresetScale:
      if fTransformModel.setPresetScale(command.FirstValue) atX(command.SecondValue) atY(command.ThirdValue) then
        renderCurrentTransform(true);

    WorkspaceCommandKind.ToggleHorizontalFlip:
      begin
        fTransformModel.toggleHorizontalFlip();
        renderCurrentTransform(false);
      end;
  end;
end;

method WorkspaceSession.disposeSession;
begin
  if fIsDisposed then
    exit;

  fIsDisposed := true;
  fRequestId := fRequestId + 1;
  if fState <> WorkspaceState.Idle then
    setState(WorkspaceState.Dismissing) statusText('正在关闭');

  dismissCurrentSurface();
  fTransformModel.resetTransform();
  setState(WorkspaceState.Idle) statusText('已关闭');
end;

method WorkspaceSession.captureDidComplete(captureResult: WorkspaceCaptureResult);
begin
  if not assigned(captureResult) then begin
    if (not fIsDisposed) and (fState = WorkspaceState.Capturing) then
      setState(WorkspaceState.Idle) statusText('无法截取当前显示器');
    exit;
  end;

  if fIsDisposed or (fState <> WorkspaceState.Capturing) or (captureResult.RequestId <> fRequestId) then begin
    releaseFrameIfPresent(captureResult.Frame);
    exit;
  end;

  if not captureResult.IsSuccess then begin
    releaseFrameIfPresent(captureResult.Frame);
    setState(WorkspaceState.Idle) statusText(statusTextForFailure(captureResult.Failure) fallback('无法截取当前显示器'));
    exit;
  end;

  presentCapture(captureResult);
end;

method WorkspaceSession.presentCapture(captureResult: WorkspaceCaptureResult);
var
  surface: IWorkspaceSurfaceActual;
  presentationResult: WorkspacePresentationResult;
  failure: WorkspaceFailure;
begin
  try
    surface := fPlatformActual.createWorkspaceSurface();
    if not assigned(surface) then
      raise new Exception('平台未创建工作区界面');

    wireSurface(surface);
    presentationResult := surface.presentFrame(captureResult.Frame) onDisplay(captureResult.Display);
  except
    dismissUnownedSurface(surface);
    releaseFrameIfPresent(captureResult.Frame);
    setState(WorkspaceState.Idle) statusText('无法创建工作区界面');
    exit;
  end;

  if (not assigned(presentationResult)) or (not presentationResult.IsSuccess) then begin
    dismissUnownedSurface(surface);
    releaseFrameIfPresent(captureResult.Frame);
    failure := nil;
    if assigned(presentationResult) then
      failure := presentationResult.Failure;
    setState(WorkspaceState.Idle) statusText(statusTextForFailure(failure) fallback('无法显示工作区'));
    exit;
  end;

  // Ownership transferred to the surface only after the successful result above.
  fSurface := surface;
  fTransformModel.resetTransform();
  try
    fSurface.renderTransform(fTransformModel.Transform) showHud(true);
  except
    dismissCurrentSurface();
    fTransformModel.resetTransform();
    setState(WorkspaceState.Idle) statusText('无法显示工作区');
    exit;
  end;

  setState(WorkspaceState.Presenting) statusText('工作模式');
end;

method WorkspaceSession.wireSurface(surface: IWorkspaceSurfaceActual);
begin
  surface.CommandRequested := @handleCommand;
  surface.DismissRequested := @dismissWorkspace;
  surface.TargetDisplayDisconnected := @dismissWorkspace;
end;

method WorkspaceSession.dismissUnownedSurface(surface: IWorkspaceSurfaceActual);
begin
  if not assigned(surface) then
    exit;

  unwireSurface(surface);
  try
    surface.dismissPresentation();
  except
    // Shared still owns a failed presentation frame and releases it afterwards.
  end;
end;

method WorkspaceSession.dismissCurrentSurface;
var
  surface: IWorkspaceSurfaceActual;
begin
  surface := fSurface;
  fSurface := nil;
  if not assigned(surface) then
    exit;

  unwireSurface(surface);
  try
    surface.dismissPresentation();
  except
    // The actual still owns a successfully presented frame even if dismissal reports an error.
  end;
end;

method WorkspaceSession.unwireSurface(surface: IWorkspaceSurfaceActual);
begin
  surface.CommandRequested := nil;
  surface.DismissRequested := nil;
  surface.TargetDisplayDisconnected := nil;
end;

method WorkspaceSession.renderCurrentTransform(showHud: Boolean);
begin
  if not assigned(fSurface) then
    exit;

  try
    fSurface.renderTransform(fTransformModel.Transform) showHud(showHud);
  except
    dismissCurrentSurface();
    fTransformModel.resetTransform();
    setState(WorkspaceState.Idle) statusText('无法更新工作区');
  end;
end;

method WorkspaceSession.releaseFrameIfPresent(workspaceFrame: IWorkspaceFrame);
begin
  if not assigned(workspaceFrame) then
    exit;

  try
    workspaceFrame.releaseFrame();
  except
    // A release failure must not revive or block a stale workspace request.
  end;
end;

method WorkspaceSession.setState(aState: WorkspaceState) statusText(text: String);
var
  stateChangedListener: WorkspaceStateChanged;
begin
  fState := aState;
  fStatusText := text;
  stateChangedListener := StateChanged;
  if assigned(stateChangedListener) then
    stateChangedListener(new WorkspaceStateSnapshot(aState) statusText(text) requestId(fRequestId) transform(fTransformModel.Transform));
end;

method WorkspaceSession.statusTextForPermission(permission: WorkspacePermissionState): String;
begin
  case permission of
    WorkspacePermissionState.Denied:
      result := '已拒绝屏幕录制权限';
    WorkspacePermissionState.Restricted:
      result := '屏幕录制权限不可用';
  else
    result := '需要屏幕录制权限';
  end;
end;

method WorkspaceSession.statusTextForFailure(failure: WorkspaceFailure) fallback(fallbackText: String): String;
var
  failureMessage: String;
begin
  if not assigned(failure) then
    exit fallbackText;

  failureMessage := failure.Message;
  if assigned(failureMessage) and (failureMessage <> '') then
    exit failureMessage;

  result := WorkspaceFailure.defaultMessageForCode(failure.Code);
end;

method WorkspaceSession.ensureNotDisposed;
begin
  if fIsDisposed then
    raise new Exception('工作区会话已经关闭');
end;

end.
