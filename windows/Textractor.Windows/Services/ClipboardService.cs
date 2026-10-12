using System;
using System.Runtime.InteropServices;
using System.Text;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public static class ClipboardService
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsClipboardFormatAvailable(uint uFormat);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern UIntPtr GlobalSize(IntPtr hMem);

    private const uint CF_TEXT = 1;
    private const uint CF_UNICODETEXT = 13;
    private const uint CF_RTF = 0xFFFF; // Registered format
    private const uint GMEM_MOVEABLE = 0x0002;
    private const uint GMEM_ZEROINIT = 0x0040;

    /// <summary>
    /// Writes text to the clipboard with optional RTF formatting.
    /// </summary>
    public static bool Copy(string text, string? rtfText = null)
    {
        if (string.IsNullOrEmpty(text)) return false;
        bool copied = false;
        void Write()
        {
            try
            {
                var data = new System.Windows.Forms.DataObject();
                data.SetData(System.Windows.Forms.DataFormats.UnicodeText, text);
                if (!string.IsNullOrEmpty(rtfText))
                    data.SetData(System.Windows.Forms.DataFormats.Rtf, rtfText);
                System.Windows.Forms.Clipboard.SetDataObject(data, true, 5, 50);
                copied = true;
            }
            catch (Exception ex) { LoggerService.Error("Clipboard copy failed", ex); }
        }
        if (System.Threading.Thread.CurrentThread.GetApartmentState() == System.Threading.ApartmentState.STA)
            Write();
        else
        {
            var thread = new System.Threading.Thread(Write);
            thread.SetApartmentState(System.Threading.ApartmentState.STA);
            thread.Start(); thread.Join();
        }
        return copied;
    }
    /// <summary>
    /// Gets plain text from clipboard.
    /// </summary>
    public static string? GetText()
    {
        string? text = null;
        void Read()
        {
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    text = System.Windows.Forms.Clipboard.GetText(System.Windows.Forms.TextDataFormat.UnicodeText);
                    return;
                }
                catch (ExternalException) { System.Threading.Thread.Sleep(50); }
            }
        }
        if (System.Threading.Thread.CurrentThread.GetApartmentState() == System.Threading.ApartmentState.STA)
            Read();
        else
        {
            var thread = new System.Threading.Thread(Read);
            thread.SetApartmentState(System.Threading.ApartmentState.STA);
            thread.Start(); thread.Join();
        }
        return text;
    }
    /// <summary>
    /// Clears the clipboard.
    /// </summary>
    public static void Clear()
    {
        try
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                try
                {
                    EmptyClipboard();
                }
                finally
                {
                    CloseClipboard();
                }
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Clipboard clear failed", ex);
        }
    }

    /// <summary>
    /// Synthesizes Ctrl+V keystroke to paste into the frontmost application.
    /// </summary>
    public static bool AutoPasteIntoFrontmostApp()
    {
        try
        {
            // Small delay to let the foreground app receive focus
            System.Threading.Thread.Sleep(150);

            // Send Ctrl+V using SendInput
            var inputs = new INPUT[2];
            
            // Ctrl down
            inputs[0].type = 1; // INPUT_KEYBOARD
            inputs[0].U.ki.wVk = 0x11; // VK_CONTROL
            inputs[0].U.ki.dwFlags = 0;
            
            // V down
            inputs[1].type = 1;
            inputs[1].U.ki.wVk = 0x56; // 'V'
            inputs[1].U.ki.dwFlags = 0;

            if (SendInput(2, inputs, INPUT.Size) != 2) return false;

            // V up
            inputs[0].type = 1;
            inputs[0].U.ki.wVk = 0x56;
            inputs[0].U.ki.dwFlags = 0x0002; // KEYUP
            
            // Ctrl up
            inputs[1].type = 1;
            inputs[1].U.ki.wVk = 0x11;
            inputs[1].U.ki.dwFlags = 0x0002;

            return SendInput(2, inputs, INPUT.Size) == 2;
        }
        catch (Exception ex)
        {
            LoggerService.Error("Auto-paste failed", ex);
            return false;
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
        public static int Size => Marshal.SizeOf<INPUT>();
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public KEYBDINPUT ki;
        [FieldOffset(0)]
        public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx, dy;
        public uint mouseData, dwFlags, time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
}

