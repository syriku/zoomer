namespace WPFApp;

uses
  System,
  System.ComponentModel,
  System.Runtime.InteropServices,
  System.Windows,
  System.Windows.Controls,
  System.Windows.Input,
  System.Windows.Interop,
  System.Windows.Media,
  System.Windows.Media.Animation,
  System.Windows.Media.Imaging,
  System.Windows.Threading,
  Core;

type
  WindowsWorkspaceWindow = public class(Window)
  private
    fRoot: Grid;
    fImage: System.Windows.Controls.Image;
    fImageTransform: MatrixTransform;
    fHud: Border;
    fHudText: TextBlock;
    fHudDelayTimer: DispatcherTimer;
    fQualityTimer: DispatcherTimer;
    fWindowSource: HwndSource;
    fCommandRequested: WorkspaceCommandRequested;
    fDismissRequested: WorkspaceSurfaceRequested;
    fDisplayChanged: WorkspaceSurfaceRequested;
    fTransform: WorkspaceTransform := WorkspaceTransform.identityTransform;
    fPreviousDragPoint: Point;
    fIsDragging: Boolean;
    fAllowsClose: Boolean;
    fDidRequestClose: Boolean;
    fIsClosed: Boolean;

    method imageSizeChanged(sender: Object) eventArgs(eventArgs: SizeChangedEventArgs);
    begin
      applyTransform;
    end;
    method restoreHighQuality(sender: Object) eventArgs(eventArgs: EventArgs);
    begin
      fQualityTimer.Stop;
      RenderOptions.SetBitmapScalingMode(fImage, BitmapScalingMode.HighQuality);
    end;
    method fadeHud(sender: Object) eventArgs(eventArgs: EventArgs);
    begin
      fHudDelayTimer.Stop;
      var animation := new DoubleAnimation;
      animation.From := 1.0;
      animation.To := 0.0;
      animation.Duration := new Duration(TimeSpan.FromMilliseconds(200.0));
      animation.FillBehavior := FillBehavior.HoldEnd;
      fHud.BeginAnimation(UIElement.OpacityProperty, animation);
    end;
    method applyTransform;
    begin
      if not assigned(fTransform) then
        exit;

      var scaleX := fTransform.Scale;
      var offsetX := fTransform.OffsetX;
      if fTransform.IsHorizontallyFlipped then begin
        scaleX := -fTransform.Scale;
        offsetX := fTransform.OffsetX + (fImage.ActualWidth * fTransform.Scale);
      end;

      fImageTransform.Matrix := new Matrix(scaleX, 0.0, 0.0, fTransform.Scale,
        offsetX, fTransform.OffsetY);
    end;
    method showHudForScale(scale: Double);
    begin
      fHudText.Text := String.Format('{0:0}%', scale * 100.0);
      fHud.BeginAnimation(UIElement.OpacityProperty, nil);
      fHud.Opacity := 1.0;
      fHudDelayTimer.Stop;
      fHudDelayTimer.Start;
    end;
    method endDrag;
    begin
      if not fIsDragging then
        exit;
      fIsDragging := false;
      if IsMouseCaptured then
        Mouse.Capture(nil);
      Cursor := Cursors.Hand;
    end;
    method requestCommand(command: WorkspaceCommand);
    begin
      var listener := fCommandRequested;
      if assigned(listener) then
        listener(command);
    end;
    method requestDismissal;
    begin
      var listener := fDismissRequested;
      if assigned(listener) then
        listener();
    end;
    method tryHandlePresetScale(eventArgs: KeyEventArgs): Boolean;
    begin
      if eventArgs.IsRepeat then
        exit false;

      var modifiers := Keyboard.Modifiers;
      var isZeroShortcut := (modifiers = ModifierKeys.None) or (modifiers = ModifierKeys.Control);
      if ((eventArgs.Key = Key.D0) or (eventArgs.Key = Key.NumPad0)) and isZeroShortcut then begin
        requestCommand(WorkspaceCommand.resetScaleInViewport(fRoot.ActualWidth) height(fRoot.ActualHeight));
        eventArgs.Handled := true;
        exit true;
      end;

      if modifiers <> ModifierKeys.None then
        exit false;

      var requestedScale: Double := 0.0;
      case eventArgs.Key of
        Key.D1, Key.NumPad1: requestedScale := 1.5;
        Key.D2, Key.NumPad2: requestedScale := 2.0;
        Key.D9, Key.NumPad9: requestedScale := 0.7;
      else
        exit false;
      end;

      requestCommand(WorkspaceCommand.presetScale(requestedScale)
        inViewportWidth(fRoot.ActualWidth) height(fRoot.ActualHeight));
      eventArgs.Handled := true;
      result := true;
    end;
    method hasNoShortcutModifiers: Boolean;
    begin
      result := Keyboard.Modifiers = ModifierKeys.None;
    end;
    method windowMessageHook(windowHandle: IntPtr) message(message: Int32) wParam(wParam: IntPtr) lParam(lParam: IntPtr) handled(var handled: Boolean): IntPtr;
    begin
      if message = WindowsNative.WindowMessageMouseHorizontalWheel then begin
        requestCommand(WorkspaceCommand.panWithDeltaX(WindowsNative.signedHighWord(wParam) / 4.0) deltaY(0.0));
        handled := true;
      end;
      if message = WindowsNative.WindowMessageDisplayChange then begin
        var listener := fDisplayChanged;
        if assigned(listener) then
          listener();
      end;
      result := IntPtr.Zero;
    end;
  protected
    method OnMouseLeftButtonDown(eventArgs: MouseButtonEventArgs); override;
    begin
      inherited OnMouseLeftButtonDown(eventArgs);
      fIsDragging := true;
      fPreviousDragPoint := eventArgs.GetPosition(fRoot);
      Mouse.Capture(self);
      Cursor := Cursors.SizeAll;
      eventArgs.Handled := true;
    end;
    method OnMouseMove(eventArgs: MouseEventArgs); override;
    begin
      inherited OnMouseMove(eventArgs);
      if not fIsDragging then
        exit;
      if eventArgs.LeftButton <> MouseButtonState.Pressed then begin
        endDrag;
        exit;
      end;

      var currentPoint := eventArgs.GetPosition(fRoot);
      requestCommand(WorkspaceCommand.panWithDeltaX(currentPoint.X - fPreviousDragPoint.X)
        deltaY(currentPoint.Y - fPreviousDragPoint.Y));
      fPreviousDragPoint := currentPoint;
      eventArgs.Handled := true;
    end;
    method OnMouseLeftButtonUp(eventArgs: MouseButtonEventArgs); override;
    begin
      inherited OnMouseLeftButtonUp(eventArgs);
      endDrag;
      eventArgs.Handled := true;
    end;
    method OnPreviewMouseWheel(eventArgs: MouseWheelEventArgs); override;
    begin
      inherited OnPreviewMouseWheel(eventArgs);
      if (Keyboard.Modifiers and ModifierKeys.Control) <> ModifierKeys.None then
        requestCommand(WorkspaceCommand.magnifyWithAmount(eventArgs.Delta / 1200.0)
          inViewportWidth(fRoot.ActualWidth) height(fRoot.ActualHeight))
      else
        requestCommand(WorkspaceCommand.scrollZoomWithDelta(eventArgs.Delta / 12.0)
          inViewportWidth(fRoot.ActualWidth) height(fRoot.ActualHeight));
      eventArgs.Handled := true;
    end;
    method OnPreviewKeyDown(eventArgs: KeyEventArgs); override;
    begin
      if tryHandlePresetScale(eventArgs) then
        exit;

      case eventArgs.Key of
        Key.Escape:
          begin
            requestDismissal;
            eventArgs.Handled := true;
            exit;
          end;

        Key.R:
          if (not eventArgs.IsRepeat) and hasNoShortcutModifiers then begin
            requestCommand(WorkspaceCommand.resetWorkspace);
            eventArgs.Handled := true;
            exit;
          end;

        Key.C:
          if (not eventArgs.IsRepeat) and hasNoShortcutModifiers then begin
            requestCommand(WorkspaceCommand.centerInViewport(fRoot.ActualWidth) height(fRoot.ActualHeight));
            eventArgs.Handled := true;
            exit;
          end;

        Key.M:
          if not eventArgs.IsRepeat then begin
            requestCommand(WorkspaceCommand.toggleHorizontalFlip);
            eventArgs.Handled := true;
            exit;
          end;
      end;

      inherited OnPreviewKeyDown(eventArgs);
    end;
    method OnClosing(eventArgs: CancelEventArgs); override;
    begin
      if not fAllowsClose then begin
        eventArgs.Cancel := true;
        if not fDidRequestClose then begin
          fDidRequestClose := true;
          Dispatcher.BeginInvoke(new Action(method
            begin
              requestDismissal;
            end));
        end;
      end;
      inherited OnClosing(eventArgs);
    end;
  public
    constructor;
    begin
      AllowsTransparency := false;
      Background := Brushes.Black;
      ResizeMode := ResizeMode.NoResize;
      ShowInTaskbar := false;
      Topmost := true;
      WindowStartupLocation := WindowStartupLocation.Manual;
      WindowStyle := WindowStyle.None;
      UseLayoutRounding := true;
      Cursor := Cursors.Hand;

      fImageTransform := new MatrixTransform;
      fImage := new System.Windows.Controls.Image;
      fImage.RenderTransform := fImageTransform;
      fImage.RenderTransformOrigin := new Point(0.0, 0.0);
      fImage.SnapsToDevicePixels := true;
      fImage.Stretch := Stretch.Fill;
      fImage.SizeChanged += @imageSizeChanged;
      RenderOptions.SetBitmapScalingMode(fImage, BitmapScalingMode.HighQuality);

      fHudText := new TextBlock;
      fHudText.FontFamily := new FontFamily('Consolas');
      fHudText.FontSize := 18.0;
      fHudText.FontWeight := FontWeights.Bold;
      fHudText.Foreground := Brushes.White;
      fHudText.HorizontalAlignment := HorizontalAlignment.Center;
      fHudText.VerticalAlignment := VerticalAlignment.Center;
      fHudText.Text := '100%';

      fHud := new Border;
      fHud.Background := new SolidColorBrush(Color.FromArgb(184, 0, 0, 0));
      fHud.Child := fHudText;
      fHud.CornerRadius := new CornerRadius(7.0);
      fHud.Height := 36.0;
      fHud.HorizontalAlignment := HorizontalAlignment.Left;
      fHud.IsHitTestVisible := false;
      fHud.Margin := new Thickness(16.0);
      fHud.Opacity := 0.0;
      fHud.VerticalAlignment := VerticalAlignment.Bottom;
      fHud.Width := 88.0;

      fRoot := new Grid;
      fRoot.Background := Brushes.Black;
      fRoot.ClipToBounds := true;
      fRoot.Children.Add(fImage);
      fRoot.Children.Add(fHud);
      Content := fRoot;

      fQualityTimer := new DispatcherTimer(DispatcherPriority.Render);
      fQualityTimer.Interval := TimeSpan.FromMilliseconds(120.0);
      fQualityTimer.Tick += @restoreHighQuality;

      fHudDelayTimer := new DispatcherTimer(DispatcherPriority.Normal);
      fHudDelayTimer.Interval := TimeSpan.FromMilliseconds(800.0);
      fHudDelayTimer.Tick += @fadeHud;
    end;

    property CommandRequested: WorkspaceCommandRequested read fCommandRequested write fCommandRequested;
    property DismissRequested: WorkspaceSurfaceRequested read fDismissRequested write fDismissRequested;
    property DisplayChanged: WorkspaceSurfaceRequested read fDisplayChanged write fDisplayChanged;

    method setCapturedImage(source: BitmapSource);
    begin
      if not assigned(source) then
        raise new ArgumentNullException('source');
      fImage.Source := source;
    end;
    method showOnDisplay(display: WorkspaceDisplay);
    begin
      var bounds: WindowsRect;
      if not assigned(display) then
        raise new ArgumentNullException('display');
      if not WindowsNative.boundsForDisplay(display) rectangle(var bounds) then
        raise new InvalidOperationException('目标显示器已经不可用');
      if not assigned(fImage.Source) then
        raise new InvalidOperationException('工作区截图无效');

      Show;
      var handle := (new WindowInteropHelper(self)).Handle;
      if handle = IntPtr.Zero then
        raise new InvalidOperationException('WPF 未创建窗口句柄');

      fWindowSource := HwndSource.FromHwnd(handle);
      if not assigned(fWindowSource) then
        raise new InvalidOperationException('无法取得 WPF 窗口消息源');
      fWindowSource.AddHook(@windowMessageHook);

      if not WindowsNative.setWindowPosition(handle)
        insertAfterWindow(WindowsNative.topmostWindowHandle)
        x(bounds.Left)
        y(bounds.Top)
        width(bounds.Width)
        height(bounds.Height)
        options(WindowsNative.SetWindowPosNoOwnerZOrder or WindowsNative.SetWindowPosShowWindow) then
        raise new Win32Exception(Marshal.GetLastWin32Error, '无法定位工作区窗口');

      Activate;
      Focus;
    end;
    method renderTransform(transform: WorkspaceTransform) showHud(showHud: Boolean);
    begin
      if (not assigned(transform)) or fIsClosed then
        exit;

      fTransform := transform;
      applyTransform;
      RenderOptions.SetBitmapScalingMode(fImage, BitmapScalingMode.Linear);
      fQualityTimer.Stop;
      fQualityTimer.Start;
      if showHud then
        showHudForScale(transform.Scale);
    end;
    method closeForDismissal;
    begin
      if fIsClosed then
        exit;

      fAllowsClose := true;
      fQualityTimer.Stop;
      fHudDelayTimer.Stop;
      endDrag;
      if assigned(fWindowSource) then begin
        fWindowSource.RemoveHook(@windowMessageHook);
        fWindowSource := nil;
      end;
      fImage.Source := nil;
      Close;
      fIsClosed := true;
    end;
  end;

end.
