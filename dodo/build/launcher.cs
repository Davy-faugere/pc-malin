using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

// Dodo - lanceur natif de l'assistant d'installation.
// Demande l'elevation, extrait l'assistant embarque, l'execute sans console.
static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string exePath = Assembly.GetExecutingAssembly().Location;

        // 1. Elevation administrateur (UAC)
        bool isAdmin;
        try
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
                isAdmin = new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch { isAdmin = false; }

        if (!isAdmin)
        {
            try
            {
                ProcessStartInfo up = new ProcessStartInfo(exePath);
                up.UseShellExecute = true;
                up.Verb = "runas";
                Process.Start(up);
            }
            catch
            {
                MessageBox.Show(
                    "Dodo a besoin de l'autorisation administrateur pour installer le couvre-feu.\n\n" +
                    "Relancez-le et cliquez sur \"Oui\" quand Windows le demande.",
                    "Dodo", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            return 0;
        }

        // 2. Extraire l'assistant embarque (UTF-8 avec BOM : les accents en dependent)
        string tempPs = Path.Combine(Path.GetTempPath(),
            "dodo_" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".ps1");
        try
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("assistant.ps1"))
            {
                if (s == null) throw new Exception("Ressource interne introuvable.");
                using (FileStream f = File.Create(tempPs)) { s.CopyTo(f); }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Impossible de preparer Dodo :\n\n" + ex.Message,
                "Dodo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // 3. Lancer l'assistant, sans fenetre console
        int rc = 1;
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Path.Combine(Environment.SystemDirectory,
                @"WindowsPowerShell\v1.0\powershell.exe");
            psi.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File \"" + tempPs +
                            "\" -SrcCmd \"" + exePath + "\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                rc = p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Impossible de demarrer Dodo :\n\n" + ex.Message,
                "Dodo", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally { try { File.Delete(tempPs); } catch { } }
        return rc;
    }
}
