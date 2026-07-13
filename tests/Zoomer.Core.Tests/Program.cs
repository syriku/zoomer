using Zoomer.Core;

var tests = new (string Name, Action Run)[]
{
    ("Transform starts at identity", () => Equal(TransformState.Identity, new TransformModel().State)),
    ("Transform preserves anchor", TestAnchor),
    ("Transform clamps minimum", TestMinimum),
    ("Transform clamps maximum", TestMaximum),
    ("Transform applies magnification", TestMagnification),
    ("Transform rejects invalid magnification", TestInvalidMagnification),
    ("Transform translates and resets", TestTranslateReset),
    ("Workspace rejects duplicate capture", TestDuplicateCapture),
    ("Workspace presents and dismisses", TestPresentDismiss),
    ("Workspace discards stale image", TestStaleImage),
    ("Workspace releases frame when presentation fails", TestPresentationFailure),
    ("Workspace releases frame after disposal", TestDisposedCapture),
    ("Workspace maps capture failure", TestCaptureFailure),
    ("Workspace requests permission", TestPermission),
    ("Workspace routes magnify and pan", TestMagnifyPan),
};

var failed = 0;
foreach (var test in tests)
{
    try { test.Run(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception error) { failed++; Console.Error.WriteLine($"FAIL {test.Name}: {error.Message}"); }
}
return failed == 0 ? 0 : 1;

static void TestAnchor()
{
    var model = new TransformModel();
    model.ZoomByFactor(2, 100, 50);
    Equal(2.0, model.State.Scale);
    Equal(-100.0, model.State.OffsetX);
    Equal(-50.0, model.State.OffsetY);
    Equal(100.0, model.State.OffsetX + (100 * model.State.Scale));
}

static void TestMinimum()
{
    var model = new TransformModel();
    model.ZoomByFactor(0.0001, 0, 0);
    Equal(0.1, model.State.Scale);
}

static void TestMaximum()
{
    var model = new TransformModel();
    model.ZoomByFactor(100, 0, 0);
    Equal(16.0, model.State.Scale);
}

static void TestMagnification()
{
    var model = new TransformModel();
    True(model.ZoomByMagnification(0.5, 100, 50));
    Equal(new TransformState(1.5, -50, -25), model.State);
    True(model.ZoomByMagnification(-0.25, 100, 50));
    Equal(new TransformState(1.25, -25, -12.5), model.State);

    model.ZoomByMagnification(100, 0, 0);
    Equal(TransformModel.MaximumScale, model.State.Scale);
    model.ZoomByMagnification(-100, 0, 0);
    Equal(TransformModel.MinimumScale, model.State.Scale);
}

static void TestInvalidMagnification()
{
    var model = new TransformModel();
    True(!model.ZoomByMagnification(double.NaN, 0, 0));
    True(!model.ZoomByMagnification(double.PositiveInfinity, 0, 0));
    Equal(TransformState.Identity, model.State);
}

static void TestTranslateReset()
{
    var model = new TransformModel();
    model.Translate(12, -8);
    Equal(new TransformState(1, 12, -8), model.State);
    model.Reset();
    Equal(TransformState.Identity, model.State);
}

static void TestDuplicateCapture()
{
    var f = new Fixture();
    f.Controller.RequestPresentation();
    f.Controller.RequestPresentation();
    Equal(1, f.Capture.Calls);
    Equal(WorkspaceState.Capturing, f.Controller.State);
}

static void TestPresentDismiss()
{
    var f = new Fixture();
    f.Controller.RequestPresentation();
    f.Capture.CompleteSuccess();
    Equal(WorkspaceState.Presenting, f.Controller.State);
    True(f.Window.Shown);
    f.Window.RaiseDismiss();
    Equal(WorkspaceState.Idle, f.Controller.State);
    True(f.Window.Disposed);
    True(f.Capture.LastFrame!.Disposed);
}

static void TestStaleImage()
{
    var f = new Fixture();
    f.Controller.RequestPresentation();
    f.Controller.DismissWorkspace();
    f.Capture.CompleteSuccess();
    True(f.Capture.LastFrame!.Disposed);
    Equal(WorkspaceState.Idle, f.Controller.State);
}

static void TestPresentationFailure()
{
    var f = new Fixture();
    f.Window.ShowSucceeds = false;
    f.Controller.RequestPresentation();
    f.Capture.CompleteSuccess();
    Equal(WorkspaceState.Idle, f.Controller.State);
    True(f.Capture.LastFrame!.Disposed);
    Equal("测试显示失败", f.Controller.StatusText);
}

static void TestDisposedCapture()
{
    var f = new Fixture();
    f.Controller.RequestPresentation();
    f.Controller.Dispose();
    f.Capture.CompleteSuccess();
    True(f.Capture.LastFrame!.Disposed);
}

static void TestCaptureFailure()
{
    var f = new Fixture();
    f.Controller.RequestPresentation();
    f.Capture.CompleteFailure("坏掉了");
    Equal(WorkspaceState.Idle, f.Controller.State);
    Equal("坏掉了", f.Controller.StatusText);
}

static void TestPermission()
{
    var f = new Fixture { Permission = { IsAuthorized = false } };
    f.Controller.RequestPresentation();
    Equal(1, f.Permission.Requests);
    Equal(0, f.Capture.Calls);
}

static void TestMagnifyPan()
{
    var f = new Fixture();
    f.Controller.RequestPresentation();
    f.Capture.CompleteSuccess();

    f.Window.RaiseMagnify(0.25, 50, 50);
    Equal((new TransformState(1.25, -12.5, -12.5), true), f.Window.Updates[^1]);

    f.Window.RaisePan(10, -4);
    Equal((new TransformState(1.25, -2.5, -16.5), false), f.Window.Updates[^1]);
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
        throw new InvalidOperationException($"expected {expected}, got {actual}");
}
static void True(bool value) { if (!value) throw new InvalidOperationException("expected true"); }

sealed class Fixture
{
    public FakePermission Permission { get; } = new();
    public FakeCapture Capture { get; } = new();
    public FakeWindow Window { get; } = new();
    public WorkspaceController Controller { get; }
    public Fixture() => Controller = new WorkspaceController(Permission, Capture, new FakeWindowFactory(Window));
}

sealed class FakePermission : IPermissionService
{
    public bool IsAuthorized { get; set; } = true;
    public int Requests { get; private set; }
    public bool RequestAuthorization() { Requests++; return IsAuthorized; }
    public void OpenSystemSettings() { }
}

sealed class FakeCapture : IScreenCaptureService
{
    private long _request;
    private Action<CaptureResult>? _completion;
    public int Calls { get; private set; }
    public FakeFrame? LastFrame { get; private set; }
    public void Capture(long requestId, Action<CaptureResult> completion)
    { Calls++; _request = requestId; _completion = completion; }
    public void CompleteSuccess()
    {
        LastFrame = new FakeFrame();
        _completion!(new CaptureResult(_request, LastFrame, new DisplayDescriptor("1", 0, 0, 100, 100, 2)));
    }
    public void CompleteFailure(string message) => _completion!(new CaptureResult(_request, null, default, WorkspaceErrorCode.CaptureFailed, message));
}

sealed class FakeFrame : ICaptureFrame
{
    public bool Disposed { get; private set; }
    public void Dispose() => Disposed = true;
}

sealed class FakeWindowFactory(FakeWindow window) : INativeWorkspaceWindowFactory
{ public INativeWorkspaceWindow Create() => window; }

sealed class FakeWindow : INativeWorkspaceWindow
{
    public event Action? DismissRequested;
    public event Action<double, double, double>? ZoomRequested;
    public event Action<double, double, double>? MagnifyRequested;
    public event Action<double, double>? PanRequested;
    public event Action? ResetRequested;
    public event Action? TargetDisplayDisconnected;
    public bool Shown { get; private set; }
    public bool Disposed { get; private set; }
    public bool ShowSucceeds { get; set; } = true;
    private ICaptureFrame? Frame { get; set; }
    public List<(TransformState Transform, bool ShowHud)> Updates { get; } = [];
    public WindowShowResult Show(ICaptureFrame frame, DisplayDescriptor display)
    {
        Shown = ShowSucceeds;
        if (ShowSucceeds) Frame = frame;
        return ShowSucceeds ? WindowShowResult.Success : WindowShowResult.Failure("测试显示失败");
    }
    public void UpdateTransform(TransformState transform, bool showHud) => Updates.Add((transform, showHud));
    public void RaiseDismiss() => DismissRequested?.Invoke();
    public void RaiseMagnify(double magnification, double x, double y)
        => MagnifyRequested?.Invoke(magnification, x, y);
    public void RaisePan(double dx, double dy) => PanRequested?.Invoke(dx, dy);
    public void Dispose()
    {
        Disposed = true;
        Frame?.Dispose();
        Frame = null;
    }
}
