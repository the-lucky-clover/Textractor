using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public class HistoryStore
{
    private static readonly string HistoryPath = Path.Combine(
        AppPaths.DataDirectory,
        "history.json");

    private static HistoryStore? _instance;
    private readonly List<HistoryRecord> _records = new();

    private HistoryStore() { Load(); }

    public static HistoryStore Shared => _instance ??= new HistoryStore();

    public void Record(CapturedImage capture, string text, CaptureMode mode, int limit)
    {
        var record = new HistoryRecord
        {
            Id = Guid.NewGuid(),
            Text = text,
            Mode = mode,
            Timestamp = DateTimeOffset.Now,
            CaptureInfo = new CaptureInfo
            {
                Rect = capture.Rect,
                Mode = capture.Mode,
                Origin = capture.Origin
            }
        };

        lock (_records)
        {
            _records.Insert(0, record); // Most recent first
            if (_records.Count > limit)
                _records.RemoveRange(limit, _records.Count - limit);
        }

        Save();
    }

    public List<HistoryRecord> GetRecent(int count)
    {
        lock (_records) return _records.Take(count).ToList();
    }

    public void Clear()
    {
        lock (_records)
        {
            _records.Clear();
        }
        Save();
    }

    private void Load()
    {
        try
        {
            if (File.Exists(HistoryPath))
            {
                var json = File.ReadAllText(HistoryPath);
                var records = JsonSerializer.Deserialize<List<HistoryRecord>>(json);
                if (records != null)
                {
                    lock (_records)
                    {
                        _records.Clear();
                        _records.AddRange(records);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to load history", ex);
        }
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(HistoryPath)!;
            Directory.CreateDirectory(dir);
            string json;
            lock (_records) json = JsonSerializer.Serialize(_records);
            File.WriteAllText(HistoryPath, json);
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to save history", ex);
        }
    }
}

