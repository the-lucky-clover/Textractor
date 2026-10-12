using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace Textractor.Windows.Services;

public static class PermissionService
{
    public static bool HasScreenCapturePermission()
    {
        // On Windows 10+, screen capture requires the app to have
        // the "ScreenScanning" capability in the app manifest (for packaged apps)
        // For desktop apps, GraphicsCapture API has its own permission dialog
        // We check if the Windows.Graphics.Capture API is supported

        try
        {
            var version = Environment.OSVersion.Version;
            return version.Major >= 10 && version.Build >= 17763; // Windows 10 1809+
        }
        catch
        {
            return false;
        }
    }

    public static bool HasClipboardPermission()
    {
        // On Windows, clipboard access requires the app to be running
        // For packaged apps, add the "userDataAccounts.readRestricted" capability
        return true; // Desktop apps have clipboard access by default
    }

    public static bool IsAdmin()
    {
        return new WindowsPrincipal(WindowsIdentity.GetCurrent())
            .IsInRole(WindowsBuiltInRole.Administrator);
    }

    public static bool RequestScreenCapturePermission()
    {
        // On Windows, the first GraphicsCapturePicker usage will prompt the user
        // This is handled by the OS automatically
        // We can also check and guide the user via Windows Settings if needed
        return HasScreenCapturePermission();
    }

    public static void OpenScreenCaptureSettings()
    {
        try
        {
            // Open Windows Settings for screen recording permissions
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "ms-settings:privacy-webcam",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to open screen capture settings", ex);
        }
    }
}