using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Microsoft.UI.Windowing;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Windows.Foundation;
using Windows.Graphics;
using Textractor.Windows.Models;
using Textractor.Windows.Services;

namespace Textractor.Windows.Views;

public sealed partial class CaptureOverlayWindow : Window
{
    // Callbacks
    public Action<Rect>? OnRegionCaptured;
    public Action<IntPtr>? OnWindowCaptured;
    public Action? OnCancel;

    // State
    private CaptureMode _mode;
    private Point _cursorPoint;
    private Point? _dragStart;
    private Point? _dragCurrent;
    private WindowDescriptor? _hoveredWindow;
    private List<WindowDescriptor> _windows = new();
    private bool _showsGrid = true;
    private bool _isAnimating = false;

    // Window info for coordinate conversion
    private Rect _overlayFrame;
    private double _primaryDisplayHeight;

    // Animation
    private Storyboard? _windowGlowStoryboard;

    public CaptureOverlayWindow(CaptureMode initialMode = CaptureMode.Crosshair)
    {
        _mode = initialMode;
        this.InitializeComponent();
        
        this.ExtendsContentIntoTitleBar = true;
        this.AppWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        
        // Set window to cover entire screen
        SetupFullScreenWindow();
        
        // Initialize animations
        InitializeAnimations();
        
        // Set up input handling
        this.KeyDown += CaptureOverlayWindow_KeyDown;
        this.PointerMoved += CaptureOverlayWindow_PointerMoved;
        this.PointerPressed += CaptureOverlayWindow_PointerPressed;
        this.PointerReleased += CaptureOverlayWindow_PointerReleased;
        this.PointerWheelChanged += CaptureOverlayWindow_PointerWheelChanged;
        
        // Load windows list
        LoadWindows();
        
        // Start status bar animation
        AnimateStatusBarIn();
    }

    private void SetupFullScreenWindow()
    {
        var displayArea = DisplayArea.Primary;
        if (displayArea != null)
        {
            var workArea = displayArea.WorkArea;
            _overlayFrame = new Rect(workArea.X, workArea.Y, workArea.Width, workArea.Height);
            
            this.AppWindow.MoveAndResize(new RectInt32(
                workArea.X, workArea.Y, workArea.Width, workArea.Height));
            
            // Get primary display height for coordinate conversion
            _primaryDisplayHeight = workArea.Height;
        }
        
        // Set window level to topmost
        this.AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
    }

    private void InitializeAnimations()
    {
        // Window glow pulse animation
        _windowGlowStoryboard = new Storyboard();
        
        var pulseAnim1 = new DoubleAnimation
        {
            From = 0.45,
            To = 0.95,
            Duration = TimeSpan.FromSeconds(0.95),
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };
        
        var pulseAnim2 = new DoubleAnimation
        {
            From = 14,
            To = 28,
            Duration = TimeSpan.FromSeconds(0.95),
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };

        Storyboard.SetTarget(pulseAnim1, WindowGlowShadow);
        Storyboard.SetTargetProperty(pulseAnim1, "Opacity");
        
        Storyboard.SetTarget(pulseAnim2, WindowGlowShadow);
        Storyboard.SetTargetProperty(pulseAnim2, "BlurRadius");

        _windowGlowStoryboard.Children.Add(pulseAnim1);
        _windowGlowStoryboard.Children.Add(pulseAnim2);
    }

    private async void AnimateStatusBarIn()
    {
        var storyboard = new Storyboard();
        
        var opacityAnim = new DoubleAnimation { From = 0, To = 1, Duration = TimeSpan.FromSeconds(0.3) };
        var translateAnim = new DoubleAnimation { From = -20, To = 0, Duration = TimeSpan.FromSeconds(0.3), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };

        Storyboard.SetTarget(opacityAnim, StatusBarBorder);
        Storyboard.SetTargetProperty(opacityAnim, "Opacity");
        
        Storyboard.SetTarget(translateAnim, StatusBarTransform);
        Storyboard.SetTargetProperty(translateAnim, "TranslateY");

        storyboard.Children.Add(opacityAnim);
        storyboard.Children.Add(translateAnim);
        
        await storyboard.BeginAsync();
    }

    private void LoadWindows()
    {
        _windows = ScreenshotService.Shared.EnumerateWindows();
        UpdateWindowOutlines();
    }

    private void UpdateWindowOutlines()
    {
        WindowOutlinesCanvas.Children.Clear();
        
        foreach (var window in _windows)
        {
            if (window.Id == _hoveredWindow?.Id) continue;
            
            var rect = ConvertToOverlay(window.Bounds);
            var border = new Border
            {
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x29, 0xE6, 0xEA, 0xDC)), // Chalk with opacity
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(5),
                Width = rect.Width,
                Height = rect.Height
            };
            
            Canvas.SetLeft(border, rect.X);
            Canvas.SetTop(border, rect.Y);
            WindowOutlinesCanvas.Children.Add(border);
        }
    }

    private void UpdateHoveredWindow()
    {
        if (_mode != CaptureMode.Window) return;
        
        _hoveredWindow = _windows.FirstOrDefault(w => 
            ConvertToOverlay(w.Bounds).Contains(_cursorPoint));
        
        UpdateWindowOutlines();
        UpdateWindowGlowHighlight();
        UpdateWindowInfoLabel();
    }

    private void UpdateWindowGlowHighlight()
    {
        if (_hoveredWindow == null)
        {
            WindowGlowBorder.Visibility = Visibility.Collapsed;
            _windowGlowStoryboard?.Stop();
            return;
        }

        var rect = ConvertToOverlay(_hoveredWindow.Bounds);
        
        WindowGlowBorder.Width = rect.Width;
        WindowGlowBorder.Height = rect.Height;
        Canvas.SetLeft(WindowGlowBorder, rect.X);
        Canvas.SetTop(WindowGlowBorder, rect.Y);
        WindowGlowBorder.Visibility = Visibility.Visible;
        
        _windowGlowStoryboard?.Begin();
    }

    private void UpdateWindowInfoLabel()
    {
        if (_hoveredWindow == null)
        {
            WindowInfoBorder.Visibility = Visibility.Collapsed;
            return;
        }

        WindowNameText.Text = _hoveredWindow.DisplayName;
        WindowSizeText.Text = $"{_hoveredWindow.Bounds.Width:F0} × {_hoveredWindow.Bounds.Height:F0}";
        
        var rect = ConvertToOverlay(_hoveredWindow.Bounds);
        var x = _cursorPoint.X + 90;
        var y = Math.Max(_cursorPoint.Y + 90, 60);
        
        Canvas.SetLeft(WindowInfoBorder, x);
        Canvas.SetTop(WindowInfoBorder, y);
        WindowInfoBorder.Visibility = Visibility.Visible;
    }

    private void UpdateCrosshair()
    {
        // Update crosshair lines
        CrosshairCanvas.Children.Clear();
        
        var dashedBrush = new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF));
        var solidBrush = new SolidColorBrush(Color.FromArgb(0xA6, 0xFF, 0xFF, 0xFF));
        
        // Vertical line (dashed)
        var vLine = new Line
        {
            X1 = _cursorPoint.X,
            Y1 = 0,
            X2 = _cursorPoint.X,
            Y2 = _overlayFrame.Height,
            Stroke = dashedBrush,
            StrokeThickness = 0.7,
            StrokeDashArray = new DoubleCollection { 4, 6 }
        };
        CrosshairCanvas.Children.Add(vLine);
        
        // Horizontal line (dashed)
        var hLine = new Line
        {
            X1 = 0,
            Y1 = _cursorPoint.Y,
            X2 = _overlayFrame.Width,
            Y2 = _cursorPoint.Y,
            Stroke = dashedBrush,
            StrokeThickness = 0.7,
            StrokeDashArray = new DoubleCollection { 4, 6 }
        };
        CrosshairCanvas.Children.Add(hLine);
        
        // Solid selection rectangle if dragging
        if (_dragStart.HasValue && _dragCurrent.HasValue)
        {
            var selectionRect = GetSelectionRect();
            if (selectionRect.Width > 0 && selectionRect.Height > 0)
            {
                SelectionRectBorder.Width = selectionRect.Width;
                SelectionRectBorder.Height = selectionRect.Height;
                SelectionRectTransform.X = selectionRect.X;
                SelectionRectTransform.Y = selectionRect.Y;
                SelectionRectBorder.Visibility = Visibility.Visible;
                
                // Update handles
                UpdateHandles(selectionRect);
                
                // Update coords readout
                UpdateCoordsReadout(selectionRect);
            }
        }
        
        // Cursor circle
        CursorCircleTransform.X = _cursorPoint.X - 11;
        CursorCircleTransform.Y = _cursorPoint.Y - 11;
        CursorCircle.Visibility = Visibility.Visible;
    }

    private void UpdateHandles(Rect rect)
    {
        HandlesCanvas.Children.Clear();
        HandlesCanvas.Visibility = Visibility.Visible;
        
        var handleSize = 10.0;
        var corners = new[]
        {
            new Point(rect.Left, rect.Top),
            new Point(rect.Right, rect.Top),
            new Point(rect.Left, rect.Bottom),
            new Point(rect.Right, rect.Bottom)
        };
        
        foreach (var corner in corners)
        {
            var ellipse = new Ellipse
            {
                Width = handleSize,
                Height = handleSize,
                Fill = new SolidColorBrush(Colors.White)
            };
            Canvas.SetLeft(ellipse, corner.X - handleSize / 2);
            Canvas.SetTop(ellipse, corner.Y - handleSize / 2);
            HandlesCanvas.Children.Add(ellipse);
        }
    }

    private void UpdateCoordsReadout(Rect rect)
    {
        CoordsReadoutText.Text = $"{rect.Width:F0} × {rect.Height:F0}";
        
        CoordsReadoutTransform.X = rect.Right - 64;
        CoordsReadoutTransform.Y = rect.Bottom + 22;
        CoordsReadoutBorder.Visibility = Visibility.Visible;
    }

    private void UpdateGridOverlay()
    {
        GridOverlayCanvas.Children.Clear();
        
        if (!_showsGrid) return;
        
        var strokeBrush = new SolidColorBrush(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF));
        var dashArray = new DoubleCollection { 3, 5 };
        
        // Vertical lines at 1/3 and 2/3
        for (int i = 1; i <= 2; i++)
        {
            var x = _overlayFrame.Width * i / 3.0;
            var line = new Line
            {
                X1 = x,
                Y1 = 0,
                X2 = x,
                Y2 = _overlayFrame.Height,
                Stroke = strokeBrush,
                StrokeThickness = 0.6,
                StrokeDashArray = dashArray
            };
            GridOverlayCanvas.Children.Add(line);
        }
        
        // Horizontal lines at 1/3 and 2/3
        for (int i = 1; i <= 2; i++)
        {
            var y = _overlayFrame.Height * i / 3.0;
            var line = new Line
            {
                X1 = 0,
                Y1 = y,
                X2 = _overlayFrame.Width,
                Y2 = y,
                Stroke = strokeBrush,
                StrokeThickness = 0.6,
                StrokeDashArray = dashArray
            };
            GridOverlayCanvas.Children.Add(line);
        }
        
        GridOverlayCanvas.Visibility = Visibility.Visible;
    }

    private void UpdateModeUI()
    {
        ModeText.Text = _mode == CaptureMode.Crosshair ? "REGION  •  DRAG" : "WINDOW  •  CLICK";
        GridText.Text = _showsGrid ? "G: GRID  ON" : "G: GRID  OFF";
        GridText.Foreground = _showsGrid ? BreakingDadToxicGreenBrush : 
            new SolidColorBrush(Color.FromArgb(0xFF, 0x88, 0x88, 0x88));
        
        CrosshairCanvas.Visibility = _mode == CaptureMode.Crosshair ? Visibility.Visible : Visibility.Collapsed;
        CursorCircle.Visibility = _mode == CaptureMode.Crosshair ? Visibility.Visible : Visibility.Collapsed;
        SelectionRectBorder.Visibility = _mode == CaptureMode.Crosshair ? Visibility.Visible : Visibility.Collapsed;
        HandlesCanvas.Visibility = _mode == CaptureMode.Crosshair ? Visibility.Visible : Visibility.Collapsed;
        CoordsReadoutBorder.Visibility = _mode == CaptureMode.Crosshair ? Visibility.Visible : Visibility.Collapsed;
        
        WindowOutlinesCanvas.Visibility = _mode == CaptureMode.Window ? Visibility.Visible : Visibility.Collapsed;
        WindowGlowBorder.Visibility = _mode == CaptureMode.Window ? Visibility.Visible : Visibility.Collapsed;
        WindowInfoBorder.Visibility = _mode == CaptureMode.Window ? Visibility.Visible : Visibility.Collapsed;
        
        UpdateGridOverlay();
    }

    private Rect GetSelectionRect()
    {
        if (!_dragStart.HasValue || !_dragCurrent.HasValue) return Rect.Empty;
        
        var start = _dragStart.Value;
        var current = _dragCurrent.Value;
        
        return new Rect(
            Math.Min(start.X, current.X),
            Math.Min(start.Y, current.Y),
            Math.Abs(start.X - current.X),
            Math.Abs(start.Y - current.Y)
        );
    }

    private Rect ConvertToOverlay(Rect screenRect)
    {
        // Convert from screen coordinates to overlay coordinates
        return new Rect(
            screenRect.X - _overlayFrame.X,
            screenRect.Y - _overlayFrame.Y,
            screenRect.Width,
            screenRect.Height
        );
    }

    private Rect ConvertToScreen(Rect overlayRect)
    {
        // Convert from overlay coordinates to screen coordinates
        return new Rect(
            overlayRect.X + _overlayFrame.X,
            overlayRect.Y + _overlayFrame.Y,
            overlayRect.Width,
            overlayRect.Height
        );
    }

    private void ToggleMode()
    {
        _mode = _mode == CaptureMode.Crosshair ? CaptureMode.Window : CaptureMode.Crosshair;
        _hoveredWindow = null;
        _dragStart = null;
        _dragCurrent = null;
        SelectionRectBorder.Visibility = Visibility.Collapsed;
        HandlesCanvas.Visibility = Visibility.Collapsed;
        CoordsReadoutBorder.Visibility = Visibility.Collapsed;
        UpdateModeUI();
        LoggerService.Log($"Capture mode switched to: {_mode}");
    }

    private void HandleAccept()
    {
        if (_mode == CaptureMode.Crosshair)
        {
            var rect = GetSelectionRect();
            if (rect.Width > 8 && rect.Height > 8)
            {
                var screenRect = ConvertToScreen(rect);
                OnRegionCaptured?.Invoke(screenRect);
                Close();
            }
        }
        else if (_mode == CaptureMode.Window && _hoveredWindow != null)
        {
            OnWindowCaptured?.Invoke(_hoveredWindow.Id);
            Close();
        }
    }

    private void Cancel()
    {
        OnCancel?.Invoke();
        Close();
    }

    // Event handlers
    private void CaptureOverlayWindow_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case Windows.System.VirtualKey.Space:
                ToggleMode();
                e.Handled = true;
                break;
            case Windows.System.VirtualKey.Escape:
                Cancel();
                e.Handled = true;
                break;
            case Windows.System.VirtualKey.Enter:
                HandleAccept();
                e.Handled = true;
                break;
            case Windows.System.VirtualKey.G:
                _showsGrid = !_showsGrid;
                UpdateGridOverlay();
                e.Handled = true;
                break;
        }
    }

    private void CaptureOverlayWindow_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        _cursorPoint = e.GetCurrentPoint(this).Position;
        UpdateCrosshair();
        UpdateHoveredWindow();
    }

    private void CaptureOverlayWindow_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_mode == CaptureMode.Crosshair)
        {
            _dragStart = _cursorPoint;
            _dragCurrent = _cursorPoint;
            LoggerService.Log($"[capture.drag] START at ({_cursorPoint.X:F0}, {_cursorPoint.Y:F0})");
        }
        else if (_mode == CaptureMode.Window)
        {
            // Click to capture window
            if (_hoveredWindow != null)
            {
                OnWindowCaptured?.Invoke(_hoveredWindow.Id);
                Close();
            }
        }
    }

    private void CaptureOverlayWindow_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_mode == CaptureMode.Crosshair && _dragStart.HasValue)
        {
            _dragCurrent = _cursorPoint;
            var rect = GetSelectionRect();
            LoggerService.Log($"[capture.drag] END at ({_cursorPoint.X:F0}, {_cursorPoint.Y:F0}) rect={rect.Width:F0}x{rect.Height:F0}");
            
            if (rect.Width > 8 && rect.Height > 8)
            {
                var screenRect = ConvertToScreen(rect);
                OnRegionCaptured?.Invoke(screenRect);
            }
            
            _dragStart = null;
            _dragCurrent = null;
            SelectionRectBorder.Visibility = Visibility.Collapsed;
            HandlesCanvas.Visibility = Visibility.Collapsed;
            CoordsReadoutBorder.Visibility = Visibility.Collapsed;
            Close();
        }
    }

    private void CaptureOverlayWindow_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
    {
        // Could be used for zoom, but not needed for basic capture
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        Cancel();
    }
}