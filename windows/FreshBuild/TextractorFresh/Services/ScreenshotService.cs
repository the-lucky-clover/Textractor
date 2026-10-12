using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using OpenCvSharp;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public class ScreenshotService
{
    // GDI-based screen capture methods
    
    public async Task<CapturedImage> CaptureRegionAsync(RectangleF rect)
    {
        return await Task.Run(() => CaptureRegionGDI(rect));
    }

    public async Task<(CapturedImage, WindowDescriptor)> CaptureWindowAsync(IntPtr windowHandle)
    {
        return await Task.Run(() =>
        {
            var window = EnumerateWindows().FirstOrDefault(w => w.Id == windowHandle);
            if (window == null)
                throw new InvalidOperationException("Window not found");

            var capture = CaptureWindowGDI(window);
            return (capture, window);
        });
    }

    public async Task<List<CapturedImage>> CaptureFullScreenAsync()
    {
        return await Task.Run(() =>
        {
            var captures = new List<CapturedImage>();
            var screens = GetDisplays();

            foreach (var (index, screen) in screens.Select((s, i) => (i, s)))
            {
                var capture = CaptureDisplayGDI(index);
                if (capture != null)
                    captures.Add(capture);
            }

            return captures;
        });
    }

    public async Task<CapturedImage> CaptureFromFileAsync(string filePath)
    {
        return await Task.Run(() =>
        {
            using var image = Cv2.ImRead(filePath, ImreadModes.Color);
            if (image.Empty()) throw new InvalidOperationException("This file could not be opened as an image. Choose a PNG, JPEG, BMP or TIFF file.");
            var tempPath = SaveToTemp(image);
            
            return new CapturedImage
            {
                Mode = CaptureMode.File,
                Origin = CaptureOrigin.File,
                Rect = new RectangleF(0, 0, image.Width, image.Height),
                FilePath = tempPath,
                CapturedAt = DateTimeOffset.Now
            };
        });
    }

    public List<WindowDescriptor> EnumerateWindows()
    {
        var windows = new List<WindowDescriptor>();
        
        EnumWindows((hWnd, lParam) =>
        {
            if (IsWindowVisible(hWnd))
            {
                GetWindowRect(hWnd, out RECT rect);
                
                var length = GetWindowTextLength(hWnd);
                var builder = new System.Text.StringBuilder(length + 1);
                GetWindowText(hWnd, builder, builder.Capacity);
                
                var length2 = GetWindowTextLength(GetAncestor(hWnd, 3)); // GA_ROOTOWNER
                var builder2 = new System.Text.StringBuilder(length2 + 1);
                GetWindowText(GetAncestor(hWnd, 3), builder2, builder2.Capacity);
                
                var isOnScreen = IsWindowVisible(hWnd) && rect.Width > 32 && rect.Height > 32;
                
                if (isOnScreen)
                {
                    windows.Add(new WindowDescriptor
                    {
                        Id = hWnd,
                        Name = builder.ToString(),
                        OwnerName = builder2.ToString(),
                        Bounds = new RectangleF(rect.Left, rect.Top, rect.Width, rect.Height),
                        Layer = 0,
                        Alpha = 1.0,
                        IsOnScreen = isOnScreen
                    });
                }
            }
            return true;
        }, IntPtr.Zero);
        
        return windows;
    }

    public List<(int Index, RectangleF Frame)> GetDisplays()
    {
        var displays = new List<(int, RectangleF)>();
        
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMonitor, hdcMonitor, lprcMonitor, dwData) =>
        {
            // Use the lprcMonitor directly from the callback
            var rectPtr = lprcMonitor;
            var rect = Marshal.PtrToStructure<RECT>(rectPtr);
            
            var frame = new RectangleF(
                rect.Left,
                rect.Top,
                rect.Width,
                rect.Height);
                
            displays.Add((displays.Count, frame));
            return true;
        }, IntPtr.Zero);
        
        return displays;
    }

    private CapturedImage CaptureRegionGDI(RectangleF rect)
    {
        var bounds = Rectangle.Intersect(Rectangle.Round(rect), System.Windows.Forms.SystemInformation.VirtualScreen);
        if (bounds.Width <= 0 || bounds.Height <= 0) throw new InvalidOperationException("Invalid capture region");
        using var cropped = new Bitmap(bounds.Width, bounds.Height);
        using (var graphics = Graphics.FromImage(cropped))
            graphics.CopyFromScreen(bounds.Location, System.Drawing.Point.Empty, bounds.Size);
        var tempPath = SaveToTemp(cropped);

        return new CapturedImage
        {
            Mode = CaptureMode.Crosshair,
            Origin = CaptureOrigin.Region,
            Rect = bounds,
            FilePath = tempPath,
            CapturedAt = DateTimeOffset.Now,
            ScreenIndex = GetDisplays().FindIndex(d => d.Frame.Contains(bounds.Location))
        };
    }

    private CapturedImage CaptureWindowGDI(WindowDescriptor window)
    {
        var tempPath = Path.Combine(
            AppPaths.DataDirectory,
            $"window_{Guid.NewGuid()}.png");

        Directory.CreateDirectory(Path.GetDirectoryName(tempPath)!);

        using var bitmap = CaptureWindowGDIImpl(window.Id);
        if (bitmap != null)
        {
            bitmap.Save(tempPath, System.Drawing.Imaging.ImageFormat.Png);
            
            return new CapturedImage
            {
                Mode = CaptureMode.Window,
                Origin = CaptureOrigin.Window,
                Rect = window.Bounds,
                FilePath = tempPath,
                CapturedAt = DateTimeOffset.Now
            };
        }

        throw new InvalidOperationException("Failed to capture window");
    }

    private CapturedImage CaptureDisplayGDI(int index)
    {
        var displays = GetDisplays();
        if (index >= displays.Count)
            throw new ArgumentOutOfRangeException(nameof(index));

        var (_, frame) = displays[index];
        var tempPath = Path.Combine(
            AppPaths.DataDirectory,
            $"display_{index}_{Guid.NewGuid()}.png");

        Directory.CreateDirectory(Path.GetDirectoryName(tempPath)!);

        using var bitmap = CaptureDisplayGDIImpl(index);
        if (bitmap != null)
        {
            bitmap.Save(tempPath, System.Drawing.Imaging.ImageFormat.Png);
            
            return new CapturedImage
            {
                Mode = CaptureMode.FullScreen,
                Origin = CaptureOrigin.FullScreen,
                Rect = frame,
                FilePath = tempPath,
                CapturedAt = DateTimeOffset.Now,
                ScreenIndex = index
            };
        }

        throw new InvalidOperationException("Failed to capture display");
    }

    private Bitmap? CaptureWindowGDIImpl(IntPtr hWnd)
    {
        try
        {
            GetWindowRect(hWnd, out RECT rect);
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;

            if (width <= 0 || height <= 0)
                return null;

            var bitmap = new Bitmap(width, height);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                var hdc = graphics.GetHdc();
                PrintWindow(hWnd, hdc, 0x00000002); // PW_RENDERFULLCONTENT
                graphics.ReleaseHdc(hdc);
            }
            return bitmap;
        }
        catch (Exception ex)
        {
            LoggerService.Error("GDI window capture failed", ex);
            return null;
        }
    }

    private Bitmap? CaptureDisplayGDIImpl(int displayIndex)
    {
        try
        {
            var displays = GetDisplays();
            if (displayIndex >= displays.Count)
                return null;

            var (_, frame) = displays[displayIndex];
            var bitmap = new Bitmap((int)frame.Width, (int)frame.Height);
            
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(
                    (int)frame.X, (int)frame.Y, 0, 0,
                    new System.Drawing.Size((int)frame.Width, (int)frame.Height),
                    CopyPixelOperation.SourceCopy);
            }
            return bitmap;
        }
        catch (Exception ex)
        {
            LoggerService.Error("GDI display capture failed", ex);
            return null;
        }
    }

    private string SaveToTemp(Bitmap image)
    {
        var dir = AppPaths.DataDirectory;
        Directory.CreateDirectory(dir);
        
        var path = Path.Combine(dir, $"{Guid.NewGuid()}.png");
        image.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        return path;
    }

    private string SaveToTemp(Mat image)
    {
        var dir = AppPaths.DataDirectory;
        Directory.CreateDirectory(dir);
        
        var path = Path.Combine(dir, $"{Guid.NewGuid()}.png");
        if (!Cv2.ImWrite(path, image)) throw new IOException("Could not save the imported image for OCR.");
        return path;
    }

    // P/Invoke declarations
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hWnd, int gaFlags);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public int Width => Right - Left;
        public int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public int dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }
}

