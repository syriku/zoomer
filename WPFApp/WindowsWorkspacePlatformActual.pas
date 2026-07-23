namespace WPFApp;

uses
  System,
  System.ComponentModel,
  System.Windows,
  System.Windows.Interop,
  System.Windows.Media.Imaging,
  System.Windows.Threading,
  Core;

type
  WindowsWorkspacePlatformActual = public class(IWorkspacePlatformActual)
  private
    fDispatcher: Dispatcher;

    method captureBitmapForDisplay(display: WorkspaceDisplay): BitmapSource;
    begin
      var bounds: WindowsRect;
      var screenContext: IntPtr;
      var memoryContext: IntPtr;
      var bitmapHandle: IntPtr;
      var previousObject: IntPtr;
      if not WindowsNative.boundsForDisplay(display) rectangle(var bounds) then
        raise new InvalidOperationException('目标显示器已经不可用');

      screenContext := IntPtr.Zero;
      memoryContext := IntPtr.Zero;
      bitmapHandle := IntPtr.Zero;
      previousObject := IntPtr.Zero;
      try
        screenContext := WindowsNative.getDeviceContext(IntPtr.Zero);
        if screenContext = IntPtr.Zero then
          raise new Win32Exception('无法读取桌面设备上下文');

        memoryContext := WindowsNative.createCompatibleDeviceContext(screenContext);
        if memoryContext = IntPtr.Zero then
          raise new Win32Exception('无法创建截图设备上下文');

        bitmapHandle := WindowsNative.createCompatibleBitmap(screenContext) width(bounds.Width) height(bounds.Height);
        if bitmapHandle = IntPtr.Zero then
          raise new Win32Exception('无法创建截图位图');

        previousObject := WindowsNative.selectGraphicsObject(memoryContext) graphicsObject(bitmapHandle);
        if previousObject = IntPtr.Zero then
          raise new Win32Exception('无法选择截图位图');

        if not WindowsNative.copyPixels(memoryContext)
          destinationX(0)
          destinationY(0)
          width(bounds.Width)
          height(bounds.Height)
          sourceContext(screenContext)
          sourceX(bounds.Left)
          sourceY(bounds.Top)
          operation(WindowsNative.SourceCopy or WindowsNative.CaptureBlt) then
          raise new Win32Exception('无法复制桌面像素');

        result := Imaging.CreateBitmapSourceFromHBitmap(bitmapHandle,
          IntPtr.Zero,
          Int32Rect.Empty,
          BitmapSizeOptions.FromEmptyOptions);
        result.Freeze;
      finally
        if (memoryContext <> IntPtr.Zero) and (previousObject <> IntPtr.Zero) then
          WindowsNative.selectGraphicsObject(memoryContext) graphicsObject(previousObject);
        if bitmapHandle <> IntPtr.Zero then
          WindowsNative.deleteGraphicsObject(bitmapHandle);
        if memoryContext <> IntPtr.Zero then
          WindowsNative.deleteDeviceContext(memoryContext);
        if screenContext <> IntPtr.Zero then
          WindowsNative.releaseDeviceContext(IntPtr.Zero) deviceContext(screenContext);
      end;
    end;
    method completeCapture(completion: WorkspaceCaptureCompletion) withResult(captureResult: WorkspaceCaptureResult);
    begin
      if fDispatcher.CheckAccess then begin
        completion(captureResult);
        exit;
      end;

      fDispatcher.BeginInvoke(new Action(method
        begin
          completion(captureResult);
        end));
    end;
    method failureForRequestId(requestId: Int64) code(failureCode: WorkspaceFailureCode) message(failureMessage: String): WorkspaceCaptureResult;
    begin
      var failure := new WorkspaceFailure(failureCode) message(failureMessage);
      result := WorkspaceCaptureResult.failedWithRequestId(requestId) failure(failure);
    end;
  public
    constructor(dispatcher: Dispatcher);
    begin
      if not assigned(dispatcher) then
        raise new ArgumentNullException('dispatcher');
      fDispatcher := dispatcher;
    end;

    method screenRecordingPermission: WorkspacePermissionState;
    begin
      // Windows 桌面 GDI 截图不需要独立的屏幕录制授权。
      result := WorkspacePermissionState.Granted;
    end;
    method requestScreenRecordingPermission;
    begin
      // Windows 没有与 macOS 屏幕录制权限对应的系统授权流程。
    end;
    method captureDisplayWithRequestId(requestId: Int64) completion(completion: WorkspaceCaptureCompletion);
    begin
      if not assigned(completion) then
        exit;

      if not fDispatcher.CheckAccess then begin
        fDispatcher.BeginInvoke(new Action(method
          begin
            captureDisplayWithRequestId(requestId) completion(completion);
          end));
        exit;
      end;

      var display := WindowsNative.displayUnderPointer;
      if not assigned(display) then begin
        completeCapture(completion) withResult(failureForRequestId(requestId)
          code(WorkspaceFailureCode.TargetDisplayUnavailable)
          message('无法找到鼠标所在的显示器'));
        exit;
      end;

      try
        var source := captureBitmapForDisplay(display);
        var frame := new WindowsWorkspaceFrame(source);
        completeCapture(completion) withResult(WorkspaceCaptureResult.succeededWithRequestId(requestId) frame(frame) onDisplay(display));
      except
        on captureError: Exception do
          completeCapture(completion) withResult(failureForRequestId(requestId)
            code(WorkspaceFailureCode.CaptureFailed)
            message('无法截取当前显示器：' + captureError.Message));
      end;
    end;
    method createWorkspaceSurface: IWorkspaceSurfaceActual;
    begin
      result := new WindowsWorkspaceSurfaceActual(fDispatcher);
    end;
  end;

end.
