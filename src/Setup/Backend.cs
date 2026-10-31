using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace DragonSword.CameraNoDelay.Setup;

internal sealed class BackendResult
{
    public bool Ok { get; set; }
    public string GameRoot { get; set; } = "";
    public string State { get; set; } = "";
    public string Version { get; set; } = "";
    public bool Running { get; set; }
    public bool CanInstall { get; set; }
    public bool CanRemove { get; set; }
    public string Message { get; set; } = "";
    public string BackupPath { get; set; } = "";
}

internal sealed class Backend : IDisposable
{
    private readonly string _root;
    internal static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    internal Backend()
    {
        _root = Path.Combine(Path.GetTempPath(), "DragonSwordCameraNoDelay", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("CameraNoDelay.Payload.zip")
            ?? throw new InvalidOperationException("설치 자료를 찾지 못했습니다. 배포 파일을 다시 받으세요.");
        using var archive = new ZipArchive(resource, ZipArchiveMode.Read);
        archive.ExtractToDirectory(_root);
    }

    internal async Task<BackendResult> ExecuteAsync(string action, string gameRoot = "")
    {
        if (action is not ("Discover" or "Status" or "Install" or "Remove")) throw new ArgumentOutOfRangeException(nameof(action));
        var start = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"),
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = _root
        };
        // Do not inherit PowerShell 7's module path when launching Windows PowerShell 5.1.
        start.Environment["PSModulePath"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules");
        var bootstrap = Path.Combine(_root, "Invoke-Backend.ps1");
        if (!File.Exists(bootstrap))
            File.WriteAllText(bootstrap, "param([string]$Action, [string]$GameRoot)\n[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)\n& (Join-Path $PSScriptRoot 'Manage-Mod.ps1') -Action $Action -GameRoot $GameRoot -AsJson\n", new UTF8Encoding(true));
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", bootstrap, "-Action", action }) start.ArgumentList.Add(arg);
        if (!string.IsNullOrWhiteSpace(gameRoot)) { start.ArgumentList.Add("-GameRoot"); start.ArgumentList.Add(gameRoot); }
        using var process = Process.Start(start) ?? throw new InvalidOperationException("설치 도구를 실행하지 못했습니다.");
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = (await outputTask).Trim().TrimStart('\uFEFF');
        var error = (await errorTask).Trim();
        try
        {
            return JsonSerializer.Deserialize<BackendResult>(output, JsonOptions)
                ?? throw new JsonException("Empty result");
        }
        catch (JsonException)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "작업 결과를 읽지 못했습니다. 배포 파일을 다시 실행하세요." : error);
        }
    }

    public void Dispose()
    {
        var prefix = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "DragonSwordCameraNoDelay")) + Path.DirectorySeparatorChar;
        if (Path.GetFullPath(_root).StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            try { Directory.Delete(_root, recursive: true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
