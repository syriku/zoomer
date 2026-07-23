namespace WPFApp;

uses
  System,
  System.Collections.Generic,
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
    const
      LaserPointerCoreRadius: Double = 4.0;
      LaserPointerGlowRadius: Double = 11.0;
      LaserDrawingCoreThickness: Double = 3.5;
      LaserDrawingGlowThickness: Double = 7.0;
      SpotlightRadius: Double = 90.0;
      SpotlightTransparentStop: Double = 0.72;
      SpotlightAnimationDurationSeconds: Double = 0.24;
      LaserDrawingHoldDurationSeconds: Double = 3.0;
      LaserDrawingFadeDurationSeconds: Double = 0.8;
      LaserDrawingMinimumPointDistanceSquared: Double = 0.25;

    var
    fRoot: Grid;
    fImage: System.Windows.Controls.Image;
    fImageTransform: MatrixTransform;
    fSpotlightLayer: System.Windows.Shapes.Rectangle;
    fSpotlightBrush: RadialGradientBrush;
    fLaserDrawingLayer: Canvas;
    fLaserPointerGlow: System.Windows.Shapes.Ellipse;
    fLaserPointerGlowTransform: TranslateTransform;
    fLaserPointer: System.Windows.Shapes.Ellipse;
    fLaserPointerTransform: TranslateTransform;
    fLaserDrawings: List<System.Windows.Shapes.Polyline>;
    fActiveLaserGlow: System.Windows.Shapes.Polyline;
    fActiveLaserDrawing: System.Windows.Shapes.Polyline;
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
    fLaserDrawingMode: Boolean;
    fSpotlightActive: Boolean;
    fSpotlightVisible: Boolean;
    fSpotlightRadius: Double;
    fSpotlightAnimationStartRadius: Double;
    fSpotlightAnimationTargetRadius: Double;
    fSpotlightAnimationStartTime: DateTime;
    fSpotlightAnimationTimer: DispatcherTimer;
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
    method setLaserPointerActive(active: Boolean);
    begin
      if active then begin
        updateLaserPointerCenter(Mouse.GetPosition(fRoot));
        fLaserPointerGlow.Visibility := Visibility.Visible;
        fLaserPointer.Visibility := Visibility.Visible;
      end
      else begin
        fLaserPointerGlow.Visibility := Visibility.Collapsed;
        fLaserPointer.Visibility := Visibility.Collapsed;
      end;
    end;
    method updateLaserPointerCenter(point: Point);
    begin
      fLaserPointerGlowTransform.X := point.X - LaserPointerGlowRadius;
      fLaserPointerGlowTransform.Y := point.Y - LaserPointerGlowRadius;
      fLaserPointerTransform.X := point.X - LaserPointerCoreRadius;
      fLaserPointerTransform.Y := point.Y - LaserPointerCoreRadius;
    end;
    method updateSpotlightCenter(point: Point);
    begin
      if (not assigned(fRoot)) or (not assigned(fSpotlightBrush)) then
        exit;

      fSpotlightBrush.Center := point;
      fSpotlightBrush.GradientOrigin := point;
    end;
    method maximumSpotlightRadius: Double;
    begin
      var width := fRoot.ActualWidth;
      var height := fRoot.ActualHeight;
      result := (Math.Sqrt((width * width) + (height * height)) / SpotlightTransparentStop) + 1.0;
    end;
    method setSpotlightRadius(radius: Double);
    begin
      fSpotlightRadius := Math.Max(0.0, radius);
      fSpotlightBrush.RadiusX := fSpotlightRadius;
      fSpotlightBrush.RadiusY := fSpotlightRadius;
    end;
    method stopSpotlightAnimation;
    begin
      if assigned(fSpotlightAnimationTimer) then
        fSpotlightAnimationTimer.Stop;
    end;
    method animateSpotlight(sender: Object) eventArgs(eventArgs: EventArgs);
    begin
      var elapsed := (DateTime.UtcNow - fSpotlightAnimationStartTime).TotalSeconds;
      var progress := Math.Min(1.0, elapsed / SpotlightAnimationDurationSeconds);
      var easedProgress := progress * progress * (3.0 - (2.0 * progress));
      setSpotlightRadius(fSpotlightAnimationStartRadius +
        ((fSpotlightAnimationTargetRadius - fSpotlightAnimationStartRadius) * easedProgress));
      if progress >= 1.0 then begin
        setSpotlightRadius(fSpotlightAnimationTargetRadius);
        stopSpotlightAnimation;
        if not fSpotlightActive then begin
          fSpotlightVisible := false;
          fSpotlightLayer.Visibility := Visibility.Collapsed;
        end;
      end;
    end;
    method startSpotlightAnimation(targetRadius: Double);
    begin
      fSpotlightVisible := true;
      fSpotlightLayer.Visibility := Visibility.Visible;
      fSpotlightAnimationStartRadius := fSpotlightRadius;
      fSpotlightAnimationTargetRadius := Math.Max(0.0, targetRadius);
      fSpotlightAnimationStartTime := DateTime.UtcNow;
      if Math.Abs(fSpotlightAnimationTargetRadius - fSpotlightAnimationStartRadius) < 0.5 then begin
        setSpotlightRadius(fSpotlightAnimationTargetRadius);
        stopSpotlightAnimation;
        if not fSpotlightActive then begin
          fSpotlightVisible := false;
          fSpotlightLayer.Visibility := Visibility.Collapsed;
        end;
        exit;
      end;
      fSpotlightAnimationTimer.Start;
    end;
    method cancelSpotlight;
    begin
      stopSpotlightAnimation;
      fSpotlightActive := false;
      fSpotlightVisible := false;
      fSpotlightLayer.Visibility := Visibility.Collapsed;
    end;
    method setSpotlightActive(active: Boolean);
    begin
      if active then begin
        if fSpotlightActive then
          exit;
        fSpotlightActive := true;
        updateSpotlightCenter(Mouse.GetPosition(fRoot));
        if not fSpotlightVisible then
          setSpotlightRadius(maximumSpotlightRadius);
        startSpotlightAnimation(SpotlightRadius);
      end
      else begin
        if not fSpotlightActive then
          exit;
        fSpotlightActive := false;
        startSpotlightAnimation(maximumSpotlightRadius);
      end;
    end;
    method beginLaserDrawing(point: Point);
    begin
      var glow := new System.Windows.Shapes.Polyline;
      glow.IsHitTestVisible := false;
      glow.Stroke := new SolidColorBrush(Color.FromArgb(72, 255, 13, 13));
      glow.StrokeEndLineCap := PenLineCap.Round;
      glow.StrokeLineJoin := PenLineJoin.Round;
      glow.StrokeStartLineCap := PenLineCap.Round;
      glow.StrokeThickness := LaserDrawingGlowThickness;
      glow.Points.Add(point);

      var drawing := new System.Windows.Shapes.Polyline;
      drawing.IsHitTestVisible := false;
      drawing.Stroke := new SolidColorBrush(Color.FromArgb(245, 255, 13, 13));
      drawing.StrokeEndLineCap := PenLineCap.Round;
      drawing.StrokeLineJoin := PenLineJoin.Round;
      drawing.StrokeStartLineCap := PenLineCap.Round;
      drawing.StrokeThickness := LaserDrawingCoreThickness;
      drawing.Points.Add(point);

      // Keep the soft stroke below the sharp core, matching the native renderer.
      fLaserDrawingLayer.Children.Add(glow);
      fLaserDrawingLayer.Children.Add(drawing);
      fLaserDrawings.Add(glow);
      fLaserDrawings.Add(drawing);
      fActiveLaserGlow := glow;
      fActiveLaserDrawing := drawing;
    end;
    method appendLaserDrawing(point: Point);
    begin
      if fActiveLaserDrawing = nil then
        exit;

      var previous := fActiveLaserDrawing.Points[fActiveLaserDrawing.Points.Count - 1];
      var deltaX := point.X - previous.X;
      var deltaY := point.Y - previous.Y;
      var minimumDistanceSquared := LaserDrawingMinimumPointDistanceSquared /
        (fTransform.Scale * fTransform.Scale);
      if (deltaX * deltaX) + (deltaY * deltaY) < minimumDistanceSquared then
        exit;

      fActiveLaserGlow.Points.Add(point);
      fActiveLaserDrawing.Points.Add(point);
    end;
    method toCanvasPoint(point: Point): Point;
    begin
      var rootFromCanvas := fImageTransform.Matrix;
      if not rootFromCanvas.HasInverse then
        exit point;

      rootFromCanvas.Invert;
      result := rootFromCanvas.Transform(point);
    end;
    method removeLaserDrawing(drawing: System.Windows.Shapes.Polyline);
    begin
      if not fLaserDrawings.Remove(drawing) then
        exit;

      drawing.BeginAnimation(UIElement.OpacityProperty, nil);
      fLaserDrawingLayer.Children.Remove(drawing);
    end;
    method endActiveLaserDrawing;
    begin
      var drawing := fActiveLaserDrawing;
      var glow := fActiveLaserGlow;
      if (drawing = nil) or (glow = nil) then
        exit;

      fActiveLaserDrawing := nil;
      fActiveLaserGlow := nil;
      var fade := new DoubleAnimation;
      fade.BeginTime := TimeSpan.FromSeconds(LaserDrawingHoldDurationSeconds);
      fade.Duration := new Duration(TimeSpan.FromSeconds(LaserDrawingFadeDurationSeconds));
      fade.FillBehavior := FillBehavior.HoldEnd;
      fade.From := 1.0;
      fade.To := 0.0;
      var glowFade := new DoubleAnimation;
      glowFade.BeginTime := fade.BeginTime;
      glowFade.Duration := fade.Duration;
      glowFade.FillBehavior := fade.FillBehavior;
      glowFade.From := fade.From;
      glowFade.To := fade.To;
      fade.Completed += (sender, eventArgs) -> begin
        removeLaserDrawing(drawing);
        removeLaserDrawing(glow);
      end;
      glow.BeginAnimation(UIElement.OpacityProperty, glowFade);
      drawing.BeginAnimation(UIElement.OpacityProperty, fade);
    end;
    method clearLaserDrawings;
    begin
      fActiveLaserDrawing := nil;
      fActiveLaserGlow := nil;
      if fLaserDrawings <> nil then begin
        for each drawing: System.Windows.Shapes.Polyline in fLaserDrawings do
          drawing.BeginAnimation(UIElement.OpacityProperty, nil);
        fLaserDrawings.Clear;
      end;
      if fLaserDrawingLayer <> nil then
        fLaserDrawingLayer.Children.Clear;
    end;
    method endMouseInteraction;
    begin
      endActiveLaserDrawing;
      fIsDragging := false;
      if IsMouseCaptured then
        Mouse.Capture(nil);
      Cursor := Cursors.None;
    end;
    method abortMouseInteraction;
    begin
      fActiveLaserDrawing := nil;
      fActiveLaserGlow := nil;
      fIsDragging := false;
      if IsMouseCaptured then
        Mouse.Capture(nil);
      Cursor := Cursors.None;
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

      requestCommand(WorkspaceCommand.presetScaleAtAnchor(requestedScale)
        atX(fRoot.ActualWidth / 2.0) atY(fRoot.ActualHeight / 2.0));
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
      if (fActiveLaserDrawing <> nil) or fIsDragging then
        endMouseInteraction;
      var point := eventArgs.GetPosition(fRoot);
      updateLaserPointerCenter(point);
      Mouse.Capture(self);
      if fLaserDrawingMode then
        beginLaserDrawing(toCanvasPoint(point))
      else begin
        fIsDragging := true;
        fPreviousDragPoint := point;
      end;
      eventArgs.Handled := true;
    end;
    method OnMouseMove(eventArgs: MouseEventArgs); override;
    begin
      inherited OnMouseMove(eventArgs);
      var point := eventArgs.GetPosition(fRoot);
      updateLaserPointerCenter(point);
      if fSpotlightActive then
        updateSpotlightCenter(point);
      if fActiveLaserDrawing <> nil then begin
        if eventArgs.LeftButton <> MouseButtonState.Pressed then begin
          endMouseInteraction;
          eventArgs.Handled := true;
          exit;
        end;

        appendLaserDrawing(toCanvasPoint(point));
        eventArgs.Handled := true;
        exit;
      end;
      if not fIsDragging then
        exit;
      if eventArgs.LeftButton <> MouseButtonState.Pressed then begin
        endMouseInteraction;
        exit;
      end;

      requestCommand(WorkspaceCommand.panWithDeltaX(point.X - fPreviousDragPoint.X)
        deltaY(point.Y - fPreviousDragPoint.Y));
      fPreviousDragPoint := point;
      eventArgs.Handled := true;
    end;
    method OnMouseLeftButtonUp(eventArgs: MouseButtonEventArgs); override;
    begin
      inherited OnMouseLeftButtonUp(eventArgs);
      var point := eventArgs.GetPosition(fRoot);
      updateLaserPointerCenter(point);
      if fActiveLaserDrawing <> nil then
        appendLaserDrawing(toCanvasPoint(point));
      endMouseInteraction;
      eventArgs.Handled := true;
    end;
    method OnMouseEnter(eventArgs: MouseEventArgs); override;
    begin
      inherited OnMouseEnter(eventArgs);
      setLaserPointerActive(true);
    end;
    method OnMouseLeave(eventArgs: MouseEventArgs); override;
    begin
      setLaserPointerActive(false);
      inherited OnMouseLeave(eventArgs);
    end;
    method OnLostMouseCapture(eventArgs: MouseEventArgs); override;
    begin
      inherited OnLostMouseCapture(eventArgs);
      if (fActiveLaserDrawing <> nil) or fIsDragging then
        endMouseInteraction;
    end;
    method OnPreviewMouseWheel(eventArgs: MouseWheelEventArgs); override;
    begin
      inherited OnPreviewMouseWheel(eventArgs);
      var point := eventArgs.GetPosition(fRoot);
      if (Keyboard.Modifiers and ModifierKeys.Control) <> ModifierKeys.None then
        requestCommand(WorkspaceCommand.magnifyWithAmount(eventArgs.Delta / 1200.0)
          atX(point.X) atY(point.Y))
      else
        requestCommand(WorkspaceCommand.scrollZoomWithDelta(eventArgs.Delta / 12.0)
          atX(point.X) atY(point.Y));
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

        Key.F:
          begin
            if not eventArgs.IsRepeat then
              setSpotlightActive(true);
            eventArgs.Handled := true;
            exit;
          end;

        Key.D:
          if hasNoShortcutModifiers then begin
            if not eventArgs.IsRepeat then
              fLaserDrawingMode := not fLaserDrawingMode;
            eventArgs.Handled := true;
            exit;
          end;
      end;

      inherited OnPreviewKeyDown(eventArgs);
    end;
    method OnPreviewKeyUp(eventArgs: KeyEventArgs); override;
    begin
      if eventArgs.Key = Key.F then begin
        setSpotlightActive(false);
        eventArgs.Handled := true;
        exit;
      end;

      inherited OnPreviewKeyUp(eventArgs);
    end;
    method OnLostKeyboardFocus(eventArgs: KeyboardFocusChangedEventArgs); override;
    begin
      setSpotlightActive(false);
      inherited OnLostKeyboardFocus(eventArgs);
    end;
    method OnClosing(eventArgs: CancelEventArgs); override;
    begin
      setSpotlightActive(false);
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
    method OnDeactivated(eventArgs: EventArgs); override;
    begin
      setSpotlightActive(false);
      setLaserPointerActive(false);
      endMouseInteraction;
      inherited OnDeactivated(eventArgs);
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
      Cursor := Cursors.None;

      fImageTransform := new MatrixTransform;
      fLaserPointerTransform := new TranslateTransform;
      fLaserDrawings := new List<System.Windows.Shapes.Polyline>;
      fImage := new System.Windows.Controls.Image;
      fImage.RenderTransform := fImageTransform;
      fImage.RenderTransformOrigin := new Point(0.0, 0.0);
      fImage.SnapsToDevicePixels := true;
      fImage.Stretch := Stretch.Fill;
      fImage.SizeChanged += @imageSizeChanged;
      RenderOptions.SetBitmapScalingMode(fImage, BitmapScalingMode.HighQuality);

      fLaserPointerGlowTransform := new TranslateTransform;
      var laserPointerGlowBrush := new RadialGradientBrush;
      laserPointerGlowBrush.Center := new Point(0.5, 0.5);
      laserPointerGlowBrush.GradientOrigin := new Point(0.5, 0.5);
      laserPointerGlowBrush.RadiusX := 0.5;
      laserPointerGlowBrush.RadiusY := 0.5;
      laserPointerGlowBrush.GradientStops.Add(new GradientStop(Color.FromArgb(96, 255, 13, 13), 0.0));
      laserPointerGlowBrush.GradientStops.Add(new GradientStop(Color.FromArgb(72, 255, 13, 13), 0.35));
      laserPointerGlowBrush.GradientStops.Add(new GradientStop(Color.FromArgb(36, 255, 13, 13), 0.65));
      laserPointerGlowBrush.GradientStops.Add(new GradientStop(Color.FromArgb(0, 255, 13, 13), 1.0));

      fLaserPointerGlow := new System.Windows.Shapes.Ellipse;
      fLaserPointerGlow.Fill := laserPointerGlowBrush;
      fLaserPointerGlow.Height := LaserPointerGlowRadius * 2.0;
      fLaserPointerGlow.HorizontalAlignment := HorizontalAlignment.Left;
      fLaserPointerGlow.IsHitTestVisible := false;
      fLaserPointerGlow.RenderTransform := fLaserPointerGlowTransform;
      fLaserPointerGlow.VerticalAlignment := VerticalAlignment.Top;
      fLaserPointerGlow.Visibility := Visibility.Collapsed;
      fLaserPointerGlow.Width := LaserPointerGlowRadius * 2.0;

      fSpotlightBrush := new RadialGradientBrush;
      fSpotlightBrush.Center := new Point(0.0, 0.0);
      fSpotlightBrush.GradientOrigin := new Point(0.0, 0.0);
      fSpotlightBrush.MappingMode := BrushMappingMode.Absolute;
      fSpotlightBrush.RadiusX := SpotlightRadius;
      fSpotlightBrush.RadiusY := SpotlightRadius;
      fSpotlightBrush.SpreadMethod := GradientSpreadMethod.Pad;
      fSpotlightBrush.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), 0.0));
      fSpotlightBrush.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), SpotlightTransparentStop));
      fSpotlightBrush.GradientStops.Add(new GradientStop(Color.FromArgb(184, 0, 0, 0), 1.0));

      fSpotlightLayer := new System.Windows.Shapes.Rectangle;
      fSpotlightLayer.Fill := fSpotlightBrush;
      fSpotlightLayer.HorizontalAlignment := HorizontalAlignment.Stretch;
      fSpotlightLayer.IsHitTestVisible := false;
      fSpotlightLayer.VerticalAlignment := VerticalAlignment.Stretch;
      fSpotlightLayer.Visibility := Visibility.Collapsed;

      fLaserDrawingLayer := new Canvas;
      fLaserDrawingLayer.ClipToBounds := true;
      fLaserDrawingLayer.IsHitTestVisible := false;
      fLaserDrawingLayer.RenderTransform := fImageTransform;
      fLaserDrawingLayer.RenderTransformOrigin := new Point(0.0, 0.0);

      fLaserPointer := new System.Windows.Shapes.Ellipse;
      fLaserPointer.Fill := new SolidColorBrush(Color.FromArgb(245, 255, 13, 13));
      fLaserPointer.Height := LaserPointerCoreRadius * 2.0;
      fLaserPointer.HorizontalAlignment := HorizontalAlignment.Left;
      fLaserPointer.IsHitTestVisible := false;
      fLaserPointer.RenderTransform := fLaserPointerTransform;
      fLaserPointer.Stroke := Brushes.White;
      fLaserPointer.StrokeThickness := 1.0;
      fLaserPointer.VerticalAlignment := VerticalAlignment.Top;
      fLaserPointer.Visibility := Visibility.Collapsed;
      fLaserPointer.Width := LaserPointerCoreRadius * 2.0;

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
      fRoot.Children.Add(fSpotlightLayer);
      fRoot.Children.Add(fLaserDrawingLayer);
      fRoot.Children.Add(fLaserPointerGlow);
      fRoot.Children.Add(fLaserPointer);
      fRoot.Children.Add(fHud);
      Content := fRoot;

      fQualityTimer := new DispatcherTimer(DispatcherPriority.Render);
      fQualityTimer.Interval := TimeSpan.FromMilliseconds(120.0);
      fQualityTimer.Tick += @restoreHighQuality;

      fHudDelayTimer := new DispatcherTimer(DispatcherPriority.Normal);
      fHudDelayTimer.Interval := TimeSpan.FromMilliseconds(800.0);
      fHudDelayTimer.Tick += @fadeHud;

      fSpotlightAnimationTimer := new DispatcherTimer(DispatcherPriority.Render);
      fSpotlightAnimationTimer.Interval := TimeSpan.FromMilliseconds(16.6667);
      fSpotlightAnimationTimer.Tick += @animateSpotlight;
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
      setLaserPointerActive(true);
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
      cancelSpotlight;
      abortMouseInteraction;
      clearLaserDrawings;
      setLaserPointerActive(false);
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
