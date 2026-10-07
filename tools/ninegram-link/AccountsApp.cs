using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--export-link-key")
        {
            LoginEncryption.ExportPublicKey(args[1]);
            return;
        }
        using (var mutex = new Mutex(true, "Local\\NinegramAccounts", out var created))
        {
            if (!created) { return; }
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new AccountsForm());
        }
    }
}

internal sealed class AccountsForm : Form
{
    private readonly string _root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ninegram-link", "ayugram");
    private readonly WebView2 _web = new WebView2();
    private readonly System.Windows.Forms.Timer _timer = new System.Windows.Forms.Timer();
    private string _statusText = "Подключаюсь к серверу…";
    private bool _ready;

    public AccountsForm()
    {
        Text = "Ninegram";
        BackColor = Color.FromArgb(5, 7, 12);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(460, 720);
        MinimumSize = new Size(400, 520);
        Font = new Font("Segoe UI", 10f);

        _web.Dock = DockStyle.Fill;
        _web.DefaultBackgroundColor = Color.FromArgb(5, 7, 12);
        _web.CreationProperties = new CoreWebView2CreationProperties
        {
            UserDataFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ninegram-link", "webview")
        };
        _web.CoreWebView2InitializationCompleted += WebReady;
        Controls.Add(_web);

        _timer.Interval = 3000;
        _timer.Tick += delegate { Push(); };
        Load += async delegate
        {
            _timer.Start();
            var worker = new Thread(() => DesktopLogin.Run(SetStatus)) { IsBackground = true };
            worker.Start();
            try
            {
                Log("ensure start");
                await _web.EnsureCoreWebView2Async();
                Log("ensure done");
            }
            catch (Exception error)
            {
                Log(error.ToString());
                ShowFailure(error.Message);
            }
        };
    }

    private static void Log(string text)
    {
        try
        {
            var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ninegram-link", "ui.log");
            File.AppendAllText(path, DateTime.Now.ToString("HH:mm:ss.fff ") + text + Environment.NewLine);
        }
        catch
        {
        }
    }

    private void ShowFailure(string message)
    {
        var label = new Label
        {
            Dock = DockStyle.Fill,
            ForeColor = Color.White,
            BackColor = Color.FromArgb(20, 24, 32),
            TextAlign = ContentAlignment.MiddleCenter,
            Padding = new Padding(24),
            Text = message
        };
        Controls.Add(label);
        label.BringToFront();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        try
        {
            int dark = 1;
            DwmSetWindowAttribute(Handle, 20, ref dark, sizeof(int));
            int round = 2;
            DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int));
        }
        catch
        {
        }
    }

    private void WebReady(object sender, CoreWebView2InitializationCompletedEventArgs args)
    {
        if (!args.IsSuccess)
        {
            var message = args.InitializationException == null ? "неизвестная ошибка" : args.InitializationException.ToString();
            Log("init failed " + message);
            ShowFailure(message);
            return;
        }
        Log("init ok");
        var core = _web.CoreWebView2;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.WebMessageReceived += OnWebMessage;
        core.NavigationCompleted += delegate
        {
            _ready = true;
            Push();
        };
        var htmlPath = Path.Combine(AppContext.BaseDirectory, "glass.html");
        core.NavigateToString(File.ReadAllText(htmlPath));
    }

    private void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        Dictionary<string, object> message;
        try
        {
            message = JsonMap.Read(args.WebMessageAsJson);
        }
        catch
        {
            return;
        }
        object commandValue;
        if (!message.TryGetValue("cmd", out commandValue) || commandValue == null)
        {
            return;
        }
        var path = Value(message, "path");
        var command = commandValue.ToString();
        if (command == "open")
        {
            OpenAccount(path);
        }
        else if (command == "delete")
        {
            DeleteAccount(path);
        }
        else if (command == "rename")
        {
            SaveTitle(path, Value(message, "title"));
        }
    }

    private static string Value(Dictionary<string, object> message, string key)
    {
        object stored;
        if (!message.TryGetValue(key, out stored) || stored == null)
        {
            return "";
        }
        return stored.ToString();
    }

    private void SetStatus(string text)
    {
        if (IsDisposed)
        {
            return;
        }
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(SetStatus), text);
            return;
        }
        _statusText = text;
        Push();
    }

    private void Push()
    {
        if (!_ready || IsDisposed || _web.CoreWebView2 == null)
        {
            return;
        }
        var running = RunningWorkdirs();
        var rows = new List<Dictionary<string, object>>();
        foreach (var account in LoadAccounts())
        {
            rows.Add(new Dictionary<string, object>
            {
                { "path", account.Path },
                { "id", Path.GetFileName(account.Path) },
                { "title", account.Title },
                { "running", running.Contains(account.Path) }
            });
        }
        var payload = JsonMap.Write(new Dictionary<string, object>
        {
            { "type", "state" },
            { "status", _statusText },
            { "accounts", rows }
        });
        _web.CoreWebView2.PostWebMessageAsJson(payload);
    }

    private List<AccountInfo> LoadAccounts()
    {
        var result = new List<AccountInfo>();
        if (!Directory.Exists(_root))
        {
            return result;
        }
        foreach (var dir in Directory.GetDirectories(_root))
        {
            var name = Path.GetFileName(dir);
            if (name == null || !name.StartsWith("account-", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (!DesktopLogin.IsLoggedIn(dir))
            {
                continue;
            }
            var title = name;
            var metaPath = Path.Combine(dir, "account.json");
            if (File.Exists(metaPath))
            {
                try
                {
                    var meta = JsonMap.Read(File.ReadAllText(metaPath));
                    object stored;
                    if (meta.TryGetValue("title", out stored) && stored != null)
                    {
                        var text = stored.ToString();
                        if (!string.IsNullOrWhiteSpace(text))
                        {
                            title = text;
                        }
                    }
                }
                catch
                {
                }
            }
            result.Add(new AccountInfo { Path = dir, Title = title });
        }
        result.Sort((a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
        return result;
    }

    private static HashSet<string> RunningWorkdirs()
    {
        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using (var searcher = new ManagementObjectSearcher("SELECT Name, CommandLine FROM Win32_Process WHERE Name LIKE 'AyuGram%'"))
            using (var results = searcher.Get())
            {
                foreach (ManagementObject process in results)
                {
                    var line = process["CommandLine"] as string;
                    if (string.IsNullOrEmpty(line))
                    {
                        continue;
                    }
                    var marker = "-workdir";
                    var index = line.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
                    if (index < 0)
                    {
                        continue;
                    }
                    var workdir = line.Substring(index + marker.Length).Trim().Trim('"');
                    if (workdir.Length > 0)
                    {
                        found.Add(workdir);
                    }
                }
            }
        }
        catch
        {
        }
        return found;
    }

    private void OpenAccount(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
        {
            return;
        }
        var pid = FindPid(path);
        if (pid != 0)
        {
            var hwnd = FindWindow(pid);
            if (hwnd != IntPtr.Zero)
            {
                ShowWindow(hwnd, 9);
                SetForegroundWindow(hwnd);
                return;
            }
        }
        try
        {
            DesktopLogin.StartAyu(path);
        }
        catch (Exception error)
        {
            SetStatus("Ошибка: " + error.Message);
        }
    }

    private void DeleteAccount(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
        {
            Push();
            return;
        }
        var pid = FindPid(path);
        if (pid != 0)
        {
            try
            {
                var process = Process.GetProcessById(pid);
                process.Kill();
                process.WaitForExit(3000);
            }
            catch
            {
            }
        }
        try
        {
            DeleteFolder(path);
        }
        catch (Exception error)
        {
            SetStatus("Ошибка: не удалось удалить папку. " + error.Message);
            return;
        }
        Push();
    }

    private static void DeleteFolder(string path)
    {
        for (var attempt = 0; attempt < 8; attempt++)
        {
            ClearReadOnly(path);
            try
            {
                if (Directory.Exists(path))
                {
                    Directory.Delete(path, true);
                }
                return;
            }
            catch (IOException)
            {
                Thread.Sleep(300);
            }
            catch (UnauthorizedAccessException)
            {
                Thread.Sleep(300);
            }
        }
        throw new IOException("файл ещё занят. Закрой окно AyuGram этого аккаунта и удали ещё раз.");
    }

    private static void ClearReadOnly(string path)
    {
        if (!Directory.Exists(path))
        {
            return;
        }
        foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
        {
            var info = new FileInfo(file);
            if (info.IsReadOnly)
            {
                info.IsReadOnly = false;
            }
        }
    }

    private static void SaveTitle(string path, string title)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
        {
            return;
        }
        var metaPath = Path.Combine(path, "account.json");
        var text = string.IsNullOrWhiteSpace(title) ? Path.GetFileName(path) : title.Trim();
        File.WriteAllText(metaPath, JsonMap.Write(new Dictionary<string, string>
        {
            { "title", text }
        }));
    }

    private static int FindPid(string path)
    {
        try
        {
            using (var searcher = new ManagementObjectSearcher("SELECT ProcessId, Name, CommandLine FROM Win32_Process WHERE Name LIKE 'AyuGram%'"))
            using (var results = searcher.Get())
            {
                foreach (ManagementObject process in results)
                {
                    var line = process["CommandLine"] as string;
                    if (line != null && line.IndexOf(path, StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        return Convert.ToInt32(process["ProcessId"]);
                    }
                }
            }
        }
        catch
        {
        }
        return 0;
    }

    private static IntPtr FindWindow(int pid)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hwnd, IntPtr lparam)
        {
            int windowPid;
            GetWindowThreadProcessId(hwnd, out windowPid);
            if (windowPid == pid && IsWindowVisible(hwnd))
            {
                found = hwnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lparam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lparam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}

internal sealed class AccountInfo
{
    public string Path;
    public string Title;
}
