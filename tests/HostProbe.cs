using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
class Probe
{
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    static int Main(string[] args)
    {
        string root = Path.GetDirectoryName(AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        File.WriteAllText(Path.Combine(root, "probe.txt"), Process.GetCurrentProcess().Id + "|" + GetConsoleWindow().ToInt64() + "|" + string.Join(" ", args));
        Thread.Sleep(5000);
        return 7;
    }
}
