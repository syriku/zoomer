namespace Core;

interface

uses
  RemObjects.Elements.RTL;

type
  WorkspaceTransformModel = public class
  private
    fTransform: WorkspaceTransform := WorkspaceTransform.identityTransform();

    method zoomToScale(requestedScale: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
    method clampScale(value: Double): Double;
    method isFinite(value: Double): Boolean;
  public
    const MinimumScale: Double = 0.1;
    const MaximumScale: Double = 16.0;

    property Transform: WorkspaceTransform read fTransform;

    method zoomByScrollDelta(delta: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
    method zoomByMagnification(magnification: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
    method zoomByFactor(factor: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
    method setPresetScale(scale: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
    method translateBy(deltaX: Double) deltaY(y: Double): Boolean;
    method resetScale: Boolean;
    method resetTransform: Boolean;
    method centerInViewport(width: Double) height(viewportHeight: Double): Boolean;
    method toggleHorizontalFlip;
  end;

implementation

method WorkspaceTransformModel.zoomByScrollDelta(delta: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
begin
  if not isFinite(delta) then
    exit false;

  result := zoomByFactor(Math.Exp(delta * 0.025)) atX(anchorX) atY(anchorY);
end;

method WorkspaceTransformModel.zoomByMagnification(magnification: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
begin
  if not isFinite(magnification) then
    exit false;

  result := zoomToScale(fTransform.Scale + magnification) atX(anchorX) atY(anchorY);
end;

method WorkspaceTransformModel.zoomByFactor(factor: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
begin
  if (not isFinite(factor)) or (factor <= 0.0) then
    exit false;

  result := zoomToScale(fTransform.Scale * factor) atX(anchorX) atY(anchorY);
end;

method WorkspaceTransformModel.setPresetScale(scale: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
begin
  result := zoomToScale(scale) atX(anchorX) atY(anchorY);
end;

method WorkspaceTransformModel.translateBy(deltaX: Double) deltaY(y: Double): Boolean;
var
  current: WorkspaceTransform;
begin
  if (not isFinite(deltaX)) or (not isFinite(y)) or ((deltaX = 0.0) and (y = 0.0)) then
    exit false;

  current := fTransform;
  fTransform := new WorkspaceTransform(current.Scale) offsetX(current.OffsetX + deltaX) offsetY(current.OffsetY + y) horizontallyFlipped(current.IsHorizontallyFlipped);
  result := true;
end;

method WorkspaceTransformModel.resetScale: Boolean;
var
  current: WorkspaceTransform;
begin
  current := fTransform;
  if current.Scale = 1.0 then
    exit false;

  fTransform := new WorkspaceTransform(1.0) offsetX(current.OffsetX) offsetY(current.OffsetY) horizontallyFlipped(current.IsHorizontallyFlipped);
  result := true;
end;

method WorkspaceTransformModel.resetTransform: Boolean;
var
  current: WorkspaceTransform;
begin
  current := fTransform;
  if (current.Scale = 1.0) and (current.OffsetX = 0.0) and (current.OffsetY = 0.0) and (not current.IsHorizontallyFlipped) then
    exit false;

  fTransform := WorkspaceTransform.identityTransform();
  result := true;
end;

method WorkspaceTransformModel.centerInViewport(width: Double) height(viewportHeight: Double): Boolean;
var
  current: WorkspaceTransform;
  offsetX: Double;
  offsetY: Double;
begin
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

method WorkspaceTransformModel.toggleHorizontalFlip;
var
  current: WorkspaceTransform;
begin
  current := fTransform;
  fTransform := new WorkspaceTransform(current.Scale) offsetX(current.OffsetX) offsetY(current.OffsetY) horizontallyFlipped(not current.IsHorizontallyFlipped);
end;

method WorkspaceTransformModel.zoomToScale(requestedScale: Double) atX(anchorX: Double) atY(anchorY: Double): Boolean;
var
  current: WorkspaceTransform;
  nextScale: Double;
  ratio: Double;
begin
  if (not isFinite(requestedScale)) or (not isFinite(anchorX)) or (not isFinite(anchorY)) then
    exit false;

  current := fTransform;
  nextScale := clampScale(requestedScale);
  if nextScale = current.Scale then
    exit false;

  ratio := nextScale / current.Scale;
  fTransform := new WorkspaceTransform(nextScale) offsetX(anchorX - ((anchorX - current.OffsetX) * ratio)) offsetY(anchorY - ((anchorY - current.OffsetY) * ratio)) horizontallyFlipped(current.IsHorizontallyFlipped);
  result := true;
end;

method WorkspaceTransformModel.clampScale(value: Double): Double;
begin
  if value < MinimumScale then
    exit MinimumScale;

  if value > MaximumScale then
    exit MaximumScale;

  result := value;
end;

method WorkspaceTransformModel.isFinite(value: Double): Boolean;
begin
  result := (value = value) and (value > -1.7976931348623157E+308) and (value < 1.7976931348623157E+308);
end;

end.
