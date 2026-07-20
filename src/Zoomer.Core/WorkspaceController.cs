namespace Zoomer.Core;

public sealed class WorkspaceController : IDisposable
{
    private readonly IPermissionService _permission;
    private readonly IScreenCaptureService _capture;
    private readonly INativeWorkspaceWindowFactory _windows;
    private readonly TransformModel _transform = new();
    private INativeWorkspaceWindow? _window;
    private long _requestId;
    private bool _disposed;

    public WorkspaceController(
        IPermissionService permission,
        IScreenCaptureService capture,
        INativeWorkspaceWindowFactory windows)
    {
        _permission = permission;
        _capture = capture;
        _windows = windows;
    }

    public WorkspaceState State { get; private set; } = WorkspaceState.Idle;
    public string StatusText { get; private set; } = "空闲";
    public event Action<WorkspaceController>? StateChanged;

    public void RequestPresentation()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (State != WorkspaceState.Idle)
            return;

        if (!_permission.IsAuthorized)
        {
            _permission.RequestAuthorization();
            SetStatus("需要屏幕录制权限", WorkspaceState.Idle);
            return;
        }

        var requestId = ++_requestId;
        SetStatus("正在截屏", WorkspaceState.Capturing);
        _capture.Capture(requestId, OnCaptureCompleted);
    }

    public void DismissWorkspace()
    {
        if (State is WorkspaceState.Idle or WorkspaceState.Dismissing)
            return;

        ++_requestId;
        SetStatus("正在关闭", WorkspaceState.Dismissing);
        DestroyWindow();
        _transform.Reset();
        SetStatus("空闲", WorkspaceState.Idle);
    }

    private void OnCaptureCompleted(CaptureResult result)
    {
        if (State != WorkspaceState.Capturing || result.RequestId != _requestId)
        {
            result.Frame?.Dispose();
            return;
        }

        if (!result.IsSuccess)
        {
            result.Frame?.Dispose();
            SetStatus(result.ErrorMessage ?? "无法截取当前显示器", WorkspaceState.Idle);
            return;
        }

        INativeWorkspaceWindow? window = null;
        WindowShowResult showResult;
        try
        {
            window = _windows.Create();
            WireWindow(window);
            showResult = window.Show(result.Frame!, result.Display);
        }
        catch (Exception error)
        {
            window?.Dispose();
            result.Frame!.Dispose();
            SetStatus($"无法创建工作窗口：{DescribeException(error)}",
                WorkspaceState.Idle);
            return;
        }

        if (!showResult.IsSuccess)
        {
            window.Dispose();
            result.Frame!.Dispose();
            SetStatus(showResult.ErrorMessage ?? "无法显示工作窗口", WorkspaceState.Idle);
            return;
        }

        _window = window;
        _transform.Reset();
        window.UpdateTransform(_transform.State, showHud: true);
        SetStatus("工作模式", WorkspaceState.Presenting);
    }

    private void WireWindow(INativeWorkspaceWindow window)
    {
        window.DismissRequested += DismissWorkspace;
        window.TargetDisplayDisconnected += DismissWorkspace;
        window.ResetRequested += () =>
        {
            if (State != WorkspaceState.Presenting) return;
            _transform.ResetScale();
            window.UpdateTransform(_transform.State, showHud: true);
        };
        window.FullResetRequested += () =>
        {
            if (State != WorkspaceState.Presenting) return;
            _transform.Reset();
            window.UpdateTransform(_transform.State, showHud: true);
        };
        window.CenterRequested += (width, height) =>
        {
            if (State != WorkspaceState.Presenting) return;
            _transform.Center(width, height);
            window.UpdateTransform(_transform.State, showHud: false);
        };
        window.ToggleHorizontalFlipRequested += () =>
        {
            if (State != WorkspaceState.Presenting) return;
            _transform.ToggleHorizontalFlip();
            window.UpdateTransform(_transform.State, showHud: false);
        };
        window.ZoomRequested += (delta, x, y) =>
        {
            if (State != WorkspaceState.Presenting) return;
            if (_transform.ZoomByScrollDelta(delta, x, y))
                window.UpdateTransform(_transform.State, showHud: true);
        };
        window.MagnifyRequested += (magnification, x, y) =>
        {
            if (State != WorkspaceState.Presenting) return;
            if (_transform.ZoomByMagnification(magnification, x, y))
                window.UpdateTransform(_transform.State, showHud: true);
        };
        window.PanRequested += (dx, dy) =>
        {
            if (State != WorkspaceState.Presenting) return;
            _transform.Translate(dx, dy);
            window.UpdateTransform(_transform.State, showHud: false);
        };
    }

    private void DestroyWindow()
    {
        _window?.Dispose();
        _window = null;
    }

    private void SetStatus(string text, WorkspaceState state)
    {
        StatusText = text;
        State = state;
        StateChanged?.Invoke(this);
    }

    private static string DescribeException(Exception error)
    {
        var root = error.GetBaseException();
        return ReferenceEquals(root, error)
            ? $"{error.GetType().Name}: {error.Message}"
            : $"{error.GetType().Name}: {error.Message} -> {root.GetType().Name}: {root.Message}";
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        ++_requestId;
        DestroyWindow();
    }
}
