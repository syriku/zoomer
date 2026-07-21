namespace MacApp;

interface

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
    method pointForEvent(nativeEvent: NSEvent): NSPoint;
    method sendPresetScale(scale: Double) atPoint(anchor: NSPoint);
    method requestCommand(command: WorkspaceCommand);
    method requestDismissal;
  public
    property CommandRequested: WorkspaceCommandRequested read fCommandRequested write fCommandRequested;
    property DismissRequested: WorkspaceSurfaceRequested read fDismissRequested write fDismissRequested;
    property Image: NSImage read fImage write setImage;

    method acceptsFirstResponder: Boolean; override;
    method renderTransform(transform: WorkspaceTransform);
    method drawRect(dirtyRect: NSRect); override;
    method mouseDown(nativeEvent: NSEvent); override;
    method mouseDragged(nativeEvent: NSEvent); override;
    method mouseUp(nativeEvent: NSEvent); override;
    method resignFirstResponder: Boolean; override;
    method scrollWheel(nativeEvent: NSEvent); override;
    method magnifyWithEvent(nativeEvent: NSEvent); override;
    method keyDown(nativeEvent: NSEvent); override;
  end;

implementation

method MacWorkspaceImageView.acceptsFirstResponder: Boolean;
begin
  result := true;
end;

method MacWorkspaceImageView.setImage(value: NSImage);
begin
  fImage := value;
  needsDisplay := true;
end;

method MacWorkspaceImageView.renderTransform(transform: WorkspaceTransform);
begin
  if transform = nil then
    exit;

  fTransform := transform;
  needsDisplay := true;
end;

method MacWorkspaceImageView.drawRect(dirtyRect: NSRect);
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

method MacWorkspaceImageView.mouseDown(nativeEvent: NSEvent);
begin
  fPreviousDragPoint := pointForEvent(nativeEvent);
  fHasPreviousDragPoint := true;
  NSCursor.closedHandCursor.set;
end;

method MacWorkspaceImageView.mouseDragged(nativeEvent: NSEvent);
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

method MacWorkspaceImageView.mouseUp(nativeEvent: NSEvent);
begin
  fHasPreviousDragPoint := false;
  NSCursor.openHandCursor.set;
end;

method MacWorkspaceImageView.resignFirstResponder: Boolean;
begin
  fHasPreviousDragPoint := false;
  NSCursor.arrowCursor.set;
  result := inherited resignFirstResponder;
end;

method MacWorkspaceImageView.scrollWheel(nativeEvent: NSEvent);
begin
  if nativeEvent.hasPreciseScrollingDeltas then begin
    requestCommand(WorkspaceCommand.panWithDeltaX(nativeEvent.scrollingDeltaX) deltaY(-nativeEvent.scrollingDeltaY));
    exit;
  end;

  var anchor := pointForEvent(nativeEvent);
  requestCommand(WorkspaceCommand.scrollZoomWithDelta(nativeEvent.scrollingDeltaY) atX(anchor.x) atY(anchor.y));
end;

method MacWorkspaceImageView.magnifyWithEvent(nativeEvent: NSEvent);
begin
  var anchor := pointForEvent(nativeEvent);
  requestCommand(WorkspaceCommand.magnifyWithAmount(nativeEvent.magnification) atX(anchor.x) atY(anchor.y));
end;

method MacWorkspaceImageView.keyDown(nativeEvent: NSEvent);
begin
  var modifiers: NSEventModifierFlags := nativeEvent.modifierFlags and
    (NSEventModifierFlags.NSCommandKeyMask or NSEventModifierFlags.NSAlternateKeyMask or
    NSEventModifierFlags.NSControlKeyMask or NSEventModifierFlags.NSShiftKeyMask);
  var hasShortcutModifier: Boolean := modifiers <> 0;
  var anchor := pointForEvent(nativeEvent);
  case nativeEvent.keyCode of
    53: begin
      requestDismissal;
      exit;
    end;

    29, 82: begin
      if not nativeEvent.isARepeat and ((modifiers = 0) or (modifiers = NSEventModifierFlags.NSCommandKeyMask)) then begin
        requestCommand(WorkspaceCommand.resetScale);
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
        sendPresetScale(1.5) atPoint(anchor);
        exit;
      end;
    end;

    19, 84: begin
      if not nativeEvent.isARepeat and not hasShortcutModifier then begin
        sendPresetScale(2.0) atPoint(anchor);
        exit;
      end;
    end;

    25, 92: begin
      if not nativeEvent.isARepeat and not hasShortcutModifier then begin
        sendPresetScale(0.7) atPoint(anchor);
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

method MacWorkspaceImageView.pointForEvent(nativeEvent: NSEvent): NSPoint;
begin
  result := convertPoint(nativeEvent.locationInWindow) fromView(nil);
end;

method MacWorkspaceImageView.sendPresetScale(scale: Double) atPoint(anchor: NSPoint);
begin
  requestCommand(WorkspaceCommand.presetScaleAtAnchor(scale) atX(anchor.x) atY(anchor.y));
end;

method MacWorkspaceImageView.requestCommand(command: WorkspaceCommand);
begin
  var commandListener := fCommandRequested;
  if assigned(commandListener) then
    commandListener(command);
end;

method MacWorkspaceImageView.requestDismissal;
begin
  var dismissListener := fDismissRequested;
  if assigned(dismissListener) then
    dismissListener();
end;

end.
