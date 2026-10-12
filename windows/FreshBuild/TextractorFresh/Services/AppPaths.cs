using System;
using System.IO;

namespace Textractor.Windows.Services;

internal static class AppPaths
{
    // Automated playtests use isolated settings/history without touching user data.
    internal static string DataDirectory => Environment.GetEnvironmentVariable("TEXTRACTOR_DATA_DIR")
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Textractor");
}
