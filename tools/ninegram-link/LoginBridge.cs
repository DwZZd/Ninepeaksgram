using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using ZXing.Windows.Compatibility;

internal static class DesktopLogin
{
    private static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ninegram-link");
    private static readonly string Profiles = Path.Combine(Root, "ayugram");
    private static readonly string Exe = @"D:\Home\Desktop\ayu\AyuGram-ninegram.exe";
    private static readonly IntPtr TopMost = new IntPtr(-1);
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpShow = 0x0040;

    public static void Run(Action<string> status)
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        Dictionary<string, object> config;
        try
        {
            config = LoadConfig();
        }
        catch (Exception error)
        {
            status("Вход с телефона выключен: " + error.Message);
            return;
        }
        status("Жду вход с телефона");
        while (true)
        {
            try
            {
                if (!PhoneWants(config))
                {
                    Thread.Sleep(2000);
                    continue;
                }
                var profile = NextProfile();
                status("Открываю AyuGram");
                int pid;
                IntPtr hwnd;
                Launch(profile, out pid, out hwnd);
                if (WaitForLogin(config, pid, hwnd, profile, status))
                {
                    status("Аккаунт сохранён. Жду следующий вход");
                    Thread.Sleep(2000);
                }
                status("Жду вход с телефона");
                Thread.Sleep(5000);
            }
            catch (Exception error)
            {
                status("Ошибка входа: " + error.Message);
                Thread.Sleep(5000);
                status("Жду вход с телефона");
            }
        }
    }

    private static Dictionary<string, object> LoadConfig()
    {
        var config = JsonMap.Read(File.ReadAllText(Path.Combine(Root, "config.json")));
        if (config == null || !config.ContainsKey("write_secret") || !config.ContainsKey("base_url"))
        {
            throw new InvalidOperationException("в config.json нет адреса сервера");
        }
        return config;
    }

    private static string Post(Dictionary<string, object> config, string path, string json, out int status)
    {
        var request = (HttpWebRequest)WebRequest.Create(config["base_url"].ToString().TrimEnd('/') + path);
        request.Method = "POST";
        request.Timeout = 15000;
        request.ContentType = "application/json";
        request.Headers["X-Ninegram-Key"] = config["write_secret"].ToString();
        var bytes = Encoding.UTF8.GetBytes(json);
        request.ContentLength = bytes.Length;
        using (var stream = request.GetRequestStream())
        {
            stream.Write(bytes, 0, bytes.Length);
        }
        try
        {
            using (var response = (HttpWebResponse)request.GetResponse())
            {
                status = (int)response.StatusCode;
                using (var reader = new StreamReader(response.GetResponseStream()))
                {
                    return reader.ReadToEnd();
                }
            }
        }
        catch (WebException error)
        {
            var http = error.Response as HttpWebResponse;
            if (http != null)
            {
                status = (int)http.StatusCode;
                using (var reader = new StreamReader(http.GetResponseStream()))
                {
                    return reader.ReadToEnd();
                }
            }
            throw;
        }
    }

    private static bool PhoneWants(Dictionary<string, object> config)
    {
        int status;
        var body = Post(config, "/v1/want", "{}", out status);
        var payload = JsonMap.Read(body);
        return payload.ContainsKey("wanted") && payload["wanted"] is bool && (bool)payload["wanted"];
    }

    private static string TakePassword(Dictionary<string, object> config)
    {
        int status;
        var body = Post(config, "/v1/password/take", "{}", out status);
        if (status == 204 || string.IsNullOrWhiteSpace(body))
        {
            return null;
        }
        var payload = JsonMap.Read(body);
        object password;
        if (payload != null && payload.TryGetValue("password", out password) && password != null)
        {
            var text = password.ToString();
            return string.IsNullOrEmpty(text) ? null : LoginEncryption.Decrypt(text);
        }
        return null;
    }

    private static string NextProfile()
    {
        Directory.CreateDirectory(Profiles);
        var max = 0;
        foreach (var dir in Directory.GetDirectories(Profiles))
        {
            var name = Path.GetFileName(dir) ?? "";
            var digits = "";
            foreach (var ch in name)
            {
                if (char.IsDigit(ch))
                {
                    digits += ch;
                }
            }
            int number;
            if (int.TryParse(digits, out number) && number > max)
            {
                max = number;
            }
        }
        return Path.Combine(Profiles, "account-" + (max + 1).ToString("000"));
    }

    private const int SocksPort = 11080;

    internal static Process StartAyu(string profile)
    {
        EnsureTunnel();
        Directory.CreateDirectory(profile);
        return StartProxied(Exe, "-many -workdir \"" + profile + "\"", Path.GetDirectoryName(Exe));
    }

    private static void EnsureTunnel()
    {
        if (TunnelUp("127.0.0.1") && TunnelUp("::1"))
        {
            return;
        }
        if (!TunnelUp("127.0.0.1"))
        {
            StartTunnel("127.0.0.1");
        }
        if (!TunnelUp("::1"))
        {
            StartTunnel("::1");
        }
        var deadline = DateTime.UtcNow.AddSeconds(12);
        while (DateTime.UtcNow < deadline)
        {
            if (TunnelUp("127.0.0.1") && TunnelUp("::1"))
            {
                return;
            }
            Thread.Sleep(200);
        }
        throw new InvalidOperationException("нет туннеля до VPS, сессия не будет с домашним IP");
    }

    private static void StartTunnel(string bind)
    {
        var ssh = Path.Combine(Environment.SystemDirectory, "OpenSSH", "ssh.exe");
        var address = bind.Contains(":") ? "[" + bind + "]" : bind;
        var started = Process.Start(new ProcessStartInfo
        {
            FileName = ssh,
            Arguments = "-D " + address + ":" + SocksPort + " -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o BatchMode=yes vps",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        });
        if (started == null)
        {
            throw new InvalidOperationException("не удалось открыть туннель до VPS");
        }
    }

    private static bool TunnelUp(string host)
    {
        try
        {
            using (var client = new System.Net.Sockets.TcpClient(host.Contains(":") ? System.Net.Sockets.AddressFamily.InterNetworkV6 : System.Net.Sockets.AddressFamily.InterNetwork))
            {
                var task = client.ConnectAsync(host, SocksPort);
                return task.Wait(300) && client.Connected;
            }
        }
        catch
        {
            return false;
        }
    }

    private static Process StartProxied(string exe, string arguments, string workingDirectory)
    {
        var dll = Path.Combine(AppContext.BaseDirectory, "ninegram-socks.dll");
        if (!File.Exists(dll) || !File.Exists(exe))
        {
            throw new InvalidOperationException("нет ninegram-socks.dll рядом с приложением");
        }
        var command = new System.Text.StringBuilder();
        command.Append('"').Append(exe).Append("\" ").Append(arguments);
        Environment.SetEnvironmentVariable("NINEGRAM_SOCKS", "1");
        var startup = new STARTUPINFO();
        startup.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        PROCESS_INFORMATION info;
        if (!CreateProcess(exe, command, IntPtr.Zero, IntPtr.Zero, false, 0x00000004, IntPtr.Zero, workingDirectory, ref startup, out info))
        {
            throw new InvalidOperationException("не удалось запустить AyuGram");
        }
        try
        {
            if (!InjectDll(info.hProcess, dll))
            {
                TerminateProcess(info.hProcess, 1);
                throw new InvalidOperationException("не удалось пустить AyuGram через VPS");
            }
            ResumeThread(info.hThread);
        }
        finally
        {
            CloseHandle(info.hThread);
            CloseHandle(info.hProcess);
        }
        return Process.GetProcessById((int)info.dwProcessId);
    }

    private static bool InjectDll(IntPtr process, string dll)
    {
        var kernel = GetModuleHandle("kernel32.dll");
        var loadLibrary = GetProcAddress(kernel, "LoadLibraryW");
        var bytes = (dll.Length + 1) * 2;
        var remote = VirtualAllocEx(process, IntPtr.Zero, (UIntPtr)bytes, 0x3000, 0x04);
        if (remote == IntPtr.Zero || loadLibrary == IntPtr.Zero)
        {
            return false;
        }
        var data = System.Text.Encoding.Unicode.GetBytes(dll + "\0");
        int written;
        if (!WriteProcessMemory(process, remote, data, data.Length, out written))
        {
            return false;
        }
        var thread = CreateRemoteThread(process, IntPtr.Zero, UIntPtr.Zero, loadLibrary, remote, 0, IntPtr.Zero);
        if (thread == IntPtr.Zero)
        {
            return false;
        }
        WaitForSingleObject(thread, 8000);
        uint code;
        var ok = GetExitCodeThread(thread, out code) && code != 0;
        CloseHandle(thread);
        return ok;
    }

    private static void Launch(string profile, out int pid, out IntPtr hwnd)
    {
        var process = StartAyu(profile);
        var deadline = DateTime.UtcNow.AddSeconds(30);
        hwnd = IntPtr.Zero;
        pid = process.Id;
        while (DateTime.UtcNow < deadline)
        {
            hwnd = FindWindow(pid);
            if (hwnd != IntPtr.Zero)
            {
                break;
            }
            if (process.HasExited)
            {
                throw new InvalidOperationException("AyuGram закрылся до появления окна");
            }
            Thread.Sleep(400);
        }
        if (hwnd == IntPtr.Zero)
        {
            try
            {
                process.Kill();
            }
            catch
            {
            }
            throw new InvalidOperationException("окно AyuGram не появилось");
        }
        ShowWindow(hwnd, 5);
        SetWindowPos(hwnd, TopMost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpShow);
    }

    private static bool WaitForLogin(Dictionary<string, object> config, int pid, IntPtr hwnd, string profile, Action<string> status)
    {
        string published = null;
        var publishedAt = DateTime.MinValue;
        var started = DateTime.UtcNow;
        string pendingPassword = null;
        DateTime? passwordAt = null;
        var passwordRetried = false;
        var qrMissing = 0;
        while (PidAlive(pid))
        {
            if (IsLoggedIn(profile))
            {
                ReportResult(config, published, true);
                try
                {
                    int ignored;
                    Post(config, "/v1/clear", "{\"token\":\"\"}", out ignored);
                }
                catch
                {
                }
                return true;
            }
            if (HasRpcFailure(profile))
            {
                ReportResult(config, published, false);
                AbortLogin(config, pid, profile, status, "AyuGram отверг вход. Закрываю окно и жду следующий");
                return false;
            }
            if (DateTime.UtcNow - started > TimeSpan.FromMinutes(3))
            {
                ReportResult(config, published, false);
                AbortLogin(config, pid, profile, status, "Вход не завершился. Закрываю окно и жду следующий");
                return false;
            }
            var token = ReadToken(hwnd);
            if (token != null)
            {
                qrMissing = 0;
                if (token != published || DateTime.UtcNow - publishedAt > TimeSpan.FromSeconds(10))
                {
                    int ignored;
                    Post(config, "/v1/token", "{\"token\":\"" + token + "\"}", out ignored);
                    if (token != published)
                    {
                        status("Жду подтверждение с телефона");
                    }
                    published = token;
                    publishedAt = DateTime.UtcNow;
                }
            }
            else
            {
                qrMissing++;
                if (IsLoggedIn(profile))
                {
                    ReportResult(config, published, true);
                    try
                    {
                        int ignored;
                        Post(config, "/v1/clear", "{\"token\":\"\"}", out ignored);
                    }
                    catch
                    {
                    }
                    return true;
                }
                if (passwordAt.HasValue && DateTime.UtcNow - passwordAt.Value > TimeSpan.FromSeconds(50))
                {
                    ReportResult(config, published, false);
                    AbortLogin(config, pid, profile, status, "Пароль не прошёл. Закрываю окно и жду следующий");
                    return false;
                }
                if (qrMissing >= 2 && pendingPassword == null && published != null)
                {
                    pendingPassword = TakePassword(config);
                    if (!string.IsNullOrEmpty(pendingPassword))
                    {
                        TypePassword(hwnd, pendingPassword);
                        passwordAt = DateTime.UtcNow;
                        status("Ввожу облачный пароль");
                    }
                }
                else if (!passwordRetried && pendingPassword != null && passwordAt.HasValue && DateTime.UtcNow - passwordAt.Value > TimeSpan.FromSeconds(8) && !IsLoggedIn(profile))
                {
                    passwordRetried = true;
                    TypePassword(hwnd, pendingPassword);
                    status("Повторяю облачный пароль");
                }
                else if (published != null && DateTime.UtcNow - publishedAt > TimeSpan.FromSeconds(10))
                {
                    int ignored;
                    Post(config, "/v1/token", "{\"token\":\"" + published + "\"}", out ignored);
                    publishedAt = DateTime.UtcNow;
                }
            }
            Thread.Sleep(2000);
        }
        if (IsLoggedIn(profile))
        {
            ReportResult(config, published, true);
            return true;
        }
        ReportResult(config, published, false);
        RemoveIncomplete(profile);
        status("AyuGram закрылся до входа");
        return false;
    }

    private static void ReportResult(Dictionary<string, object> config, string token, bool success)
    {
        if (string.IsNullOrEmpty(token)) { return; }
        var json = JsonMap.Write(new { token, success });
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                int code;
                Post(config, "/v1/finish", json, out code);
                if (code == 200) { return; }
            }
            catch { }
            Thread.Sleep(1000);
        }
        throw new InvalidOperationException("Не удалось подтвердить результат входа телефону; профиль на ПК сохранён");
    }

    internal static bool IsLoggedIn(string profile)
    {
        var tdata = Path.Combine(profile, "tdata");
        if (!Directory.Exists(tdata))
        {
            return false;
        }
        if (File.Exists(Path.Combine(tdata, "user_data")) || Directory.Exists(Path.Combine(tdata, "user_data")))
        {
            return true;
        }
        foreach (var dir in Directory.GetDirectories(tdata))
        {
            var name = Path.GetFileName(dir);
            if (name == null || name.Length != 16)
            {
                continue;
            }
            var hex = true;
            foreach (var ch in name)
            {
                if (!((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F') || (ch >= 'a' && ch <= 'f')))
                {
                    hex = false;
                    break;
                }
            }
            if (hex && File.Exists(Path.Combine(dir, "maps")))
            {
                return true;
            }
        }
        return false;
    }

    private static bool HasRpcFailure(string profile)
    {
        var logPath = Path.Combine(profile, "log.txt");
        if (!File.Exists(logPath))
        {
            return false;
        }
        try
        {
            using (var stream = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                var take = (int)Math.Min(stream.Length, 65536);
                if (take <= 0)
                {
                    return false;
                }
                stream.Seek(stream.Length - take, SeekOrigin.Begin);
                var buffer = new byte[take];
                stream.Read(buffer, 0, take);
                var text = Encoding.UTF8.GetString(buffer);
                return text.Contains("API_ID_INVALID") || text.Contains("AUTH_KEY_UNREGISTERED");
            }
        }
        catch
        {
            return false;
        }
    }

    private static void AbortLogin(Dictionary<string, object> config, int pid, string profile, Action<string> status, string message)
    {
        status(message);
        try
        {
            int ignored;
            Post(config, "/v1/clear", "{\"token\":\"\"}", out ignored);
        }
        catch
        {
        }
        try
        {
            if (PidAlive(pid))
            {
                Process.GetProcessById(pid).Kill();
            }
        }
        catch
        {
        }
        Thread.Sleep(400);
        RemoveIncomplete(profile);
    }

    private static void RemoveIncomplete(string profile)
    {
        var resolved = Path.GetFullPath(profile);
        var root = Path.GetFullPath(Profiles) + Path.DirectorySeparatorChar;
        if (!resolved.StartsWith(root, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(resolved).StartsWith("account-", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }
        if (IsLoggedIn(profile))
        {
            return;
        }
        try
        {
            if (Directory.Exists(profile))
            {
                foreach (var file in Directory.EnumerateFiles(profile, "*", SearchOption.AllDirectories))
                {
                    var info = new FileInfo(file);
                    if (info.IsReadOnly)
                    {
                        info.IsReadOnly = false;
                    }
                }
                Directory.Delete(profile, true);
            }
        }
        catch
        {
        }
    }

    private static string ReadToken(IntPtr hwnd)
    {
        var bitmap = Capture(hwnd);
        if (bitmap == null)
        {
            return null;
        }
        try
        {
            var reader = new BarcodeReader { AutoRotate = true, TryInverted = true };
            var result = reader.Decode(bitmap);
            if (result == null || string.IsNullOrEmpty(result.Text))
            {
                return null;
            }
            return NormalizeToken(result.Text);
        }
        finally
        {
            bitmap.Dispose();
        }
    }

    private static string NormalizeToken(string url)
    {
        var marker = "token=";
        var index = url.IndexOf(marker, StringComparison.Ordinal);
        if (index < 0)
        {
            return null;
        }
        var token = url.Substring(index + marker.Length).Split('&')[0].Trim().Replace('-', '+').Replace('_', '/');
        token += new string('=', (4 - token.Length % 4) % 4);
        try
        {
            Convert.FromBase64String(token);
        }
        catch
        {
            return null;
        }
        return token;
    }

    private static Bitmap Capture(IntPtr hwnd)
    {
        RECT rect;
        if (!GetWindowRect(hwnd, out rect))
        {
            return null;
        }
        if (IsIconic(hwnd))
        {
            ShowWindow(hwnd, 9);
            Thread.Sleep(200);
            GetWindowRect(hwnd, out rect);
        }
        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        if (width < 50 || height < 50)
        {
            return null;
        }
        var bitmap = new Bitmap(width, height);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new Size(width, height));
        }
        return bitmap;
    }

    private static void TypePassword(IntPtr hwnd, string password)
    {
        ForceForeground(hwnd);
        ClickCenter(hwnd);
        Thread.Sleep(250);
        foreach (var ch in password)
        {
            Key(0, ch, 0x0004);
            Key(0, ch, 0x0004 | 0x0002);
            Thread.Sleep(18);
        }
        Key(0x0D, 0, 0);
        Key(0x0D, 0, 0x0002);
    }

    private static void ForceForeground(IntPtr hwnd)
    {
        var foreground = GetForegroundWindow();
        int foregroundPid;
        var foregroundThread = GetWindowThreadProcessId(foreground, out foregroundPid);
        var thisThread = GetCurrentThreadId();
        AttachThreadInput(foregroundThread, thisThread, true);
        ShowWindow(hwnd, 9);
        SetForegroundWindow(hwnd);
        AttachThreadInput(foregroundThread, thisThread, false);
    }

    private static void ClickCenter(IntPtr hwnd)
    {
        RECT rect;
        if (!GetWindowRect(hwnd, out rect))
        {
            return;
        }
        SetCursorPos((rect.Left + rect.Right) / 2, (rect.Top + rect.Bottom) / 2);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }

    private static void Key(ushort virtualKey, ushort scan, uint flags)
    {
        var input = new INPUT[1];
        input[0].type = 1;
        input[0].ki.wVk = virtualKey;
        input[0].ki.wScan = scan;
        input[0].ki.dwFlags = flags;
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
    }

    private static bool PidAlive(int pid)
    {
        try
        {
            var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
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
    private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcess(string applicationName, System.Text.StringBuilder commandLine, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory, ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInformation);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    private static extern IntPtr GetModuleHandle(string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, UIntPtr size, uint allocationType, uint protect);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(IntPtr process, IntPtr address, byte[] buffer, int size, out int written);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateRemoteThread(IntPtr process, IntPtr attributes, UIntPtr stackSize, IntPtr startAddress, IntPtr parameter, uint flags, IntPtr threadId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr thread);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeThread(IntPtr thread, out uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public uint dwProcessId;
        public uint dwThreadId;
    }

    [DllImport("user32.dll")]
    private static extern uint SendInput(uint count, INPUT[] inputs, int size);

    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit, Size = 40)]
    private struct INPUT
    {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public KEYBDINPUT ki;
    }
}
