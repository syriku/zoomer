namespace Zoomer.Core;

public interface ICaptureFrame : IDisposable;

public interface IPermissionService
{
    bool IsAuthorized { get; }
    bool RequestAuthorization();
    void OpenSystemSettings();
}

public interface IScreenCaptureService
{
    void Capture(long requestId, Action<CaptureResult> completion);
}

public interface IHotKeyService
{
    bool Register(Action triggered);
    void Unregister();
}

public interface INativeWorkspaceWindow : IDisposable
{
    event Action? DismissRequested;
    event Action<double, double, double>? ZoomRequested;
    event Action<double, double, double>? MagnifyRequested;
    event Action<double, double>? PanRequested;
    event Action? ResetRequested;
    event Action? TargetDisplayDisconnected;

    // The window takes ownership of frame only when the result is successful.
    WindowShowResult Show(ICaptureFrame frame, DisplayDescriptor display);
    void UpdateTransform(TransformState transform, bool showHud);
}

public interface INativeWorkspaceWindowFactory
{
    INativeWorkspaceWindow Create();
}
