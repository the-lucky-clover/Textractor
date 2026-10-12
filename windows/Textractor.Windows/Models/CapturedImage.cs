using System;
using System.Drawing;

namespace Textractor.Windows.Models;

public class CapturedImage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public CaptureMode Mode { get; set; }
    public CaptureOrigin Origin { get; set; }
    public RectangleF Rect { get; set; }
    public string FilePath { get; set; } = "";
    public DateTimeOffset CapturedAt { get; set; } = DateTimeOffset.Now;
    public int ScreenIndex { get; set; }
}

public class WindowDescriptor
{
    public IntPtr Id { get; set; }
    public string? Name { get; set; }
    public string? OwnerName { get; set; }
    public RectangleF Bounds { get; set; }
    public int Layer { get; set; }
    public double Alpha { get; set; } = 1.0;
    public bool IsOnScreen { get; set; }

    public string DisplayName => !string.IsNullOrEmpty(Name) ? Name : 
                               !string.IsNullOrEmpty(OwnerName) ? OwnerName : 
                               $"Window {Id}";

    public bool IsCaptureEligible => Layer == 0 && IsOnScreen && Bounds.Width > 32 && Bounds.Height > 32;
}