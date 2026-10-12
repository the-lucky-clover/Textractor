using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public class TelemetryService
{
    private static readonly string TelemetryPath = Path.Combine(
        AppPaths.DataDirectory,
        "telemetry.jsonl");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false
    };

    private static TelemetryService? _instance;

    public bool IsEnabled { get; set; } = true;

    public static TelemetryService Shared => _instance ??= new TelemetryService();

    private TelemetryService() { }

    public void Record(TelemetryEvent telemetryEvent)
    {
        if (!IsEnabled) return;

        try
        {
            var dir = Path.GetDirectoryName(TelemetryPath)!;
            Directory.CreateDirectory(dir);
            var json = JsonSerializer.Serialize(telemetryEvent, JsonOptions);
            File.AppendAllText(TelemetryPath, json + Environment.NewLine);
        }
        catch
        {
            // Fail silently for telemetry
        }
    }

    public List<TelemetryEvent> ReadAll()
    {
        if (!File.Exists(TelemetryPath)) return new();

        try
        {
            var lines = File.ReadAllLines(TelemetryPath);
            var events = new List<TelemetryEvent>();
            foreach (var line in lines)
            {
                if (!string.IsNullOrWhiteSpace(line))
                {
                    var ev = JsonSerializer.Deserialize<TelemetryEvent>(line, JsonOptions);
                    if (ev != null) events.Add(ev);
                }
            }
            return events;
        }
        catch
        {
            return new();
        }
    }
}
