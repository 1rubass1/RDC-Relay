using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Windows.Forms;

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
        new Payload("divider-particles.ps", "RdcPayload.divider-particles.ps"),
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
            Directory.CreateDirectory(installRoot);
            Directory.CreateDirectory(Path.Combine(installRoot, "backups"));

            string newVersion = ReadEmbeddedText("RdcPayload.version.txt").Trim();
            if (newVersion.Length == 0)
                throw new InvalidOperationException("Embedded version.txt is empty.");

            BackupExistingPayload(installRoot);
            ExtractPayload(installRoot);
            DeleteIfExists(Path.Combine(installRoot, "Remote Desktop Commander.cmd"));
            DeleteIfExists(Path.Combine(installRoot, "CommanderRelay.cmd"));

            string iconPath = CreateVersionedIcon(installRoot, newVersion);
            if (!noShortcuts)
            {
                CreateShortcuts(installRoot, iconPath);
                SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
            }
            CleanupLegacyIcons(installRoot, iconPath);

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
            if (!silent)
            {
                MessageBox.Show(
                    "Не удалось установить RDC Relay.\r\n\r\n" + ex.Message,
                    "RDC Relay Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            return 1;
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

    private static void BackupExistingPayload(string installRoot)
    {
        bool any = false;
        for (int i = 0; i < Files.Length; i++)
        {
            if (File.Exists(Path.Combine(installRoot, Files[i].FileName)))
            {
                any = true;
                break;
            }
        }
        if (!any) return;

        string oldVersion = "unknown";
        string oldVersionPath = Path.Combine(installRoot, "version.txt");
        try
        {
            if (File.Exists(oldVersionPath))
            {
                string value = File.ReadAllText(oldVersionPath).Trim();
                if (value.Length > 0) oldVersion = value;
            }
        }
        catch { }

        string backupRoot = Path.Combine(
            installRoot,
            "backups",
            "manual-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-v" + oldVersion);
        Directory.CreateDirectory(backupRoot);

        for (int i = 0; i < Files.Length; i++)
        {
            string source = Path.Combine(installRoot, Files[i].FileName);
            if (File.Exists(source))
                File.Copy(source, Path.Combine(backupRoot, Files[i].FileName), true);
        }
    }

    private static void ExtractPayload(string installRoot)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        for (int i = 0; i < Files.Length; i++)
        {
            Payload payload = Files[i];
            string destination = Path.Combine(installRoot, payload.FileName);
            string staged = destination + ".new";

            using (Stream input = asm.GetManifestResourceStream(payload.ResourceName))
            {
                if (input == null)
                    throw new InvalidOperationException("Missing embedded resource: " + payload.ResourceName);
                using (FileStream output = new FileStream(staged, FileMode.Create, FileAccess.Write, FileShare.None))
                    input.CopyTo(output);
            }

            File.Copy(staged, destination, true);
            File.Delete(staged);
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
