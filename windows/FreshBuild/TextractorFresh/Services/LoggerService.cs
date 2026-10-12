using System;
using System.IO;

namespace Textractor.Windows.Services;

public static class LoggerService
{
    private static readonly string LogPath = Path.Combine(
        AppPaths.DataDirectory,
        "logs",
        $"textractor_{DateTime.Now:yyyyMMdd}.log");

    static LoggerService()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
    }

    public static void Log(string message)
    {
        var entry = $"[{DateTime.Now:HH:mm:ss.fff}] {message}";
        Console.WriteLine(entry);
        File.AppendAllText(LogPath, entry + Environment.NewLine);
    }

    public static void Info(string message) => Log($"INFO: {message}");
    public static void Warning(string message) => Log($"WARN: {message}");
    public static void Error(string message, Exception? ex = null)
    {
        var msg = ex != null ? $"{message}: {ex}" : message;
        Log($"ERROR: {msg}");
    }
}
