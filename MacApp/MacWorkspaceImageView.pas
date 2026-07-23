namespace MacApp;

uses
  AppKit,
  CoreGraphics,
  Foundation,
  Core;

type
  MacWorkspaceImageView = public class(NSView)
  private
    fCommandRequested: WorkspaceCommandRequested;
    fDismissRequested: WorkspaceSurfaceRequested;
    fPreviousDragPoint: NSPoint;
    fHasPreviousDragPoint: Boolean;
    fImage: NSImage;
    fTransform: WorkspaceTransform := WorkspaceTransform.identityTransform;

    method setImage(value: NSImage);
    begin
      fImage := value;
      needsDisplay := true;
    end;
    method pointForEvent(nativeEvent: NSEvent): NSPoint;
    begin
      result := convertPoint(nativeEvent.locationInWindow) fromView(nil);
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
    end;
    method mouseDown(nativeEvent: NSEvent); override;
    begin
      fPreviousDragPoint := pointForEvent(nativeEvent);
      fHasPreviousDragPoint := true;
      NSCursor.closedHandCursor.set;
    end;
    method mouseDragged(nativeEvent: NSEvent); override;
    begin
      var point := pointForEvent(nativeEvent);
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
      fHasPreviousDragPoint := false;
      NSCursor.openHandCursor.set;
    end;
    method resignFirstResponder: Boolean; override;
    begin
      fHasPreviousDragPoint := false;
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
      end;

      inherited keyDown(nativeEvent);
    end;
  end;

end.
