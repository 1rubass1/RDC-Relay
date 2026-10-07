using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Windows.Forms;
using System.Threading;
using Microsoft.Win32;

internal static class SetupProgram
{
    private sealed class Payload
    {
        public readonly string FileName;
        public readonly string ResourceName;
        public Payload(string fileName, string resourceName)
        {
            FileName = fileName;
            ResourceName = resourceName;
        }
    }

    private static readonly Payload[] Files = new Payload[]
    {
        new Payload("remote-window.ps1", "RdcPayload.remote-window.ps1"),
        new Payload("divider-caustic.ps", "RdcPayload.divider-caustic.ps"),
        new Payload("divider-caustic-detail.ps", "RdcPayload.divider-caustic-detail.ps"),
        new Payload("divider-particles.ps", "RdcPayload.divider-particles.ps"),
        new Payload("divider-particles-core.ps", "RdcPayload.divider-particles-core.ps"),
        new Payload("RDCRelay.ico", "RdcPayload.RDCRelay.ico"),
        new Payload("version.txt", "RdcPayload.version.txt"),
        new Payload("update.ps1", "RdcPayload.update.ps1"),
        new Payload("update-manifest.json", "RdcPayload.update-manifest.json"),
        new Payload("RDC Relay.cmd", "RdcPayload.launch.cmd")
    };

    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

    [STAThread]
    private static int Main(string[] args)
    {
        bool silent = HasArgument(args, "--silent");
        bool noShortcuts = HasArgument(args, "--no-shortcuts");
        bool noRegister = HasArgument(args, "--no-register");

        Mutex windowMutex = null, payloadMutex = null;
        bool ownsWindow = false, ownsPayload = false;
        PayloadTransaction transaction = null;
        try
        {
            string installRoot = GetOption(args, "--install-root");
            if (String.IsNullOrWhiteSpace(installRoot))
            {
                installRoot = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "RemoteDesktopCommanderLauncher");
            }
            installRoot = Path.GetFullPath(installRoot);
            installRoot = installRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string key;
            using (SHA256 sha = SHA256.Create())
                key = BitConverter.ToString(sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(installRoot.ToLowerInvariant()))).Replace("-", "");
            windowMutex = new Mutex(false, @"Local\RemoteDesktopCommanderWindow-" + key);
            try { ownsWindow = windowMutex.WaitOne(0); } catch (AbandonedMutexException) { ownsWindow = true; }
            if (!ownsWindow)
                throw new InvalidOperationException("Закройте окно RDC Relay перед установкой. Работающая версия не изменена.");
            payloadMutex = new Mutex(false, @"Local\RDCRelayPayload-" + key);
            try { ownsPayload = payloadMutex.WaitOne(0); } catch (AbandonedMutexException) { ownsPayload = true; }
            if (!ownsPayload)
                throw new InvalidOperationException("Другая установка или обновление RDC Relay уже выполняется.");
            Directory.CreateDirectory(installRoot);
            Directory.CreateDirectory(Path.Combine(installRoot, "backups"));

            string newVersion = ReadEmbeddedText("RdcPayload.version.txt").Trim();
            if (newVersion.Length == 0)
                throw new InvalidOperationException("Embedded version.txt is empty.");

            transaction = new PayloadTransaction(installRoot);
            transaction.Apply();
            DeleteIfExists(Path.Combine(installRoot, "Remote Desktop Commander.cmd"));
            DeleteIfExists(Path.Combine(installRoot, "CommanderRelay.cmd"));

            string iconPath = CreateVersionedIcon(installRoot, newVersion);
            if (!noShortcuts)
            {
                CreateShortcuts(installRoot, iconPath);
                SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
            }
            CleanupLegacyIcons(installRoot, iconPath);
            if (!noRegister)
                RegisterInstalledApp(installRoot, iconPath, newVersion);

            transaction.Commit();
            DeleteIfExists(Path.Combine(installRoot, ".local-candidate.json"));
            if (!silent)
            {
                MessageBox.Show(
                    "RDC Relay v" + newVersion + " установлен.\r\n\r\n" +
                    "Используйте ярлык «RDC Relay» на рабочем столе или в меню Пуск.",
                    "RDC Relay",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }

            return 0;
        }
        catch (Exception ex)
        {
            string error = ex.Message;
            if (transaction != null)
            {
                try { transaction.Rollback(); }
                catch (Exception rollbackError) { error += "\r\nRollback: " + rollbackError.Message; }
            }
            if (!silent)
            {
                MessageBox.Show(
                    "Не удалось установить RDC Relay.\r\n\r\n" + error,
                    "RDC Relay Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            return 1;
        }
        finally
        {
            if (transaction != null) transaction.Dispose();
            if (ownsPayload) payloadMutex.ReleaseMutex();
            if (payloadMutex != null) payloadMutex.Dispose();
            if (ownsWindow) windowMutex.ReleaseMutex();
            if (windowMutex != null) windowMutex.Dispose();
        }
    }

    private static bool HasArgument(string[] args, string name)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (String.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static string GetOption(string[] args, string name)
    {
        for (int i = 0; i + 1 < args.Length; i++)
        {
            if (String.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        }
        return null;
    }

    private static string ReadEmbeddedText(string resourceName)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        using (Stream stream = asm.GetManifestResourceStream(resourceName))
        {
            if (stream == null)
                throw new InvalidOperationException("Missing embedded resource: " + resourceName);
            using (StreamReader reader = new StreamReader(stream, System.Text.Encoding.UTF8, true))
                return reader.ReadToEnd();
        }
    }

    // Keep the complete previous payload until all installation steps succeed.
    private sealed class PayloadTransaction : IDisposable
    {
        private readonly string root, stage, backup;
        private readonly List<string> attempted = new List<string>();
        private readonly HashSet<string> existed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private bool committed;

        public PayloadTransaction(string installRoot)
        {
            root = installRoot;
            string id = DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N");
            stage = Path.Combine(root, ".setup-stage-" + id);
            backup = Path.Combine(root, "backups", "manual-" + id);
        }

        public void Apply()
        {
            Directory.CreateDirectory(stage);
            Directory.CreateDirectory(backup);
            Assembly asm = Assembly.GetExecutingAssembly();
            foreach (Payload payload in Files)
            {
                using (Stream input = asm.GetManifestResourceStream(payload.ResourceName))
                {
                    if (input == null) throw new InvalidOperationException("Missing embedded resource: " + payload.ResourceName);
                    using (FileStream output = new FileStream(Path.Combine(stage, payload.FileName), FileMode.CreateNew))
                        input.CopyTo(output);
                }
                string destination = Path.Combine(root, payload.FileName);
                if (File.Exists(destination))
                {
                    File.Copy(destination, Path.Combine(backup, payload.FileName), false);
                    existed.Add(payload.FileName);
                }
            }
            foreach (Payload payload in Files)
            {
                string destination = Path.Combine(root, payload.FileName);
                string source = Path.Combine(stage, payload.FileName);
                attempted.Add(payload.FileName);
                if (existed.Contains(payload.FileName)) File.Replace(source, destination, null);
                else File.Move(source, destination);
            }
        }

        public void Commit() { committed = true; }

        public void Rollback()
        {
            if (committed) return;
            List<string> errors = new List<string>();
            for (int i = attempted.Count - 1; i >= 0; i--)
            {
                string name = attempted[i];
                string destination = Path.Combine(root, name);
                try
                {
                    if (existed.Contains(name))
                    {
                        if (File.Exists(destination) && SameContent(destination, Path.Combine(backup, name))) continue;
                        string restore = Path.Combine(stage, "restore-" + name);
                        File.Copy(Path.Combine(backup, name), restore, true);
                        if (File.Exists(destination)) File.Replace(restore, destination, null);
                        else File.Move(restore, destination);
                    }
                    else if (File.Exists(destination)) File.Delete(destination);
                }
                catch (Exception ex) { errors.Add(name + ": " + ex.Message); }
            }
            if (errors.Count > 0)
                throw new IOException(String.Join("; ", errors.ToArray()) + ". Backup: " + backup);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(stage)) Directory.Delete(stage, true); } catch { }
        }

        private static bool SameContent(string first, string second)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream a = File.OpenRead(first))
            using (FileStream b = File.OpenRead(second))
                return BitConverter.ToString(sha.ComputeHash(a)) == BitConverter.ToString(sha.ComputeHash(b));
        }
    }

    private static string CreateVersionedIcon(string installRoot, string version)
    {
        string source = Path.Combine(installRoot, "RDCRelay.ico");
        string hash;
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(source))
            hash = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").Substring(0, 8);

        string versioned = Path.Combine(
            installRoot,
            "RDCRelay-v" + version + "-" + hash + ".ico");
        File.Copy(source, versioned, true);
        return versioned;
    }

    private static void DeleteIfExists(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch { }
    }

    private static void CleanupLegacyIcons(string installRoot, string currentIconPath)
    {
        DeleteIfExists(Path.Combine(installRoot, "DesktopCommander.ico"));

        string[] legacy = Directory.GetFiles(installRoot, "DesktopCommander-v*.ico");
        for (int i = 0; i < legacy.Length; i++)
            DeleteIfExists(legacy[i]);

        string[] oldRelay = Directory.GetFiles(installRoot, "RDCRelay-v*.ico");
        for (int i = 0; i < oldRelay.Length; i++)
        {
            if (!String.Equals(
                Path.GetFullPath(oldRelay[i]),
                Path.GetFullPath(currentIconPath),
                StringComparison.OrdinalIgnoreCase))
            {
                DeleteIfExists(oldRelay[i]);
            }
        }
    }

    private static void RegisterInstalledApp(string installRoot, string iconPath, string version)
    {
        string powershell = Path.Combine(
            Environment.SystemDirectory,
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        string updateScript = Path.Combine(installRoot, "update.ps1");
        string baseArgs =
            "-NoProfile -ExecutionPolicy Bypass -File " + Quote(updateScript) +
            " -InstallRoot " + Quote(installRoot) +
            " -CurrentVersion " + Quote(version) +
            " -Uninstall";

        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(
            String.Join(((char)92).ToString(), new string[] { "Software", "Microsoft", "Windows", "CurrentVersion", "Uninstall", "RDC Relay" })))
        {
            if (key == null)
                throw new InvalidOperationException("Cannot create Installed Apps registry entry.");

            key.SetValue("DisplayName", "RDC Relay", RegistryValueKind.String);
            key.SetValue("DisplayVersion", version, RegistryValueKind.String);
            key.SetValue("Publisher", "UMAS", RegistryValueKind.String);
            key.SetValue("InstallLocation", installRoot, RegistryValueKind.String);
            key.SetValue("DisplayIcon", iconPath, RegistryValueKind.String);
            key.SetValue("URLInfoAbout", "https://github.com/1rubass1/RDC-Relay", RegistryValueKind.String);
            key.SetValue("UninstallString", Quote(powershell) + " " + baseArgs, RegistryValueKind.String);
            key.SetValue("QuietUninstallString", Quote(powershell) + " " + baseArgs + " -Silent", RegistryValueKind.String);
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            key.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"), RegistryValueKind.String);
            key.SetValue("EstimatedSize", CalculateEstimatedSizeKb(installRoot), RegistryValueKind.DWord);
        }
    }

    private static int CalculateEstimatedSizeKb(string installRoot)
    {
        long bytes = 0;
        try
        {
            string[] files = Directory.GetFiles(installRoot, "*", SearchOption.AllDirectories);
            for (int i = 0; i < files.Length; i++)
            {
                try { bytes += new FileInfo(files[i]).Length; } catch { }
            }
        }
        catch { }

        long kb = Math.Max(1L, (bytes + 1023L) / 1024L);
        return (int)Math.Min(Int32.MaxValue, kb);
    }

    private static string Quote(string value)
    {
        return "\"" + value + "\"";
    }

    private static void CreateShortcuts(string installRoot, string iconPath)
    {
        string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);

        DeleteIfExists(Path.Combine(desktop, "Remote Desktop Commander.lnk"));
        DeleteIfExists(Path.Combine(programs, "Remote Desktop Commander.lnk"));
        DeleteIfExists(Path.Combine(desktop, "CommanderRelay.lnk"));
        DeleteIfExists(Path.Combine(programs, "CommanderRelay.lnk"));
        CreateShortcut(Path.Combine(desktop, "RDC Relay.lnk"), installRoot, iconPath);
        CreateShortcut(Path.Combine(programs, "RDC Relay.lnk"), installRoot, iconPath);
    }

    private static void CreateShortcut(string shortcutPath, string installRoot, string iconPath)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null)
            throw new InvalidOperationException("WScript.Shell is not available.");

        object shell = Activator.CreateInstance(shellType);
        object shortcut = shellType.InvokeMember(
            "CreateShortcut",
            BindingFlags.InvokeMethod,
            null,
            shell,
            new object[] { shortcutPath });

        Type shortcutType = shortcut.GetType();
        string powershell = Path.Combine(
            Environment.SystemDirectory,
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        string script = Path.Combine(installRoot, "remote-window.ps1");

        shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { powershell });
        shortcutType.InvokeMember(
            "Arguments",
            BindingFlags.SetProperty,
            null,
            shortcut,
            new object[] { "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"" });
        shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { installRoot });
        shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { iconPath + ",0" });
        shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { "RDC Relay" });
        shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);

        Marshal.FinalReleaseComObject(shortcut);
        Marshal.FinalReleaseComObject(shell);
    }
}
