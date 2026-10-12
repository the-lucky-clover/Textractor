using System;
using System.IO;
using System.Threading.Tasks;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

/// <summary>
/// Handles screenshot storage decisions: ask, delete, or save to folder.
/// </summary>
public static class StorageService
{
    public static string DefaultScreenshotsFolder => Path.Combine(
        AppPaths.DataDirectory,
        "Screenshots");

    public static string GetScreenshotsFolder(AppSettings settings)
    {
        if (!string.IsNullOrEmpty(settings.CustomScreenshotsFolder) && 
            Directory.Exists(settings.CustomScreenshotsFolder))
        {
            return settings.CustomScreenshotsFolder;
        }
        return DefaultScreenshotsFolder;
    }

    /// <summary>
    /// Govern the storage of a captured image based on user settings.
    /// </summary>
    public static async Task<StorageDecision> GovernStorageAsync(
        CapturedImage capture, 
        AppSettings settings,
        Func<StorageDecision, Task>? onDecision = null)
    {
        var decision = settings.StorageDecision;

        if (decision == StorageDecision.Ask)
        {
            decision = await ToastService.Shared.RequestStorageDecisionAsync(settings.StorageDecisionTimeoutSeconds);
        }

        switch (decision)
        {
            case StorageDecision.Delete:
                DeleteCapture(capture);
                break;

            case StorageDecision.SaveToFolder:
                SaveCapture(capture, settings);
                break;

            case StorageDecision.Ask:
                // Should not reach here, handled above
                SaveCapture(capture, settings);
                break;
        }

        if (onDecision != null)
        {
            await onDecision(decision);
        }

        return decision;
    }

    private static void SaveCapture(CapturedImage capture, AppSettings settings)
    {
        try
        {
            var folder = GetScreenshotsFolder(settings);
            Directory.CreateDirectory(folder);

            var fileName = $"Textractor_{capture.CapturedAt:yyyyMMdd_HHmmss}_{capture.Id:N}.png";
            var destPath = Path.Combine(folder, fileName);

            if (File.Exists(capture.FilePath))
            {
                File.Copy(capture.FilePath, destPath, true);
                File.Delete(capture.FilePath);
                capture.FilePath = destPath;
                LoggerService.Log($"Saved capture to {destPath}");
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to save capture", ex);
            throw;
        }
    }

    private static void DeleteCapture(CapturedImage capture)
    {
        try
        {
            if (File.Exists(capture.FilePath))
            {
                File.Delete(capture.FilePath);
                LoggerService.Log($"Deleted capture {capture.FilePath}");
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to delete capture", ex);
            throw;
        }
    }

    /// <summary>
    /// Move a capture to a specific folder (user-initiated).
    /// </summary>
    public static bool MoveCaptureToFolder(CapturedImage capture, string folder)
    {
        try
        {
            Directory.CreateDirectory(folder);
            var fileName = Path.GetFileName(capture.FilePath);
            var destPath = Path.Combine(folder, fileName);
            
            if (File.Exists(capture.FilePath))
            {
                File.Move(capture.FilePath, destPath, true);
                capture.FilePath = destPath;
                return true;
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to move capture", ex);
        }
        return false;
    }
}

