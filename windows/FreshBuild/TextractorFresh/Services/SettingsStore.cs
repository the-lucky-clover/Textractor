using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace Textractor.Windows.Services;

public class SettingsStore
{
    private static readonly string SettingsPath = Path.Combine(
        AppPaths.DataDirectory,
        "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private static SettingsStore? _instance;

    public Models.AppSettings Settings { get; set; } = Models.AppSettings.Default;

    private SettingsStore() { }

    public static SettingsStore Shared
    {
        get
        {
            if (_instance == null)
            {
                _instance = new SettingsStore();
                _instance.Load();
            }
            return _instance;
        }
    }

    public void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(SettingsPath)!;
            Directory.CreateDirectory(dir);
            var json = JsonSerializer.Serialize(Settings, JsonOptions);
            File.WriteAllText(SettingsPath, json);
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to save settings", ex);
        }
    }

    public void Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                Settings = JsonSerializer.Deserialize<Models.AppSettings>(json, JsonOptions) ?? Models.AppSettings.Default;
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to load settings", ex);
            Settings = Models.AppSettings.Default;
        }
    }
}
