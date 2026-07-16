namespace Zoomer.Core;

public sealed class TransformModel
{
    public const double MinimumScale = 0.1;
    public const double MaximumScale = 16.0;

    public TransformState State { get; private set; } = TransformState.Identity;

    public bool ZoomByScrollDelta(double deltaY, double anchorX, double anchorY)
        => ZoomByFactor(Math.Exp(deltaY * 0.025), anchorX, anchorY);

    public bool ZoomByMagnification(double magnification, double anchorX, double anchorY)
    {
        if (!double.IsFinite(magnification))
            return false;

        return ZoomToScale(State.Scale + magnification, anchorX, anchorY);
    }

    public bool ZoomByFactor(double factor, double anchorX, double anchorY)
    {
        if (!double.IsFinite(factor) || factor <= 0)
            return false;

        return ZoomToScale(State.Scale * factor, anchorX, anchorY);
    }

    private bool ZoomToScale(double requestedScale, double anchorX, double anchorY)
    {
        var old = State;
        var nextScale = Math.Clamp(requestedScale, MinimumScale, MaximumScale);
        if (Math.Abs(nextScale - old.Scale) < double.Epsilon)
            return false;

        var ratio = nextScale / old.Scale;
        State = new TransformState(
            nextScale,
            anchorX - ((anchorX - old.OffsetX) * ratio),
            anchorY - ((anchorY - old.OffsetY) * ratio));
        return true;
    }

    public void Translate(double deltaX, double deltaY)
    {
        var current = State;
        State = current with
        {
            OffsetX = current.OffsetX + deltaX,
            OffsetY = current.OffsetY + deltaY,
        };
    }

    public void ToggleHorizontalFlip()
        => State = State with { IsHorizontallyFlipped = !State.IsHorizontallyFlipped };

    public void Reset() => State = TransformState.Identity;
}
