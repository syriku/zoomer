namespace Core;

uses
  RemObjects.Elements.RTL;

type
  WorkspaceState = public (
    Idle,
    Capturing,
    Presenting,
    Dismissing
  );

  WorkspacePermissionState = public (
    Granted,
    NotDetermined,
    Denied,
    Restricted
  );

  WorkspaceFailureCode = public (
    PermissionDenied = 1,
    TargetDisplayUnavailable,
    CaptureFailed,
    CaptureCancelled,
    PresentationFailed,
    PlatformActualFailed
  );

  WorkspaceCommandKind = public (
    Dismiss,
    ScrollZoom,
    Magnify,
    Pan,
    ResetScale,
    ResetWorkspace,
    Center,
    PresetScale,
    ToggleHorizontalFlip
  );

  // A frame is owned by Shared until presentFrame reports success. The surface then
  // owns it exclusively and must release it when the presentation is dismissed.
  IWorkspaceFrame = public interface
    method releaseFrame;
  end;

  WorkspaceFailure = public class
  private
    fCode: WorkspaceFailureCode;
    fMessage: String;
  public
    constructor(failureCode: WorkspaceFailureCode) message(text: String);
    begin
      fCode := failureCode;
      fMessage := text;
    end;
    property Code: WorkspaceFailureCode read fCode write fCode;
    property Message: String read fMessage write fMessage;

    class method defaultMessageForCode(code: WorkspaceFailureCode): String;
    begin
      case code of
        WorkspaceFailureCode.PermissionDenied:
          result := '需要屏幕录制权限';
        WorkspaceFailureCode.TargetDisplayUnavailable:
          result := '无法找到当前显示器';
        WorkspaceFailureCode.CaptureCancelled:
          result := '截屏已取消';
        WorkspaceFailureCode.PresentationFailed:
          result := '无法显示工作区';
        WorkspaceFailureCode.PlatformActualFailed:
          result := '平台工作区实现不可用';
      else
        result := '无法截取当前显示器';
      end;
    end;
    class method withDefaultMessageForCode(code: WorkspaceFailureCode): WorkspaceFailure;
    begin
      result := new WorkspaceFailure(code) message(defaultMessageForCode(code));
    end;
  end;

  WorkspaceDisplay = public class
  private
    fDisplayId: String;
    fOriginX: Double;
    fOriginY: Double;
    fWidth: Double;
    fHeight: Double;
    fBackingScale: Double;
  public
    constructor(identifier: String) originX(x: Double) originY(y: Double) width(displayWidth: Double) height(displayHeight: Double) backingScale(scale: Double);
    begin
      fDisplayId := identifier;
      fOriginX := x;
      fOriginY := y;
      fWidth := displayWidth;
      fHeight := displayHeight;
      fBackingScale := scale;
    end;
    property DisplayId: String read fDisplayId write fDisplayId;
    property OriginX: Double read fOriginX write fOriginX;
    property OriginY: Double read fOriginY write fOriginY;
    property Width: Double read fWidth write fWidth;
    property Height: Double read fHeight write fHeight;
    property BackingScale: Double read fBackingScale write fBackingScale;
  end;

  WorkspaceTransform = public class
  private
    fScale: Double;
    fOffsetX: Double;
    fOffsetY: Double;
    fIsHorizontallyFlipped: Boolean;
  public
    constructor(initialScale: Double) offsetX(x: Double) offsetY(y: Double) horizontallyFlipped(flipped: Boolean);
    begin
      fScale := initialScale;
      fOffsetX := x;
      fOffsetY := y;
      fIsHorizontallyFlipped := flipped;
    end;
    property Scale: Double read fScale write fScale;
    property OffsetX: Double read fOffsetX write fOffsetX;
    property OffsetY: Double read fOffsetY write fOffsetY;
    property IsHorizontallyFlipped: Boolean read fIsHorizontallyFlipped write fIsHorizontallyFlipped;

    class method identityTransform: WorkspaceTransform;
    begin
      result := new WorkspaceTransform(1.0) offsetX(0.0) offsetY(0.0) horizontallyFlipped(false);
    end;
  end;

  WorkspaceRenderState = public class
  private
    fTransform: WorkspaceTransform;
    fShowsHud: Boolean;
  public
    constructor(renderTransform: WorkspaceTransform) showHud(hud: Boolean);
    begin
      fTransform := renderTransform;
      fShowsHud := hud;
    end;
    property Transform: WorkspaceTransform read fTransform write fTransform;
    property ShowsHud: Boolean read fShowsHud write fShowsHud;
  end;

  WorkspaceCaptureResult = public class
  private
    fRequestId: Int64;
    fFrame: IWorkspaceFrame;
    fDisplay: WorkspaceDisplay;
    fFailure: WorkspaceFailure;
    method get_IsSuccess: Boolean;
    begin
      result := assigned(fFrame) and assigned(fDisplay) and not assigned(fFailure);
    end;
  public
    constructor(captureRequestId: Int64) frame(capturedFrame: IWorkspaceFrame) onDisplay(captureDisplay: WorkspaceDisplay) failure(failureValue: WorkspaceFailure);
    begin
      fRequestId := captureRequestId;
      fFrame := capturedFrame;
      fDisplay := captureDisplay;
      fFailure := failureValue;
    end;
    property RequestId: Int64 read fRequestId write fRequestId;
    property Frame: IWorkspaceFrame read fFrame write fFrame;
    property Display: WorkspaceDisplay read fDisplay write fDisplay;
    property Failure: WorkspaceFailure read fFailure write fFailure;
    property IsSuccess: Boolean read get_IsSuccess;

    class method succeededWithRequestId(requestId: Int64) frame(capturedFrame: IWorkspaceFrame) onDisplay(display: WorkspaceDisplay): WorkspaceCaptureResult;
    begin
      result := new WorkspaceCaptureResult(requestId) frame(capturedFrame) onDisplay(display) failure(nil);
    end;
    class method failedWithRequestId(requestId: Int64) failure(failureValue: WorkspaceFailure): WorkspaceCaptureResult;
    begin
      result := new WorkspaceCaptureResult(requestId) frame(nil) onDisplay(nil) failure(failureValue);
    end;
  end;

  WorkspacePresentationResult = public class
  private
    fIsSuccess: Boolean;
    fFailure: WorkspaceFailure;
  public
    constructor(didSucceed: Boolean) failure(failureValue: WorkspaceFailure);
    begin
      fIsSuccess := didSucceed;
      fFailure := failureValue;
    end;
    property IsSuccess: Boolean read fIsSuccess write fIsSuccess;
    property Failure: WorkspaceFailure read fFailure write fFailure;

    class method succeeded: WorkspacePresentationResult;
    begin
      result := new WorkspacePresentationResult(true) failure(nil);
    end;
    class method failedWithFailure(failureValue: WorkspaceFailure): WorkspacePresentationResult;
    begin
      result := new WorkspacePresentationResult(false) failure(failureValue);
    end;
  end;

  WorkspaceCommand = public class
  private
    fKind: WorkspaceCommandKind;
    fFirstValue: Double;
    fSecondValue: Double;
    fThirdValue: Double;

    constructor(aKind: WorkspaceCommandKind) firstValue(first: Double) secondValue(second: Double) thirdValue(third: Double);
    begin
      fKind := aKind;
      fFirstValue := first;
      fSecondValue := second;
      fThirdValue := third;
    end;
  public
    property Kind: WorkspaceCommandKind read fKind write fKind;
    property FirstValue: Double read fFirstValue write fFirstValue;
    property SecondValue: Double read fSecondValue write fSecondValue;
    property ThirdValue: Double read fThirdValue write fThirdValue;

    class method dismiss: WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.Dismiss) firstValue(0.0) secondValue(0.0) thirdValue(0.0);
    end;
    class method scrollZoomWithDelta(delta: Double) atX(anchorX: Double) atY(anchorY: Double): WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.ScrollZoom) firstValue(delta) secondValue(anchorX) thirdValue(anchorY);
    end;
    class method magnifyWithAmount(magnification: Double) atX(anchorX: Double) atY(anchorY: Double): WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.Magnify) firstValue(magnification) secondValue(anchorX) thirdValue(anchorY);
    end;
    class method panWithDeltaX(deltaX: Double) deltaY(y: Double): WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.Pan) firstValue(deltaX) secondValue(y) thirdValue(0.0);
    end;
    class method resetScaleInViewport(width: Double) height(viewportHeight: Double): WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.ResetScale) firstValue(0.0) secondValue(width) thirdValue(viewportHeight);
    end;
    class method resetWorkspace: WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.ResetWorkspace) firstValue(0.0) secondValue(0.0) thirdValue(0.0);
    end;
    class method centerInViewport(width: Double) height(viewportHeight: Double): WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.Center) firstValue(width) secondValue(viewportHeight) thirdValue(0.0);
    end;
    class method presetScaleAtAnchor(scale: Double) atX(anchorX: Double) atY(anchorY: Double): WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.PresetScale) firstValue(scale) secondValue(anchorX) thirdValue(anchorY);
    end;
    class method toggleHorizontalFlip: WorkspaceCommand;
    begin
      result := new WorkspaceCommand(WorkspaceCommandKind.ToggleHorizontalFlip) firstValue(0.0) secondValue(0.0) thirdValue(0.0);
    end;
  end;

  WorkspaceStateSnapshot = public class
  private
    fState: WorkspaceState;
    fStatusText: String;
    fRequestId: Int64;
    fTransform: WorkspaceTransform;
  public
    constructor(workspaceState: WorkspaceState) statusText(text: String) requestId(id: Int64) transform(currentTransform: WorkspaceTransform);
    begin
      fState := workspaceState;
      fStatusText := text;
      fRequestId := id;
      fTransform := currentTransform;
    end;
    property State: WorkspaceState read fState write fState;
    property StatusText: String read fStatusText write fStatusText;
    property RequestId: Int64 read fRequestId write fRequestId;
    property Transform: WorkspaceTransform read fTransform write fTransform;
  end;

  WorkspaceCaptureCompletion = public block(&result: WorkspaceCaptureResult);
  WorkspaceStateChanged = public block(snapshot: WorkspaceStateSnapshot);
  WorkspaceCommandRequested = public block(command: WorkspaceCommand);
  WorkspaceSurfaceRequested = public block;

  IWorkspacePlatformActual = public interface
    method screenRecordingPermission: WorkspacePermissionState;
    method requestScreenRecordingPermission;
    method captureDisplayWithRequestId(requestId: Int64) completion(completion: WorkspaceCaptureCompletion);
    method createWorkspaceSurface: IWorkspaceSurfaceActual;
  end;

  IWorkspaceSurfaceActual = public interface
    property CommandRequested: WorkspaceCommandRequested read write;
    property DismissRequested: WorkspaceSurfaceRequested read write;
    property TargetDisplayDisconnected: WorkspaceSurfaceRequested read write;

    method presentFrame(workspaceFrame: IWorkspaceFrame) onDisplay(display: WorkspaceDisplay): WorkspacePresentationResult;
    method renderTransform(transform: WorkspaceTransform) showHud(showHud: Boolean);
    method dismissPresentation;
  end;

  WorkspaceActuals = public static class
  private
    class field fRegisteredPlatformActual: IWorkspacePlatformActual;
  public
    class method registerPlatformActual(actual: IWorkspacePlatformActual);
    begin
      if not assigned(actual) then
        raise new Exception('平台工作区实现不能为空');

      if assigned(fRegisteredPlatformActual) then
        raise new Exception('平台工作区实现只能在启动时注册一次');

      fRegisteredPlatformActual := actual;
    end;
    class method createSessionUsingRegisteredPlatform: WorkspaceSession;
    begin
      if not assigned(fRegisteredPlatformActual) then
        raise new Exception('必须先注册平台工作区实现');

      result := new WorkspaceSession(fRegisteredPlatformActual);
    end;
  end;

end.
