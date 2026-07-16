namespace Zoomer.Core;

public enum WorkspaceState
{
    Idle,
    Capturing,
    Presenting,
    Dismissing,
}

public enum WorkspaceErrorCode
{
    PermissionDenied = 1,
    TargetDisplayUnavailable,
    CaptureFailed,
    CaptureCancelled,
    PresentationFailed,
    NativeBridgeFailed,
}

public readonly record struct DisplayDescriptor(
    string DisplayId,
    double X,
    double Y,
    double Width,
    double Height,
    double BackingScale);

public readonly record struct TransformState(
    double Scale,
    double OffsetX,
    double OffsetY,
    bool IsHorizontallyFlipped = false)
{
    public static TransformState Identity => new(1, 0, 0);
}

public readonly record struct CaptureResult(
    long RequestId,
    ICaptureFrame? Frame,
    DisplayDescriptor Display,
    WorkspaceErrorCode? ErrorCode = null,
    string? ErrorMessage = null)
{
    public bool IsSuccess => Frame is not null && ErrorCode is null;
}

public readonly record struct WindowShowResult(bool IsSuccess, string? ErrorMessage = null)
{
    public static WindowShowResult Success => new(true);
    public static WindowShowResult Failure(string? errorMessage) => new(false, errorMessage);
}
