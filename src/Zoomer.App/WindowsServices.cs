#if WINDOWS
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using Zoomer.Core;
using Drawing = System.Drawing;
using DrawingImaging = System.Drawing.Imaging;
using Forms = System.Windows.Forms;

namespace Zoomer.App;

internal sealed class WindowsPermissionService : IPermissionService
{
    public bool IsAuthorized => true;
    public bool RequestAuthorization() => true;
    public void OpenSystemSettings() { }
}

internal sealed class WindowsCaptureFrame(BitmapSource source) : ICaptureFrame
{
    private BitmapSource? _source = source;

    internal BitmapSource Source => _source ??
        throw new ObjectDisposedException(nameof(WindowsCaptureFrame));

    public void Dispose() => _source = null;
}

internal sealed class WindowsScreenCaptureService : IScreenCaptureService
{
    public void Capture(long requestId, Action<CaptureResult> completion)
    {
        var screen = Forms.Screen.FromPoint(Forms.Cursor.Position);
        var bounds = screen.Bounds;
        try
        {
            using var bitmap = new Drawing.Bitmap(bounds.Width, bounds.Height,
                DrawingImaging.PixelFormat.Format32bppPArgb);
            using (var graphics = Drawing.Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(bounds.Location, Drawing.Point.Empty, bounds.Size,
                    Drawing.CopyPixelOperation.SourceCopy);
            }

            var source = CopyToBitmapSource(bitmap);
            completion(new CaptureResult(requestId, new WindowsCaptureFrame(source),
                new DisplayDescriptor(screen.DeviceName, bounds.X, bounds.Y,
                    bounds.Width, bounds.Height, 1)));
        }
        catch (Exception error)
        {
            completion(new CaptureResult(requestId, null,
                new DisplayDescriptor(string.Empty, 0, 0, 0, 0, 1),
                WorkspaceErrorCode.CaptureFailed, $"无法截取当前显示器：{error.Message}"));
        }
    }

    private static BitmapSource CopyToBitmapSource(Drawing.Bitmap bitmap)
    {
        var rectangle = new Drawing.Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rectangle, DrawingImaging.ImageLockMode.ReadOnly,
            DrawingImaging.PixelFormat.Format32bppPArgb);
        try
        {
            if (data.Stride <= 0)
                throw new InvalidOperationException("无法读取截图像素。");

            var source = BitmapSource.Create(bitmap.Width, bitmap.Height, 96, 96,
                PixelFormats.Pbgra32, null, data.Scan0, checked(data.Stride * bitmap.Height),
                data.Stride);
            source.Freeze();
            return source;
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }
}

internal sealed class WindowsWorkspaceWindowFactory : INativeWorkspaceWindowFactory
{
    public INativeWorkspaceWindow Create() => new WindowsWorkspaceWindow();
}

internal sealed class WindowsWorkspaceWindow : Window, INativeWorkspaceWindow
{
    private const int WmMouseHWheel = 0x020E;
    private const uint SwpNoOwnerZOrder = 0x0200;
    private const double SpotlightRadius = 90.0;
    private const double LaserPointerRadius = 7.0;
    private const double LaserDrawingHoldDurationSeconds = 3.0;
    private const double LaserDrawingFadeDurationSeconds = 0.8;
    private const double LaserDrawingMinimumPointDistanceSquared = 0.25;
    private static readonly nint HwndTopmost = new(-1);

    private readonly Grid _root;
    private readonly System.Windows.Controls.Image _image;
    private readonly Border _hud;
    private readonly TextBlock _hudText;
    private readonly RadialGradientBrush _spotlightBrush;
    private readonly System.Windows.Shapes.Rectangle _spotlight;
    private readonly Canvas _laserDrawingLayer;
    private readonly System.Windows.Shapes.Ellipse _laserPointer;
    private readonly List<System.Windows.Shapes.Polyline> _laserDrawings = [];
    private readonly TranslateTransform _laserPointerTransform = new();
    private readonly MatrixTransform _imageTransform = new();
    private readonly DispatcherTimer _qualityTimer;
    private readonly DispatcherTimer _hudDelayTimer;
    private WindowsCaptureFrame? _frame;
    private HwndSource? _windowSource;
    private string? _displayId;
    private Drawing.Rectangle _targetBounds;
    private System.Windows.Point _previousDragPoint;
    private System.Windows.Shapes.Polyline? _activeLaserDrawing;
    private bool _dragging;
    private bool _laserDrawingMode;
    private bool _monitoringDisplays;
    private bool _closed;
    private bool _disposed;
    private TransformState _transform = TransformState.Identity;

    public WindowsWorkspaceWindow()
    {
        AllowsTransparency = false;
        Background = System.Windows.Media.Brushes.Black;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        WindowStyle = WindowStyle.None;
        UseLayoutRounding = true;
        Cursor = System.Windows.Input.Cursors.None;

        _image = new System.Windows.Controls.Image
        {
            RenderTransform = _imageTransform,
            RenderTransformOrigin = new System.Windows.Point(0, 0),
            SnapsToDevicePixels = true,
            Stretch = Stretch.Fill,
        };
        _image.SizeChanged += (_, _) => ApplyTransform();
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);

        _spotlightBrush = new RadialGradientBrush
        {
            Center = new System.Windows.Point(0, 0),
            GradientOrigin = new System.Windows.Point(0, 0),
            MappingMode = BrushMappingMode.Absolute,
            RadiusX = SpotlightRadius,
            RadiusY = SpotlightRadius,
            SpreadMethod = GradientSpreadMethod.Pad,
        };
        _spotlightBrush.GradientStops.Add(new GradientStop(
            System.Windows.Media.Colors.Transparent, 0));
        _spotlightBrush.GradientStops.Add(new GradientStop(
            System.Windows.Media.Colors.Transparent, 0.72));
        _spotlightBrush.GradientStops.Add(new GradientStop(
            System.Windows.Media.Color.FromArgb(184, 0, 0, 0), 1));
        _spotlight = new System.Windows.Shapes.Rectangle
        {
            Fill = _spotlightBrush,
            IsHitTestVisible = false,
            Visibility = Visibility.Collapsed,
        };
        _laserDrawingLayer = new Canvas
        {
            ClipToBounds = true,
            IsHitTestVisible = false,
            RenderTransform = _imageTransform,
            RenderTransformOrigin = new System.Windows.Point(0, 0),
        };
        _laserPointer = new System.Windows.Shapes.Ellipse
        {
            Fill = new SolidColorBrush(System.Windows.Media.Color.FromArgb(245, 255, 13, 13)),
            Height = LaserPointerRadius * 2,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
            IsHitTestVisible = false,
            RenderTransform = _laserPointerTransform,
            Stroke = System.Windows.Media.Brushes.White,
            StrokeThickness = 1,
            VerticalAlignment = System.Windows.VerticalAlignment.Top,
            Visibility = Visibility.Collapsed,
            Width = LaserPointerRadius * 2,
        };

        _hudText = new TextBlock
        {
            FontFamily = new System.Windows.Media.FontFamily("Consolas"),
            FontSize = 18,
            FontWeight = FontWeights.Bold,
            Foreground = System.Windows.Media.Brushes.White,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment = System.Windows.VerticalAlignment.Center,
            Text = "100%",
        };
        _hud = new Border
        {
            Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(184, 0, 0, 0)),
            Child = _hudText,
            CornerRadius = new CornerRadius(7),
            Height = 36,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
            IsHitTestVisible = false,
            Margin = new Thickness(16),
            Opacity = 0,
            VerticalAlignment = System.Windows.VerticalAlignment.Bottom,
            Width = 88,
        };

        _root = new Grid
        {
            Background = System.Windows.Media.Brushes.Black,
            ClipToBounds = true,
        };
        _root.Children.Add(_image);
        _root.Children.Add(_spotlight);
        _root.Children.Add(_laserDrawingLayer);
        _root.Children.Add(_laserPointer);
        _root.Children.Add(_hud);
        Content = _root;

        _qualityTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(120),
        };
        _qualityTimer.Tick += RestoreHighQuality;
        _hudDelayTimer = new DispatcherTimer(DispatcherPriority.Normal)
        {
            Interval = TimeSpan.FromMilliseconds(800),
        };
        _hudDelayTimer.Tick += FadeHud;
    }

    public event Action? DismissRequested;
    public event Action<double, double, double>? ZoomRequested;
    public event Action<double, double, double>? MagnifyRequested;
    public event Action<double, double>? PanRequested;
    public event Action? ResetRequested;
    public event Action? FullResetRequested;
    public event Action<double, double>? CenterRequested;
    public event Action? ToggleHorizontalFlipRequested;
    public event Action? TargetDisplayDisconnected;

    WindowShowResult INativeWorkspaceWindow.Show(ICaptureFrame frame, DisplayDescriptor display)
    {
        if (frame is not WindowsCaptureFrame windowsFrame)
            return WindowShowResult.Failure("无法显示工作窗口（验证截图）：截图类型无效");

        var screen = Forms.Screen.AllScreens.FirstOrDefault(candidate =>
            string.Equals(candidate.DeviceName, display.DisplayId,
                StringComparison.OrdinalIgnoreCase));
        if (screen is null)
            return WindowShowResult.Failure(
                $"无法显示工作窗口（查找显示器）：找不到 {display.DisplayId}");

        _displayId = display.DisplayId;
        _targetBounds = screen.Bounds;
        _image.Source = windowsFrame.Source;

        var stage = "准备窗口";
        try
        {
            stage = "显示 WPF 窗口";
            base.Show();

            stage = "获取窗口句柄";
            var handle = new WindowInteropHelper(this).Handle;
            if (handle == 0)
                throw new InvalidOperationException("WPF 未创建窗口句柄。");

            stage = "安装窗口消息钩子";
            _windowSource = HwndSource.FromHwnd(handle) ??
                throw new InvalidOperationException("无法获取 WPF 窗口消息源。");
            _windowSource.AddHook(WindowMessageHook);

            stage = "设置窗口位置";
            if (!SetWindowPos(handle, HwndTopmost, _targetBounds.X,
                    _targetBounds.Y, _targetBounds.Width, _targetBounds.Height,
                    SwpNoOwnerZOrder))
            {
                throw new Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error());
            }

            stage = "监听显示器变化";
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
            _monitoringDisplays = true;

            stage = "激活窗口";
            Activate();
            Focus();
            SetLaserPointerActive(true);
            _frame = windowsFrame;
            return WindowShowResult.Success;
        }
        catch (Exception error)
        {
            var win32Code = error is Win32Exception win32 ?
                $"，Win32={win32.NativeErrorCode}" : string.Empty;
            CleanupFailedShow();
            return WindowShowResult.Failure(
                $"无法显示工作窗口（{stage}）：{DescribeException(error)}{win32Code}");
        }
    }

    private static string DescribeException(Exception error)
    {
        var root = error.GetBaseException();
        return ReferenceEquals(root, error)
            ? $"{error.GetType().Name}: {error.Message}"
            : $"{error.GetType().Name}: {error.Message} -> {root.GetType().Name}: {root.Message}";
    }

    private void CleanupFailedShow()
    {
        StopMonitoringDisplays();
        _windowSource?.RemoveHook(WindowMessageHook);
        _windowSource = null;
        _image.Source = null;
        _qualityTimer.Stop();
        _hudDelayTimer.Stop();
        AbortMouseInteraction();
        ClearLaserDrawings();
        if (!_closed)
        {
            try
            {
                Close();
            }
            catch (InvalidOperationException)
            {
                // The failed Show may already have torn down the WPF window.
            }
            _closed = true;
        }
    }

    public void UpdateTransform(TransformState transform, bool showHud)
    {
        if (_disposed) return;

        _transform = transform;
        ApplyTransform();
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.Linear);
        _qualityTimer.Stop();
        _qualityTimer.Start();

        if (showHud)
            ShowHud(transform.Scale);
    }

    private void ApplyTransform()
    {
        var scaleX = _transform.IsHorizontallyFlipped ? -_transform.Scale : _transform.Scale;
        var offsetX = _transform.IsHorizontallyFlipped
            ? _transform.OffsetX + (_image.ActualWidth * _transform.Scale)
            : _transform.OffsetX;
        _imageTransform.Matrix = new Matrix(scaleX, 0, 0, _transform.Scale,
            offsetX, _transform.OffsetY);
    }

    private void RestoreHighQuality(object? sender, EventArgs e)
    {
        _qualityTimer.Stop();
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
    }

    private void ShowHud(double scale)
    {
        _hudText.Text = $"{scale * 100:0}%";
        _hud.BeginAnimation(OpacityProperty, null);
        _hud.Opacity = 1;
        _hudDelayTimer.Stop();
        _hudDelayTimer.Start();
    }

    private void FadeHud(object? sender, EventArgs e)
    {
        _hudDelayTimer.Stop();
        _hud.BeginAnimation(OpacityProperty, new DoubleAnimation
        {
            Duration = TimeSpan.FromMilliseconds(200),
            From = 1,
            To = 0,
            FillBehavior = FillBehavior.HoldEnd,
        });
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (_activeLaserDrawing is not null || _dragging)
            EndMouseInteraction();
        var point = e.GetPosition(_root);
        UpdateLaserPointerCenter(point);
        Mouse.Capture(this);
        if (_laserDrawingMode)
            BeginLaserDrawing(ToCanvasPoint(point));
        else
        {
            _dragging = true;
            _previousDragPoint = point;
        }
        e.Handled = true;
    }

    protected override void OnMouseMove(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var point = e.GetPosition(_root);
        UpdateLaserPointerCenter(point);
        if (_spotlight.Visibility == Visibility.Visible)
            UpdateSpotlightCenter(point);
        if (_activeLaserDrawing is not null)
        {
            if (e.LeftButton != MouseButtonState.Pressed)
            {
                EndMouseInteraction();
                e.Handled = true;
                return;
            }

            AppendLaserDrawing(ToCanvasPoint(point));
            e.Handled = true;
            return;
        }
        if (!_dragging) return;
        if (e.LeftButton != MouseButtonState.Pressed)
        {
            EndMouseInteraction();
            return;
        }

        PanRequested?.Invoke(point.X - _previousDragPoint.X, point.Y - _previousDragPoint.Y);
        _previousDragPoint = point;
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        var point = e.GetPosition(_root);
        UpdateLaserPointerCenter(point);
        if (_spotlight.Visibility == Visibility.Visible)
            UpdateSpotlightCenter(point);
        if (_activeLaserDrawing is not null)
            AppendLaserDrawing(ToCanvasPoint(point));
        EndMouseInteraction();
        e.Handled = true;
    }

    protected override void OnMouseEnter(System.Windows.Input.MouseEventArgs e)
    {
        base.OnMouseEnter(e);
        SetLaserPointerActive(true);
    }

    protected override void OnMouseLeave(System.Windows.Input.MouseEventArgs e)
    {
        SetLaserPointerActive(false);
        base.OnMouseLeave(e);
    }

    protected override void OnLostMouseCapture(System.Windows.Input.MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        if (_activeLaserDrawing is not null || _dragging)
            EndMouseInteraction();
    }

    private void BeginLaserDrawing(System.Windows.Point point)
    {
        var drawing = new System.Windows.Shapes.Polyline
        {
            IsHitTestVisible = false,
            Stroke = new SolidColorBrush(System.Windows.Media.Color.FromArgb(235, 255, 13, 13)),
            StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeThickness = 3.5,
        };
        drawing.Points.Add(point);
        _laserDrawingLayer.Children.Add(drawing);
        _laserDrawings.Add(drawing);
        _activeLaserDrawing = drawing;
    }

    private void AppendLaserDrawing(System.Windows.Point point)
    {
        var drawing = _activeLaserDrawing;
        if (drawing is null) return;

        var previous = drawing.Points[^1];
        var deltaX = point.X - previous.X;
        var deltaY = point.Y - previous.Y;
        var minimumDistanceSquared = LaserDrawingMinimumPointDistanceSquared /
            (_transform.Scale * _transform.Scale);
        if ((deltaX * deltaX) + (deltaY * deltaY) < minimumDistanceSquared)
            return;

        drawing.Points.Add(point);
    }

    private System.Windows.Point ToCanvasPoint(System.Windows.Point point)
    {
        var rootFromCanvas = _imageTransform.Matrix;
        if (!rootFromCanvas.HasInverse) return point;
        rootFromCanvas.Invert();
        return rootFromCanvas.Transform(point);
    }

    private void EndMouseInteraction()
    {
        EndActiveLaserDrawing();
        _dragging = false;
        if (IsMouseCaptured)
            Mouse.Capture(null);
        Cursor = System.Windows.Input.Cursors.None;
    }

    private void EndActiveLaserDrawing()
    {
        var drawing = _activeLaserDrawing;
        if (drawing is null) return;

        _activeLaserDrawing = null;
        var fade = new DoubleAnimation
        {
            BeginTime = TimeSpan.FromSeconds(LaserDrawingHoldDurationSeconds),
            Duration = TimeSpan.FromSeconds(LaserDrawingFadeDurationSeconds),
            FillBehavior = FillBehavior.HoldEnd,
            From = 1,
            To = 0,
        };
        fade.Completed += (_, _) => RemoveLaserDrawing(drawing);
        drawing.BeginAnimation(OpacityProperty, fade);
    }

    private void AbortMouseInteraction()
    {
        _activeLaserDrawing = null;
        _dragging = false;
        if (IsMouseCaptured)
            Mouse.Capture(null);
        Cursor = System.Windows.Input.Cursors.None;
    }

    private void RemoveLaserDrawing(System.Windows.Shapes.Polyline drawing)
    {
        if (!_laserDrawings.Remove(drawing)) return;
        drawing.BeginAnimation(OpacityProperty, null);
        _laserDrawingLayer.Children.Remove(drawing);
    }

    private void ClearLaserDrawings()
    {
        _activeLaserDrawing = null;
        foreach (var drawing in _laserDrawings)
            drawing.BeginAnimation(OpacityProperty, null);
        _laserDrawings.Clear();
        _laserDrawingLayer.Children.Clear();
    }

    protected override void OnPreviewMouseWheel(MouseWheelEventArgs e)
    {
        base.OnPreviewMouseWheel(e);
        var point = e.GetPosition(_root);
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0)
            MagnifyRequested?.Invoke(e.Delta / 1200.0, point.X, point.Y);
        else
            ZoomRequested?.Invoke(e.Delta / 12.0, point.X, point.Y);
        e.Handled = true;
    }

    protected override void OnPreviewKeyDown(System.Windows.Input.KeyEventArgs e)
    {
        if (TryHandlePresetScale(e))
            return;
        if (e.Key == Key.R && Keyboard.Modifiers == ModifierKeys.None)
        {
            if (!e.IsRepeat)
                FullResetRequested?.Invoke();
            e.Handled = true;
            return;
        }
        if (e.Key == Key.C && Keyboard.Modifiers == ModifierKeys.None)
        {
            if (!e.IsRepeat)
                CenterRequested?.Invoke(_root.ActualWidth, _root.ActualHeight);
            e.Handled = true;
            return;
        }
        if (e.Key == Key.D && Keyboard.Modifiers == ModifierKeys.None)
        {
            if (!e.IsRepeat)
                _laserDrawingMode = !_laserDrawingMode;
            e.Handled = true;
            return;
        }
        if (e.Key == Key.M)
        {
            if (!e.IsRepeat)
                ToggleHorizontalFlipRequested?.Invoke();
            e.Handled = true;
            return;
        }
        if (e.Key == Key.F)
        {
            SetSpotlightActive(true);
            e.Handled = true;
            return;
        }
        if (e.Key == Key.Escape)
        {
            DismissRequested?.Invoke();
            e.Handled = true;
            return;
        }
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0 &&
            (e.Key == Key.D0 || e.Key == Key.NumPad0))
        {
            if (!e.IsRepeat)
                ResetRequested?.Invoke();
            e.Handled = true;
            return;
        }
        base.OnPreviewKeyDown(e);
    }

    protected override void OnPreviewKeyUp(System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.F)
        {
            SetSpotlightActive(false);
            e.Handled = true;
            return;
        }
        base.OnPreviewKeyUp(e);
    }

    protected override void OnDeactivated(EventArgs e)
    {
        SetSpotlightActive(false);
        EndMouseInteraction();
        base.OnDeactivated(e);
    }

    private void SetSpotlightActive(bool active)
    {
        if (active)
        {
            UpdateSpotlightCenter(Mouse.GetPosition(_root));
            _spotlight.Visibility = Visibility.Visible;
        }
        else
        {
            _spotlight.Visibility = Visibility.Collapsed;
        }
    }

    private bool TryHandlePresetScale(System.Windows.Input.KeyEventArgs e)
    {
        if (e.IsRepeat || (Keyboard.Modifiers &
                (ModifierKeys.Alt | ModifierKeys.Control | ModifierKeys.Shift | ModifierKeys.Windows)) != 0)
            return false;

        double? scale = e.Key switch
        {
            Key.D0 or Key.NumPad0 => 1.0,
            Key.D1 or Key.NumPad1 => 1.5,
            Key.D2 or Key.NumPad2 => 2.0,
            Key.D9 or Key.NumPad9 => 0.7,
            _ => null,
        };
        if (scale is null)
            return false;

        if (scale.Value == 1.0)
            ResetRequested?.Invoke();
        else
        {
            var point = Mouse.GetPosition(_root);
            MagnifyRequested?.Invoke(scale.Value - _transform.Scale, point.X, point.Y);
        }
        e.Handled = true;
        return true;
    }

    private void SetLaserPointerActive(bool active)
    {
        if (active)
        {
            UpdateLaserPointerCenter(Mouse.GetPosition(_root));
            _laserPointer.Visibility = Visibility.Visible;
        }
        else
        {
            _laserPointer.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateLaserPointerCenter(System.Windows.Point point)
    {
        _laserPointerTransform.X = point.X - LaserPointerRadius;
        _laserPointerTransform.Y = point.Y - LaserPointerRadius;
    }

    private void UpdateSpotlightCenter(System.Windows.Point point)
    {
        _spotlightBrush.Center = point;
        _spotlightBrush.GradientOrigin = point;
    }

    private nint WindowMessageHook(nint hwnd, int message, nint wParam, nint lParam,
        ref bool handled)
    {
        if (message == WmMouseHWheel)
        {
            var delta = unchecked((short)(wParam.ToInt64() >> 16));
            PanRequested?.Invoke(delta / 4.0, 0);
            handled = true;
        }
        return 0;
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
    {
        if (_disposed || Dispatcher.HasShutdownStarted) return;
        _ = Dispatcher.BeginInvoke(CheckTargetDisplay);
    }

    private void CheckTargetDisplay()
    {
        if (_disposed || _displayId is null) return;
        var screen = Forms.Screen.AllScreens.FirstOrDefault(candidate =>
            string.Equals(candidate.DeviceName, _displayId,
                StringComparison.OrdinalIgnoreCase));
        if (screen is null || screen.Bounds != _targetBounds)
            TargetDisplayDisconnected?.Invoke();
    }

    private void StopMonitoringDisplays()
    {
        if (!_monitoringDisplays) return;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        _monitoringDisplays = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        StopMonitoringDisplays();
        _qualityTimer.Stop();
        _hudDelayTimer.Stop();
        _windowSource?.RemoveHook(WindowMessageHook);
        _windowSource = null;
        _image.Source = null;
        _frame?.Dispose();
        _frame = null;
        AbortMouseInteraction();
        ClearLaserDrawings();
        if (!_closed)
        {
            Close();
            _closed = true;
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    [return: System.Runtime.InteropServices.MarshalAs(
        System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool SetWindowPos(nint window, nint insertAfter, int x, int y,
        int width, int height, uint flags);
}
#endif
