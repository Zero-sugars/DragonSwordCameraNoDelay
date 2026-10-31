using System.Text.Json;
using System.Runtime.InteropServices;

namespace DragonSword.CameraNoDelay.Setup;

internal static class Program
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            using var backend = new Backend();
            if (args.Length > 0 && args[0] == "--action")
            {
                if (args.Length < 2) return 2;
                var root = "";
                for (var i = 2; i + 1 < args.Length; i++) if (args[i] == "--game-root") root = args[++i];
                var result = backend.ExecuteAsync(args[1], root).GetAwaiter().GetResult();
                Console.OutputEncoding = new System.Text.UTF8Encoding(false);
                Console.WriteLine(JsonSerializer.Serialize(result));
                return result.Ok ? 0 : 1;
            }
            ApplicationConfiguration.Initialize();
            SetCurrentProcessExplicitAppUserModelID("DragonSword.CameraNoDelay.Setup");
            using var mutex = new Mutex(true, "Local\\DragonSwordCameraNoDelaySetup", out var created);
            if (!created) { MessageBox.Show("설치 프로그램이 이미 실행 중입니다.", "드래곤소드 카메라 모드"); return 0; }
            var initialRoot = "";
            for (var i = 0; i + 1 < args.Length; i++) if (args[i] == "--game-root") initialRoot = args[++i];
            using var form = new MainForm(backend, initialRoot);
            var uiExitCode = 0;
            if (args.Contains("--ui-test"))
            {
                var imageFolder = Path.Combine(AppContext.BaseDirectory, "ui-test-output");
                for (var i = 0; i + 1 < args.Length; i++) if (args[i] == "--image-folder") imageFolder = args[++i];
                form.Shown += async (_, _) =>
                {
                    try { await form.RunUiTestAsync(initialRoot, imageFolder); Console.WriteLine("UI: install/remove buttons, state updates and render PASS"); }
                    catch (Exception error) { uiExitCode = 1; Console.Error.WriteLine(error.Message); }
                    finally { form.Close(); }
                };
            }
            Application.Run(form);
            return uiExitCode;
        }
        catch (Exception error)
        {
            if (args.Length > 0) { Console.Error.WriteLine(error.Message); return 1; }
            MessageBox.Show(error.Message, "드래곤소드 카메라 모드", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
