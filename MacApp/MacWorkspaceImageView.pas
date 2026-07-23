namespace MacApp;

uses
  AppKit,
  CoreGraphics,
  Foundation,
  RemObjects.Elements.RTL,
  Core;

type
  MacLaserStroke = class
  private
    fPoints: NSMutableArray;
    fReleasedAt: Double;
  public
    constructor(startPoint: NSPoint);
    begin
      fPoints := new NSMutableArray;
      fPoints.addObject(NSValue.valueWithPoint(startPoint));
    end;
    property Points: NSMutableArray read fPoints;
    property ReleasedAt: Double read fReleasedAt write fReleasedAt;
  end;

  MacWorkspaceImageView = public class(NSView)
  private
    fCommandRequested: WorkspaceCommandRequested;
    fDismissRequested: WorkspaceSurfaceRequested;
    fPreviousDragPoint: NSPoint;
    fHasPreviousDragPoint: Boolean;
    fImage: NSImage;
    fTransform: WorkspaceTransform := WorkspaceTransform.identityTransform;
    fTrackingArea: NSTrackingArea;
    fLaserPointerVisible: Boolean;
    fLaserPointerCenter: NSPoint;
    fSystemCursorHidden: Boolean;
    fLaserDrawingMode: Boolean;
    fActiveLaserStroke: MacLaserStroke;
    fLaserStrokes: NSMutableArray;
    fLaserTrailTimer: NSTimer;

    method setImage(value: NSImage);
    begin
      fImage := value;
      needsDisplay := true;
    end;
    method pointForEvent(nativeEvent: NSEvent): NSPoint;
    begin
      result := convertPoint(nativeEvent.locationInWindow) fromView(nil);
    end;
    method hideSystemCursor;
    begin
      if fSystemCursorHidden then
        exit;

      NSCursor.hide;
      fSystemCursorHidden := true;
    end;
    method restoreSystemCursor;
    begin
      if not fSystemCursorHidden then
        exit;

      NSCursor.unhide;
      fSystemCursorHidden := false;
    end;
    method beginLaserStrokeAtPoint(point: NSPoint);
    begin
      if fLaserStrokes = nil then
        fLaserStrokes := new NSMutableArray;

      var stroke := new MacLaserStroke(point);
      fLaserStrokes.addObject(stroke);
      fActiveLaserStroke := stroke;
    end;
    method canvasPointForViewPoint(point: NSPoint): NSPoint;
    begin
      var scale := fTransform.Scale;
      if scale <= 0.0 then
        exit point;

      var x := (point.x - fTransform.OffsetX) / scale;
      if fTransform.IsHorizontallyFlipped then
        x := bounds.size.width - x;
      result := NSMakePoint(x, (point.y - fTransform.OffsetY) / scale);
    end;
    method viewPointForCanvasPoint(point: NSPoint): NSPoint;
    begin
      var x := point.x;
      if fTransform.IsHorizontallyFlipped then
        x := bounds.size.width - x;
      result := NSMakePoint(fTransform.OffsetX + (x * fTransform.Scale),
        fTransform.OffsetY + (point.y * fTransform.Scale));
    end;
    method appendLaserStrokePoint(point: NSPoint);
    begin
      if fActiveLaserStroke = nil then
        exit;

      var previous := (fActiveLaserStroke.Points.objectAtIndex(fActiveLaserStroke.Points.count - 1) as NSValue).pointValue;
      var deltaX := point.x - previous.x;
      var deltaY := point.y - previous.y;
      var minimumDistanceSquared := 0.25 / (fTransform.Scale * fTransform.Scale);
      if (deltaX * deltaX) + (deltaY * deltaY) < minimumDistanceSquared then
        exit;

      fActiveLaserStroke.Points.addObject(NSValue.valueWithPoint(point));
    end;
    method startLaserTrailTimer;
    begin
      if fLaserTrailTimer <> nil then
        exit;

      fLaserTrailTimer := NSTimer.scheduledTimerWithTimeInterval(1.0 / 60.0) repeats(true) &block(method(aTimer: NSTimer)
        begin
          updateLaserTrails;
        end);
    end;
    method updateLaserTrails;
    begin
      if fLaserStrokes = nil then begin
        if fLaserTrailTimer <> nil then begin
          fLaserTrailTimer.invalidate;
          fLaserTrailTimer := nil;
        end;
        exit;
      end;

      var now := CACurrentMediaTime;
      var keepTimer := false;
      var needsRedraw := false;
      var index: Int32 := Int32(fLaserStrokes.count) - 1;
      while index >= 0 do begin
        var stroke := fLaserStrokes.objectAtIndex(NSUInteger(index)) as MacLaserStroke;
        if stroke.ReleasedAt > 0.0 then begin
          var elapsed := now - stroke.ReleasedAt;
          if elapsed >= 3.8 then begin
            fLaserStrokes.removeObjectAtIndex(NSUInteger(index));
            needsRedraw := true;
          end
          else begin
            keepTimer := true;
            if elapsed >= 3.0 then
              needsRedraw := true;
          end;
        end;
        index := index - 1;
      end;

      if needsRedraw then
        needsDisplay := true;
      if not keepTimer and (fLaserTrailTimer <> nil) then begin
        fLaserTrailTimer.invalidate;
        fLaserTrailTimer := nil;
      end;
    end;
    method endActiveLaserStroke;
    begin
      if fActiveLaserStroke = nil then
        exit;

      fActiveLaserStroke.ReleasedAt := CACurrentMediaTime;
      fActiveLaserStroke := nil;
      startLaserTrailTimer;
      needsDisplay := true;
    end;
    method clearLaserStrokes;
    begin
      if fLaserTrailTimer <> nil then begin
        fLaserTrailTimer.invalidate;
        fLaserTrailTimer := nil;
      end;
      fActiveLaserStroke := nil;
      if fLaserStrokes <> nil then
        fLaserStrokes.removeAllObjects;
    end;
    method drawLaserStrokesInContext(context: CGContextRef);
    begin
      if (fLaserStrokes = nil) or (fTransform.Scale <= 0.0) then
        exit;

      var now := CACurrentMediaTime;
      var drawingScale := fTransform.Scale;
      var destination := NSMakeRect(fTransform.OffsetX, fTransform.OffsetY,
        bounds.size.width * drawingScale, bounds.size.height * drawingScale);
      CGContextSaveGState(context);
      CGContextClipToRect(context, NSRectToCGRect(destination));
      CGContextSetLineCap(context, CGLineCap.Round);
      CGContextSetLineJoin(context, CGLineJoin.Round);

      for each stroke: MacLaserStroke in fLaserStrokes do begin
        var points := stroke.Points;
        if points.count = 0 then
          continue;

        var opacity := 1.0;
        if stroke.ReleasedAt > 0.0 then begin
          var elapsed := now - stroke.ReleasedAt;
          if elapsed > 3.0 then
            opacity := Math.Max(0.0, 1.0 - ((elapsed - 3.0) / 0.8));
        end;
        if opacity <= 0.0 then
          continue;

        if points.count = 1 then begin
          var point := viewPointForCanvasPoint((points.objectAtIndex(0) as NSValue).pointValue);
          CGContextSetFillColorWithColor(context,
            NSColor.colorWithCalibratedRed(1.0) green(0.08) blue(0.08) alpha(0.28 * opacity).CGColor);
          CGContextFillEllipseInRect(context, NSMakeRect(point.x - (3.5 * drawingScale),
            point.y - (3.5 * drawingScale), 7.0 * drawingScale, 7.0 * drawingScale));
          CGContextSetFillColorWithColor(context,
            NSColor.colorWithCalibratedRed(1.0) green(0.05) blue(0.05) alpha(0.96 * opacity).CGColor);
          CGContextFillEllipseInRect(context, NSMakeRect(point.x - (1.75 * drawingScale),
            point.y - (1.75 * drawingScale), 3.5 * drawingScale, 3.5 * drawingScale));
          continue;
        end;

        CGContextBeginPath(context);
        var firstPoint := viewPointForCanvasPoint((points.objectAtIndex(0) as NSValue).pointValue);
        CGContextMoveToPoint(context, firstPoint.x, firstPoint.y);
        var pointIndex: Int32 := 1;
        while pointIndex < Int32(points.count) do begin
          var point := viewPointForCanvasPoint((points.objectAtIndex(NSUInteger(pointIndex)) as NSValue).pointValue);
          CGContextAddLineToPoint(context, point.x, point.y);
          pointIndex := pointIndex + 1;
        end;
        CGContextSetStrokeColorWithColor(context,
          NSColor.colorWithCalibratedRed(1.0) green(0.08) blue(0.08) alpha(0.28 * opacity).CGColor);
        CGContextSetLineWidth(context, 7.0 * drawingScale);
        CGContextStrokePath(context);

        CGContextBeginPath(context);
        firstPoint := viewPointForCanvasPoint((points.objectAtIndex(0) as NSValue).pointValue);
        CGContextMoveToPoint(context, firstPoint.x, firstPoint.y);
        pointIndex := 1;
        while pointIndex < Int32(points.count) do begin
          var point := viewPointForCanvasPoint((points.objectAtIndex(NSUInteger(pointIndex)) as NSValue).pointValue);
          CGContextAddLineToPoint(context, point.x, point.y);
          pointIndex := pointIndex + 1;
        end;
        CGContextSetStrokeColorWithColor(context,
          NSColor.colorWithCalibratedRed(1.0) green(0.05) blue(0.05) alpha(0.96 * opacity).CGColor);
        CGContextSetLineWidth(context, 3.5 * drawingScale);
        CGContextStrokePath(context);
      end;

      CGContextRestoreGState(context);
    end;
    public
    method updateTrackingAreas; override;
    begin
      inherited updateTrackingAreas;
      if fTrackingArea <> nil then
        removeTrackingArea(fTrackingArea);

      fTrackingArea := new NSTrackingArea withRect(bounds)
        options(NSTrackingAreaOptions.MouseEnteredAndExited or NSTrackingAreaOptions.MouseMoved or
          NSTrackingAreaOptions.ActiveAlways or NSTrackingAreaOptions.InVisibleRect)
        owner(self) userInfo(nil);
      addTrackingArea(fTrackingArea);
    end;
    method mouseEntered(nativeEvent: NSEvent); override;
    begin
      NSCursor.openHandCursor.set;
      hideSystemCursor;
      fLaserPointerVisible := true;
      fLaserPointerCenter := pointForEvent(nativeEvent);
      needsDisplay := true;
    end;
    method mouseExited(nativeEvent: NSEvent); override;
    begin
      restoreSystemCursor;
      fLaserPointerVisible := false;
      needsDisplay := true;
    end;
    method mouseMoved(nativeEvent: NSEvent); override;
    begin
      hideSystemCursor;
      fLaserPointerVisible := true;
      fLaserPointerCenter := pointForEvent(nativeEvent);
      needsDisplay := true;
    end;
    method sendPresetScale(scale: Double);
    begin
      requestCommand(WorkspaceCommand.presetScale(scale) inViewportWidth(bounds.size.width) height(bounds.size.height));
    end;
    method requestCommand(command: WorkspaceCommand);
    begin
      var commandListener := fCommandRequested;
      if assigned(commandListener) then
        commandListener(command);
    end;
    method requestDismissal;
    begin
      var dismissListener := fDismissRequested;
      if assigned(dismissListener) then
        dismissListener();
    end;
  public
    property CommandRequested: WorkspaceCommandRequested read fCommandRequested write fCommandRequested;
    property DismissRequested: WorkspaceSurfaceRequested read fDismissRequested write fDismissRequested;
    property Image: NSImage read fImage write setImage;

    method acceptsFirstResponder: Boolean; override;
    begin
      result := true;
    end;
    method renderTransform(transform: WorkspaceTransform);
    begin
      if transform = nil then
        exit;

      fTransform := transform;
      needsDisplay := true;
    end;
    method activateLaserPointerAtPoint(point: NSPoint);
    begin
      fLaserPointerCenter := point;
      fLaserPointerVisible := NSPointInRect(point, bounds);
      if fLaserPointerVisible then
        hideSystemCursor
      else
        restoreSystemCursor;
      needsDisplay := true;
    end;
    method deactivateLaserPointer;
    begin
      endActiveLaserStroke;
      restoreSystemCursor;
      fLaserPointerVisible := false;
      needsDisplay := true;
    end;
    method cleanupInteraction;
    begin
      fHasPreviousDragPoint := false;
      clearLaserStrokes;
      deactivateLaserPointer;
      NSCursor.arrowCursor.set;
    end;
    method drawRect(dirtyRect: NSRect); override;
    begin
      NSColor.blackColor.setFill;
      NSRectFill(bounds);
      if fImage = nil then
        exit;

      var destination := NSMakeRect(fTransform.OffsetX,
        fTransform.OffsetY,
        bounds.size.width * fTransform.Scale,
        bounds.size.height * fTransform.Scale);
      var graphicsContext := NSGraphicsContext.currentContext;
      if graphicsContext <> nil then
        CGContextSetInterpolationQuality(graphicsContext.CGContext, CGInterpolationQuality.High);

      if fTransform.IsHorizontallyFlipped and (graphicsContext <> nil) then begin
        CGContextSaveGState(graphicsContext.CGContext);
        CGContextTranslateCTM(graphicsContext.CGContext, NSMinX(destination) + NSMaxX(destination), 0.0);
        CGContextScaleCTM(graphicsContext.CGContext, -1.0, 1.0);
      end;

      fImage.drawInRect(destination) fromRect(NSZeroRect) operation(NSCompositingOperation.Copy) fraction(1.0) respectFlipped(false) hints(nil);

      if fTransform.IsHorizontallyFlipped and (graphicsContext <> nil) then
        CGContextRestoreGState(graphicsContext.CGContext);

      if graphicsContext <> nil then begin
        drawLaserStrokesInContext(graphicsContext.CGContext);

        if fLaserPointerVisible then begin
          var context := graphicsContext.CGContext;
          var outerRadius := 11.0;
          var coreRadius := 4.0;
          CGContextSaveGState(context);
          CGContextSetFillColorWithColor(context,
            NSColor.colorWithCalibratedRed(1.0) green(0.08) blue(0.08) alpha(0.28).CGColor);
          CGContextFillEllipseInRect(context, NSMakeRect(fLaserPointerCenter.x - outerRadius,
            fLaserPointerCenter.y - outerRadius, outerRadius * 2.0, outerRadius * 2.0));
          CGContextSetFillColorWithColor(context,
            NSColor.colorWithCalibratedRed(1.0) green(0.05) blue(0.05) alpha(0.96).CGColor);
          CGContextFillEllipseInRect(context, NSMakeRect(fLaserPointerCenter.x - coreRadius,
            fLaserPointerCenter.y - coreRadius, coreRadius * 2.0, coreRadius * 2.0));
          CGContextSetStrokeColorWithColor(context, NSColor.whiteColor.colorWithAlphaComponent(0.9).CGColor);
          CGContextSetLineWidth(context, 1.0);
          CGContextStrokeEllipseInRect(context, NSMakeRect(fLaserPointerCenter.x - coreRadius,
            fLaserPointerCenter.y - coreRadius, coreRadius * 2.0, coreRadius * 2.0));
          CGContextRestoreGState(context);
        end;
      end;
    end;
    method mouseDown(nativeEvent: NSEvent); override;
    begin
      hideSystemCursor;
      endActiveLaserStroke;
      fPreviousDragPoint := pointForEvent(nativeEvent);
      fHasPreviousDragPoint := true;
      fLaserPointerVisible := true;
      fLaserPointerCenter := fPreviousDragPoint;
      needsDisplay := true;
      if fLaserDrawingMode then
        beginLaserStrokeAtPoint(canvasPointForViewPoint(fPreviousDragPoint))
      else
        NSCursor.closedHandCursor.set;
    end;
    method mouseDragged(nativeEvent: NSEvent); override;
    begin
      hideSystemCursor;
      var point := pointForEvent(nativeEvent);
      fLaserPointerVisible := true;
      fLaserPointerCenter := point;
      needsDisplay := true;
      if fActiveLaserStroke <> nil then begin
        appendLaserStrokePoint(canvasPointForViewPoint(point));
        exit;
      end;
      if not fHasPreviousDragPoint then begin
        fPreviousDragPoint := point;
        fHasPreviousDragPoint := true;
        exit;
      end;

      var deltaX: Double := point.x - fPreviousDragPoint.x;
      var deltaY: Double := point.y - fPreviousDragPoint.y;
      fPreviousDragPoint := point;
      if (deltaX <> 0.0) or (deltaY <> 0.0) then
        requestCommand(WorkspaceCommand.panWithDeltaX(deltaX) deltaY(deltaY));
    end;
    method mouseUp(nativeEvent: NSEvent); override;
    begin
      if fActiveLaserStroke <> nil then begin
        var point := pointForEvent(nativeEvent);
        appendLaserStrokePoint(canvasPointForViewPoint(point));
        fLaserPointerCenter := point;
        fLaserPointerVisible := true;
        endActiveLaserStroke;
      end
      else
        NSCursor.openHandCursor.set;
      fHasPreviousDragPoint := false;
    end;
    method resignFirstResponder: Boolean; override;
    begin
      fHasPreviousDragPoint := false;
      deactivateLaserPointer;
      NSCursor.arrowCursor.set;
      result := inherited resignFirstResponder;
    end;
    method scrollWheel(nativeEvent: NSEvent); override;
    begin
      if nativeEvent.hasPreciseScrollingDeltas then begin
        requestCommand(WorkspaceCommand.panWithDeltaX(nativeEvent.scrollingDeltaX) deltaY(-nativeEvent.scrollingDeltaY));
        exit;
      end;

      requestCommand(WorkspaceCommand.scrollZoomWithDelta(nativeEvent.scrollingDeltaY)
        inViewportWidth(bounds.size.width) height(bounds.size.height));
    end;
    method magnifyWithEvent(nativeEvent: NSEvent); override;
    begin
      requestCommand(WorkspaceCommand.magnifyWithAmount(nativeEvent.magnification)
        inViewportWidth(bounds.size.width) height(bounds.size.height));
    end;
    method keyDown(nativeEvent: NSEvent); override;
    begin
      var modifiers: NSEventModifierFlags := nativeEvent.modifierFlags and
        (NSEventModifierFlags.NSCommandKeyMask or NSEventModifierFlags.NSAlternateKeyMask or
        NSEventModifierFlags.NSControlKeyMask or NSEventModifierFlags.NSShiftKeyMask);
      var hasShortcutModifier: Boolean := modifiers <> 0;
      case nativeEvent.keyCode of
        53: begin
          requestDismissal;
          exit;
        end;

        29, 82: begin
          if not nativeEvent.isARepeat and ((modifiers = 0) or (modifiers = NSEventModifierFlags.NSCommandKeyMask)) then begin
            requestCommand(WorkspaceCommand.resetScaleInViewport(bounds.size.width) height(bounds.size.height));
            exit;
          end;
        end;

        15: begin
          if not nativeEvent.isARepeat and not hasShortcutModifier then begin
            requestCommand(WorkspaceCommand.resetWorkspace);
            exit;
          end;
        end;

        8: begin
          if not nativeEvent.isARepeat and not hasShortcutModifier then begin
            requestCommand(WorkspaceCommand.centerInViewport(bounds.size.width) height(bounds.size.height));
            exit;
          end;
        end;

        18, 83: begin
          if not nativeEvent.isARepeat and not hasShortcutModifier then begin
            sendPresetScale(1.5);
            exit;
          end;
        end;

        19, 84: begin
          if not nativeEvent.isARepeat and not hasShortcutModifier then begin
            sendPresetScale(2.0);
            exit;
          end;
        end;

        25, 92: begin
          if not nativeEvent.isARepeat and not hasShortcutModifier then begin
            sendPresetScale(0.7);
            exit;
          end;
        end;

        46: begin
          if not nativeEvent.isARepeat then
            requestCommand(WorkspaceCommand.toggleHorizontalFlip);
          exit;
        end;

        2: begin
          if not nativeEvent.isARepeat and not hasShortcutModifier then begin
            fLaserDrawingMode := not fLaserDrawingMode;
            exit;
          end;
        end;
      end;

      inherited keyDown(nativeEvent);
    end;
  end;

end.
