using System.Diagnostics;

namespace DragonSword.CameraNoDelay.Setup;

internal sealed class MainForm : Form
{
    private readonly Backend _backend;
    private readonly TextBox _path = new() { Dock = DockStyle.Fill, AccessibleName = "게임 폴더" };
    private readonly Label _status = new() { AutoSize = true, Text = "설치 상태를 확인하고 있습니다.", Font = new Font("맑은 고딕", 15, FontStyle.Bold) };
    private readonly Label _detail = new() { AutoSize = true, MaximumSize = new Size(750, 0), Text = "" };
    private readonly TextBox _result = new() { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.FixedSingle, AccessibleName = "처리 결과" };
    private readonly Button _install = new() { Text = "모드 설치 / 업데이트", AutoSize = true, Padding = new Padding(18, 8, 18, 8) };
    private readonly Button _remove = new() { Text = "모드 삭제", AutoSize = true, Padding = new Padding(18, 8, 18, 8) };
    private readonly Button _browse = new() { Text = "폴더 선택", AutoSize = true };
    private readonly Button _discover = new() { Text = "자동 찾기", AutoSize = true };
    private readonly Button _refresh = new() { Text = "상태 새로고침", AutoSize = true };
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 6000 };
    private bool _busy;
    private bool _operation;
    private bool _closing;
    private string _checkedPath = "";

    internal MainForm(Backend backend, string initialRoot = "")
    {
        _backend = backend;
        Text = "드래곤소드 카메라 모드 설치 · 삭제  v0.2.0";
        Font = new Font("맑은 고딕", 10);
        BackColor = Color.FromArgb(247, 249, 252);
        ForeColor = Color.FromArgb(30, 40, 58);
        ClientSize = new Size(850, 590);
        MinimumSize = new Size(820, 620);
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(28), ColumnCount = 1, RowCount = 8 };
        for (var i = 0; i < 8; i++) layout.RowStyles.Add(new RowStyle(i == 6 ? SizeType.Percent : SizeType.AutoSize, i == 6 ? 100 : 0));
        layout.Controls.Add(new Label { Text = "카메라 회전 딜레이 제거", AutoSize = true, Font = new Font("맑은 고딕", 22, FontStyle.Bold), Margin = new Padding(0, 0, 0, 8) });
        layout.Controls.Add(new Label { Text = "드래곤소드: 어웨이크닝  ·  설치하면 자동 적용  ·  게임에서 F8로 켜기 / 끄기", AutoSize = true, Margin = new Padding(0, 0, 0, 24) });
        layout.Controls.Add(new Label { Text = "게임 폴더 — DSClient.exe가 있는 폴더를 선택하세요.", AutoSize = true, Margin = new Padding(0, 0, 0, 6) });
        var pathRow = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 3, Margin = new Padding(0, 0, 0, 22) };
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        pathRow.Controls.Add(_path, 0, 0); pathRow.Controls.Add(_browse, 1, 0); pathRow.Controls.Add(_discover, 2, 0);
        _path.Margin = new Padding(0, 5, 8, 0); layout.Controls.Add(pathRow);
        var statusCard = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Top, WrapContents = false, BackColor = Color.White, Padding = new Padding(16), Margin = new Padding(0, 0, 0, 18) };
        statusCard.Controls.Add(_status); _detail.Margin = new Padding(3, 10, 3, 2); statusCard.Controls.Add(_detail); layout.Controls.Add(statusCard);
        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 16) };
        _install.BackColor = Color.FromArgb(35, 96, 210); _install.ForeColor = Color.White; _install.FlatStyle = FlatStyle.Flat; _install.FlatAppearance.BorderSize = 0;
        actions.Controls.AddRange([_install, _remove, _refresh]); layout.Controls.Add(actions);
        _result.Text = "게임을 종료한 상태에서 설치 또는 삭제 버튼을 눌러주세요.";
        _result.Margin = new Padding(0, 0, 0, 12); layout.Controls.Add(_result);
        var help = new LinkLabel { Text = "설치 안내 · 최신 배포 파일", AutoSize = true, Margin = new Padding(0) };
        help.LinkClicked += (_, _) => Process.Start(new ProcessStartInfo("https://github.com/pwj891129-arch/DragonSwordCameraNoDelay") { UseShellExecute = true });
        layout.Controls.Add(help); Controls.Add(layout);
        _browse.Click += async (_, _) =>
        {
            using var picker = new FolderBrowserDialog { Description = "DSClient.exe가 있는 드래곤소드 게임 폴더", UseDescriptionForTitle = true, ShowNewFolderButton = false };
            if (Directory.Exists(_path.Text)) picker.InitialDirectory = _path.Text;
            if (picker.ShowDialog(this) == DialogResult.OK) { _path.Text = picker.SelectedPath; await RefreshStatusAsync(); }
        };
        _discover.Click += async (_, _) => await DiscoverAsync();
        _refresh.Click += async (_, _) => await RefreshStatusAsync();
        _install.Click += async (_, _) => await RunOperationAsync("Install");
        _remove.Click += async (_, _) => await RunOperationAsync("Remove");
        _path.TextChanged += (_, _) => { if (_path.Text.Trim() != _checkedPath) { _install.Enabled = false; _remove.Enabled = false; } };
        _path.Leave += async (_, _) => { if (!_busy && _path.Text.Trim() != _checkedPath) await RefreshStatusAsync(); };
        _timer.Tick += async (_, _) => { if (!_busy && !string.IsNullOrWhiteSpace(_path.Text)) await RefreshStatusAsync(); };
        Shown += async (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(initialRoot)) await DiscoverAsync();
            else { _path.Text = initialRoot; await RefreshStatusAsync(); }
            _timer.Start();
        };
        FormClosing += (_, e) => { if (_operation) { e.Cancel = true; _result.Text = "파일 작업을 마칠 때까지 잠시 기다려주세요."; } else { _closing = true; _timer.Stop(); } };
        FormClosed += (_, _) => _timer.Dispose();
    }

    private void SetBusy(bool value)
    {
        _busy = value;
        _browse.Enabled = _discover.Enabled = _refresh.Enabled = _path.Enabled = !value;
        if (value) { _install.Enabled = false; _remove.Enabled = false; }
        UseWaitCursor = value;
    }
    private async Task DiscoverAsync()
    {
        if (_busy) return;
        SetBusy(true);
        try
        {
            var result = await _backend.ExecuteAsync("Discover");
            if (_closing) return;
            if (!result.Ok) throw new InvalidOperationException(result.Message);
            _path.Text = result.GameRoot;
            if (string.IsNullOrWhiteSpace(result.GameRoot)) { _status.Text = "게임 폴더를 선택하세요"; _detail.Text = "자동으로 찾지 못했습니다. ‘폴더 선택’으로 게임 설치 폴더를 지정하세요."; }
        }
        catch (Exception error) { if (!_closing) ShowFailure(error.Message); }
        finally { if (!_closing) SetBusy(false); }
        if (!_closing && !string.IsNullOrWhiteSpace(_path.Text)) await RefreshStatusAsync();
    }
    private async Task RefreshStatusAsync()
    {
        if (_busy || _closing || string.IsNullOrWhiteSpace(_path.Text)) return;
        SetBusy(true);
        try
        {
            var result = await _backend.ExecuteAsync("Status", _path.Text.Trim());
            if (_closing) return;
            _checkedPath = _path.Text.Trim();
            if (!result.Ok) { ShowFailure(result.Message); return; }
            _status.Text = result.State switch { "installed" => $"설치됨  ·  v{result.Version}", "conflict" => "기존 파일 확인 필요", _ => "설치되지 않음" };
            _status.ForeColor = result.State == "conflict" ? Color.FromArgb(160, 70, 20) : Color.FromArgb(30, 65, 110);
            _detail.Text = result.Message;
            _install.Enabled = result.CanInstall; _remove.Enabled = result.CanRemove;
        }
        catch (Exception error) { if (!_closing) ShowFailure(error.Message); }
        finally { if (!_closing) SetBusy(false); }
    }
    private async Task RunOperationAsync(string action)
    {
        if (_busy) return;
        _operation = true; SetBusy(true);
        _result.Text = action == "Install" ? "모드를 설치하고 있습니다…" : "모드를 삭제하고 있습니다…";
        try
        {
            var result = await _backend.ExecuteAsync(action, _path.Text.Trim());
            _result.Text = result.Message;
            if (!string.IsNullOrEmpty(result.BackupPath)) _result.AppendText(Environment.NewLine + Environment.NewLine + "파일 보관 위치: " + result.BackupPath);
            if (!result.Ok) _result.AppendText(Environment.NewLine + "문제를 해결한 뒤 다시 시도하세요.");
        }
        catch (Exception error) { _result.Text = error.Message; }
        finally { _operation = false; SetBusy(false); }
        await RefreshStatusAsync();
    }
    private void ShowFailure(string message)
    {
        _status.Text = "설치 상태를 확인할 수 없습니다";
        _status.ForeColor = Color.FromArgb(160, 70, 20); _detail.Text = message;
        _install.Enabled = _remove.Enabled = false;
    }

    internal async Task RunUiTestAsync(string fixtureRoot, string imageFolder)
    {
        var fixtureFile = Path.Combine(fixtureRoot, "DS", "Binaries", "Win64", "DSClient-Win64-Shipping.exe");
        if (!File.Exists(fixtureFile) || new FileInfo(fixtureFile).Length > 100 || File.ReadAllText(fixtureFile).Trim() != "UI test fixture")
            throw new InvalidOperationException("UI tests require a disposable UI test fixture.");
        async Task WaitFor(Func<bool> predicate)
        {
            var deadline = DateTime.UtcNow.AddSeconds(40);
            while (!predicate())
            {
                if (DateTime.UtcNow >= deadline) throw new InvalidOperationException("UI test timed out: " + _detail.Text + " " + _result.Text);
                await Task.Delay(100);
            }
        }
        void Render(string name)
        {
            Directory.CreateDirectory(imageFolder);
            using var bitmap = new Bitmap(Width, Height);
            DrawToBitmap(bitmap, new Rectangle(0, 0, Width, Height));
            bitmap.Save(Path.Combine(imageFolder, name), System.Drawing.Imaging.ImageFormat.Png);
        }
        await WaitFor(() => !_busy && _checkedPath == fixtureRoot);
        if (!_install.Enabled || _remove.Enabled) throw new InvalidOperationException("Initial install/remove button states are wrong.");
        _install.PerformClick();
        await WaitFor(() => !_busy && !_operation && _status.Text.StartsWith("설치됨", StringComparison.Ordinal));
        if (!_remove.Enabled) throw new InvalidOperationException("Remove button did not enable after installation.");
        Render("installed.png");
        _remove.PerformClick();
        await WaitFor(() => !_busy && !_operation && _status.Text == "설치되지 않음");
        if (_remove.Enabled || !_install.Enabled) throw new InvalidOperationException("Button states are wrong after removal.");
        Render("removed.png");
    }
}
