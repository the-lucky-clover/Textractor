using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Tesseract;
using Textractor.Windows.Models;

namespace Textractor.Windows.Services;

public class OCRService : IDisposable
{
    private TesseractEngine? _engine;
    private string _tessdataPath = "";
    private string _currentLanguage = "eng";
    private readonly object _engineLock = new();
    public bool IsReady => _engine != null;
    internal static string[] DataDirectories => new[]
    {
        Path.Combine(AppContext.BaseDirectory, "tessdata"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Textractor", "tessdata"),
        Path.GetFullPath("tessdata")
    };

    public OCRService()
    {
        // Set up native library resolver before initializing Tesseract
        SetupNativeLibraryResolver();
        InitializeEngine();
    }

    private void SetupNativeLibraryResolver()
    {
        try
        {
            var baseDir = AppContext.BaseDirectory;
            
            // Pre-load native libraries using LoadLibrary to ensure they're in memory
            var leptonicaPath = Path.Combine(baseDir, "leptonica-1.82.0.dll");
            var tesseractPath = Path.Combine(baseDir, "tesseract50.dll");
            
            if (File.Exists(leptonicaPath))
            {
                LoadLibrary(leptonicaPath);
            }
            if (File.Exists(tesseractPath))
            {
                LoadLibrary(tesseractPath);
            }

            // Add the base directory to PATH
            var currentPath = Environment.GetEnvironmentVariable("PATH") ?? "";
            if (!currentPath.Split(';').Contains(baseDir))
            {
                Environment.SetEnvironmentVariable("PATH", baseDir + ";" + currentPath);
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to setup native library resolver", ex);
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string lpFileName);

    private void InitializeEngine()
    {
        try
        {
            var baseDir = AppContext.BaseDirectory;
            var possiblePaths = DataDirectories;

            foreach (var path in possiblePaths)
            {
                if (Directory.Exists(path) && File.Exists(Path.Combine(path, _currentLanguage + ".traineddata")))
                {
                    _tessdataPath = path;
                    break;
                }
            }

            if (string.IsNullOrEmpty(_tessdataPath))
            {
                _tessdataPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Textractor",
                    "tessdata");
                LoggerService.Warning($"Tessdata not found. Please place traineddata files in: {_tessdataPath}");
            }

            _engine = new TesseractEngine(_tessdataPath, _currentLanguage, EngineMode.Default);
        }
        catch (Exception ex)
        {
            LoggerService.Error("Failed to initialize Tesseract OCR engine", ex);
        }
    }

    public void SetLanguage(string languageCode)
    {
        if (_currentLanguage == languageCode) return;
        
        _currentLanguage = languageCode;
        _engine?.Dispose();
        _engine = null;
        InitializeEngine();
    }

    public string GetTessdataPath() => _tessdataPath;

    public async Task<OCRResult> RecognizeText(
        Bitmap image,
        double weirdness = 0.45,
        IEnumerable<string>? customVocabulary = null)
    {
        var started = DateTime.Now;
        var normalized = Math.Clamp(weirdness, 0.0, 1.0);

        var revisionsUsed = new List<(string, int)>();
        var observations = new List<TextObservation>();

        if (_engine == null)
        {
            LoggerService.Error("OCR engine not initialized");
            return new OCRResult { RawObservations = observations, RecognizedAtSeconds = 0 };
        }

        try
        {
            // Single pass with auto page segmentation
            var trial1 = await Task.Run(() => RunSync(image));
            observations = trial1;
            revisionsUsed.Add(("auto", 1));
        }
        catch (Exception ex)
        {
            LoggerService.Error("OCR processing failed", ex);
        }

        var result = new OCRResult
        {
            RawObservations = observations,
            RecognizedAtSeconds = (DateTime.Now - started).TotalSeconds,
            LanguageCandidates = new List<string> { _currentLanguage },
            RevisionsUsed = revisionsUsed
        };

        TelemetryService.Shared.Record(new TelemetryEvent
        {
            Kind = result.IsEmpty ? "ocrFailure" : "ocrSuccess",
            Success = !result.IsEmpty,
            LatencyMs = result.RecognizedAtSeconds * 1000,
            Meta = new Dictionary<string, string>
            {
                ["candidates"] = observations.Count.ToString(),
                ["conf"] = result.AverageConfidence.ToString("F2"),
                ["attempts"] = revisionsUsed.Count.ToString()
            }
        });

        return result;
    }

    private List<TextObservation> RunSync(Bitmap image)
    {
        var observations = new List<TextObservation>();

        if (_engine == null) return observations;

        try
        {
            lock (_engineLock)
            {
                // Convert Bitmap to byte array (PNG format)
                using var ms = new MemoryStream();
                image.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                var imageBytes = ms.ToArray();
                
                // Create Pix from bytes
                using var pix = Pix.LoadFromMemory(imageBytes);
                using var page = _engine.Process(pix);
                var text = page.GetText();
                
                // Get confidence
                var confidence = page.GetMeanConfidence();

                // Simple approach: split by lines and create observations
                var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
                var yPos = 0f;
                foreach (var line in lines)
                {
                    if (!string.IsNullOrWhiteSpace(line))
                    {
                        observations.Add(new TextObservation
                        {
                            Text = line.Trim(),
                            Confidence = confidence / 100f,
                            BoundingBox = new RectangleF(0, yPos, 100, 20)
                        });
                        yPos += 20;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            LoggerService.Error("OCR processing failed", ex);
        }

        return observations;
    }

    private float GetThresholdForWeirdness(double weirdness)
    {
        var clamped = Math.Clamp(weirdness, 0.0, 1.0);
        var interval = 0.06 - 0.005;
        return (float)(0.005 + (1.0 - clamped) * interval);
    }

    public void Dispose()
    {
        _engine?.Dispose();
        _engine = null;
    }
}
