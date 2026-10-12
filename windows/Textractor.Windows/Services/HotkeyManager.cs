using System;
using System.Runtime.InteropServices;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

/// <summary>
/// Manages global hotkey registration for the application.
/// </summary>
public static class HotkeyManager
{
    private static IntPtr _windowHandle = IntPtr.Zero;
    private static int _hotkeyId = 1;
    private static Action? _hotkeyCallback;

    // Windows API constants
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_WIN = 0x0008;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    /// <summary>
    /// Initializes the hotkey manager with the main window handle.
    /// </summary>
    public static void Initialize(IntPtr windowHandle, Action onHotkeyPressed)
    {
        _windowHandle = windowHandle;
        _hotkeyCallback = onHotkeyPressed;
    }

    /// <summary>
    /// Registers the global hotkey based on settings.
    /// </summary>
    public static bool RegisterHotkey(AppSettings settings)
    {
        if (_windowHandle == IntPtr.Zero)
        {
            LoggerService.Warning("Cannot register hotkey: window handle not set");
            return false;
        }

        // Unregister existing hotkey first
        UnregisterHotKey(_windowHandle, _hotkeyId);

        // Parse modifiers and key code from settings
        uint modifiers = settings.RegionCaptureModifiers;
        uint keyCode = settings.RegionCaptureKeyCode;

        // Default to Alt+Shift+2 if not configured
        if (modifiers == 0 && keyCode == 0)
        {
            modifiers = MOD_ALT | MOD_SHIFT;
            keyCode = 0x32; // '2' key
        }

        var success = RegisterHotKey(_windowHandle, _hotkeyId, modifiers, keyCode);
        
        if (success)
        {
            LoggerService.Log($"Global hotkey registered: Modifiers={modifiers}, Key={keyCode}");
        }
        else
        {
            var error = Marshal.GetLastWin32Error();
            LoggerService.Error($"Failed to register hotkey. Error: {error}");
        }

        return success;
    }

    /// <summary>
    /// Unregisters the global hotkey.
    /// </summary>
    public static void UnregisterHotkey()
    {
        if (_windowHandle != IntPtr.Zero)
        {
            UnregisterHotKey(_windowHandle, _hotkeyId);
            LoggerService.Log("Global hotkey unregistered");
        }
    }

    /// <summary>
    /// Processes window messages to handle hotkey events.
    /// Should be called from the window's WndProc hook.
    /// </summary>
    public static bool ProcessHotkeyMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == _hotkeyId)
        {
            _hotkeyCallback?.Invoke();
            handled = true;
            return true;
        }
        return false;
    }

    /// <summary>
    /// Starts the hotkey listener (alias for RegisterHotkey with current settings).
    /// </summary>
    public static void Start()
    {
        var settings = SettingsStore.Shared.Settings;
        RegisterHotkey(settings);
    }

    /// <summary>
    /// Stops the hotkey listener.
    /// </summary>
    public static void Stop()
    {
        UnregisterHotkey();
    }
}