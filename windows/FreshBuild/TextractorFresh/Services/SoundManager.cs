using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

/// <summary>
/// Manages UI sound effects for the application.
/// </summary>
public class SoundManager : IDisposable
{
    private bool _disposed = false;

    public SoundManager()
    {
    }

    public void PlayCaptureSound(AppSettings settings)
    {
        if (settings.SoundEffectsEnabled)
        {
            PlaySystemSound("SystemAsterisk");
        }
    }

    public void PlaySuccessSound(AppSettings settings)
    {
        if (settings.SoundEffectsEnabled)
        {
            PlaySystemSound("SystemExclamation");
        }
    }

    public void PlayErrorSound(AppSettings settings)
    {
        if (settings.SoundEffectsEnabled)
        {
            PlaySystemSound("SystemHand");
        }
    }

    public void PlayClickSound(AppSettings settings)
    {
        if (settings.SoundEffectsEnabled)
        {
            PlaySystemSound("SystemQuestion");
        }
    }

    private void PlaySystemSound(string soundName)
    {
        try
        {
            // Use Windows API to play system sounds
            MessageBeep(GetBeepType(soundName));
        }
        catch (Exception ex)
        {
            LoggerService.Error($"Failed to play sound {soundName}", ex);
        }
    }

    private uint GetBeepType(string soundName)
    {
        return soundName switch
        {
            "SystemAsterisk" => 0x00000040, // MB_ICONASTERISK
            "SystemExclamation" => 0x00000030, // MB_ICONEXCLAMATION
            "SystemHand" => 0x00000010, // MB_ICONHAND
            "SystemQuestion" => 0x00000020, // MB_ICONQUESTION
            _ => 0x00000000 // MB_OK
        };
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool MessageBeep(uint uType);

    public void Dispose()
    {
        if (!_disposed)
        {
            _disposed = true;
        }
    }
}