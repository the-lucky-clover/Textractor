using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

/// <summary>
/// Handles local-only version checking (no remote network calls by default).
/// </summary>
public class UpdateService
{
    private const string CurrentVersion = "2.0.0";
    private readonly HttpClient _httpClient;
    private readonly string _updateUrl = "https://api.github.com/repos/the-lucky-clover/textractor/releases/latest";

    public UpdateService()
    {
        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Textractor/2.0.0");
        _httpClient.Timeout = TimeSpan.FromSeconds(10);
    }

    /// <summary>
    /// Checks for updates. Returns null if no update available or check failed.
    /// </summary>
    public async Task<UpdateInfo?> CheckForUpdatesAsync()
    {
        try
        {
            var response = await _httpClient.GetStringAsync(_updateUrl);
            var json = JsonDocument.Parse(response);
            var tagName = json.RootElement.GetProperty("tag_name").GetString();
            var publishedAt = json.RootElement.GetProperty("published_at").GetDateTime();
            var body = json.RootElement.GetProperty("body").GetString();
            var htmlUrl = json.RootElement.GetProperty("html_url").GetString();

            if (!string.IsNullOrEmpty(tagName) && IsNewerVersion(tagName.TrimStart('v')))
            {
                return new UpdateInfo
                {
                    Version = tagName.TrimStart('v'),
                    ReleaseDate = publishedAt,
                    ReleaseNotes = body ?? "",
                    DownloadUrl = htmlUrl ?? "",
                    IsAvailable = true
                };
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Update check failed", ex);
        }

        return null;
    }

    private bool IsNewerVersion(string remoteVersion)
    {
        if (Version.TryParse(CurrentVersion, out var current) && 
            Version.TryParse(remoteVersion, out var remote))
        {
            return remote > current;
        }
        return false;
    }

    public void Dispose()
    {
        _httpClient?.Dispose();
    }
}

public class UpdateInfo
{
    public string Version { get; set; } = "";
    public DateTime ReleaseDate { get; set; }
    public string ReleaseNotes { get; set; } = "";
    public string DownloadUrl { get; set; } = "";
    public bool IsAvailable { get; set; }
}