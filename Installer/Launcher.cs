using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("RDC Relay")]
[assembly: AssemblyDescription("Portable launcher for RDC Relay")]
[assembly: AssemblyCompany("UMAS")]
[assembly: AssemblyProduct("RDC Relay")]

internal static class LauncherProgram
{
    [STAThread]
    private static int Main()
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "remote-window.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("remote-window.ps1 not found.", script);

            string powershell = Path.Combine(
                Environment.SystemDirectory,
                "WindowsPowerShell",
                "v1.0",
                "powershell.exe");

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = powershell;
            psi.Arguments =
                "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" +
                script + "\"";
            psi.WorkingDirectory = root;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Не удалось запустить RDC Relay.\r\n\r\n" + ex.Message,
                "RDC Relay",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
