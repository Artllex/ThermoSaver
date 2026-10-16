using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal static class Host
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int kind, IntPtr info, uint length);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits
    {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A, B, C, D, E, F; }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits
    {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [STAThread] static int Main(string[] args)
    {
        IntPtr job = IntPtr.Zero;
        try
        {
            if (args.Length != 1) return 2;
            string script;
            switch (args[0])
            {
                case "guard": script = "Run-Guard.ps1"; break;
                case "notifier": script = "Run-Notifier.ps1"; break;
                case "watchdog": case "recovery": script = "Run-Watchdog.ps1"; break;
                default: return 2;
            }
            string root = AppDomain.CurrentDomain.BaseDirectory;
            var info = new ProcessStartInfo(Path.Combine(root, "runtime", "pwsh.exe"));
            info.Arguments = "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \"" + Path.Combine(root, script) + "\"";
            if (args[0] == "recovery") info.Arguments += " -Once";
            info.WorkingDirectory = root;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.WindowStyle = ProcessWindowStyle.Hidden;
            job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new InvalidOperationException("Cannot create process job.");
            var limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000; // Terminating the task must also terminate its PowerShell child.
            int size = Marshal.SizeOf(limits);
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(limits, buffer, false);
                if (!SetInformationJobObject(job, 9, buffer, (uint)size)) throw new InvalidOperationException("Cannot configure process job.");
            }
            finally { Marshal.FreeHGlobal(buffer); }
            using (var child = Process.Start(info))
            {
                if (!AssignProcessToJobObject(job, child.Handle))
                {
                    child.Kill();
                    throw new InvalidOperationException("Cannot supervise PowerShell child.");
                }
                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch (Exception ex)
        {
            try
            {
                string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "ThermoSaver");
                if (args.Length == 1 && args[0] == "notifier") directory = Path.Combine(directory, "requests");
                File.AppendAllText(Path.Combine(directory, "host-errors.log"), DateTime.UtcNow.ToString("o") + " " + ex.Message + Environment.NewLine);
            }
            catch { }
            return 1;
        }
        finally { if (job != IntPtr.Zero) CloseHandle(job); }
    }
}
