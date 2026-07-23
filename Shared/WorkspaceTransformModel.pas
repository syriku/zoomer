namespace Core;

uses
  RemObjects.Elements.RTL;

type
  WorkspaceTransformModel = public class
  private
    fTransform: WorkspaceTransform := WorkspaceTransform.identityTransform();

    method zoomToScale(requestedScale: Double) inViewportWidth(viewportWidth: Double) height(viewportHeight: Double): Boolean;
    begin
      var current: WorkspaceTransform;
      var nextScale: Double;
      var imageCenterX: Double;
      var imageCenterY: Double;
      if (not isFinite(requestedScale)) or (not isFinite(viewportWidth)) or (not isFinite(viewportHeight)) or
        (viewportWidth < 0.0) or (viewportHeight < 0.0) then
        exit false;

      current := fTransform;
      nextScale := clampScale(requestedScale);
      if nextScale = current.Scale then
        exit false;

      // Keep the point at the center of the already transformed image fixed.
      // The image is rendered at the viewport size before this transform, so
      // its current center is offset + (viewportSize * currentScale / 2).
      imageCenterX := current.OffsetX + (viewportWidth * current.Scale / 2.0);
      imageCenterY := current.OffsetY + (viewportHeight * current.Scale / 2.0);
      fTransform := new WorkspaceTransform(nextScale)
        offsetX(imageCenterX - (viewportWidth * nextScale / 2.0))
        offsetY(imageCenterY - (viewportHeight * nextScale / 2.0))
        horizontallyFlipped(current.IsHorizontallyFlipped);
      result := true;
    end;
    method clampScale(value: Double): Double;
    begin
      if value < MinimumScale then
        exit MinimumScale;

      if value > MaximumScale then
        exit MaximumScale;

      result := value;
    end;
    method isFinite(value: Double): Boolean;
    begin
      result := (value = value) and (value > -1.7976931348623157E+308) and (value < 1.7976931348623157E+308);
    end;
  public
    const MinimumScale: Double = 0.1;
    const MaximumScale: Double = 16.0;

    property Transform: WorkspaceTransform read fTransform;

    method zoomByScrollDelta(delta: Double) inViewportWidth(viewportWidth: Double) height(viewportHeight: Double): Boolean;
    begin
      if not isFinite(delta) then
        exit false;

      result := zoomByFactor(Math.Exp(delta * 0.025)) inViewportWidth(viewportWidth) height(viewportHeight);
    end;
    method zoomByMagnification(magnification: Double) inViewportWidth(viewportWidth: Double) height(viewportHeight: Double): Boolean;
    begin
      if not isFinite(magnification) then
        exit false;

      result := zoomToScale(fTransform.Scale + magnification) inViewportWidth(viewportWidth) height(viewportHeight);
    end;
    method zoomByFactor(factor: Double) inViewportWidth(viewportWidth: Double) height(viewportHeight: Double): Boolean;
    begin
      if (not isFinite(factor)) or (factor <= 0.0) then
        exit false;

      result := zoomToScale(fTransform.Scale * factor) inViewportWidth(viewportWidth) height(viewportHeight);
    end;
    method setPresetScale(scale: Double) inViewportWidth(viewportWidth: Double) height(viewportHeight: Double): Boolean;
    begin
      result := zoomToScale(scale) inViewportWidth(viewportWidth) height(viewportHeight);
    end;
    method translateBy(deltaX: Double) deltaY(y: Double): Boolean;
    begin
      var current: WorkspaceTransform;
      if (not isFinite(deltaX)) or (not isFinite(y)) or ((deltaX = 0.0) and (y = 0.0)) then
        exit false;

      current := fTransform;
      fTransform := new WorkspaceTransform(current.Scale) offsetX(current.OffsetX + deltaX) offsetY(current.OffsetY + y) horizontallyFlipped(current.IsHorizontallyFlipped);
      result := true;
    end;
    method resetScaleInViewport(viewportWidth: Double) height(viewportHeight: Double): Boolean;
    begin
      result := zoomToScale(1.0) inViewportWidth(viewportWidth) height(viewportHeight);
    end;
    method resetTransform: Boolean;
    begin
      var current: WorkspaceTransform;
      current := fTransform;
      if (current.Scale = 1.0) and (current.OffsetX = 0.0) and (current.OffsetY = 0.0) and (not current.IsHorizontallyFlipped) then
        exit false;

      fTransform := WorkspaceTransform.identityTransform();
      result := true;
    end;
    method centerInViewport(width: Double) height(viewportHeight: Double): Boolean;
    begin
      var current: WorkspaceTransform;
      var offsetX: Double;
      var offsetY: Double;
      if (not isFinite(width)) or (not isFinite(viewportHeight)) or (width < 0.0) or (viewportHeight < 0.0) then
        exit false;

      current := fTransform;
      offsetX := (width - (width * current.Scale)) / 2.0;
      offsetY := (viewportHeight - (viewportHeight * current.Scale)) / 2.0;
      if (offsetX = current.OffsetX) and (offsetY = current.OffsetY) then
        exit false;

      fTransform := new WorkspaceTransform(current.Scale) offsetX(offsetX) offsetY(offsetY) horizontallyFlipped(current.IsHorizontallyFlipped);
      result := true;
    end;
    method toggleHorizontalFlip;
    begin
      var current: WorkspaceTransform;
      current := fTransform;
      fTransform := new WorkspaceTransform(current.Scale) offsetX(current.OffsetX) offsetY(current.OffsetY) horizontallyFlipped(not current.IsHorizontallyFlipped);
    end;
  end;

end.
