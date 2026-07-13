using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

// PC Malin - lanceur natif
// Extrait le script embarque et l'execute sans aucune fenetre console.
static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string exePath = Assembly.GetExecutingAssembly().Location;

        // 1. Elevation administrateur (UAC) si necessaire
        bool isAdmin;
        try
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            {
                isAdmin = new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
            }
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
                    "PC Malin a besoin de l'autorisation administrateur pour nettoyer les fichiers systeme.\n\n" +
                    "Relancez-le et cliquez sur \"Oui\" quand Windows le demande.",
                    "PC Malin", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            return 0;
        }

        // 2. Extraire le script embarque vers un fichier temporaire
        string tempPs = Path.Combine(Path.GetTempPath(),
            "pcmalin_" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".ps1");
        try
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("pcmalin.ps1"))
            {
                if (s == null) throw new Exception("Ressource interne introuvable.");
                using (FileStream f = File.Create(tempPs)) { s.CopyTo(f); }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Impossible de preparer PC Malin :\n\n" + ex.Message,
                "PC Malin", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // 3. Lancer PowerShell sans fenetre console
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
            MessageBox.Show("Impossible de demarrer PC Malin :\n\n" + ex.Message,
                "PC Malin", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            try { File.Delete(tempPs); } catch { }
        }
        return rc;
    }
}
