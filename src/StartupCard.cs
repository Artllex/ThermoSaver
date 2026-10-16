using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class ThermoSaverStartupCard : Form
{
    readonly Timer dismiss = new Timer();
    readonly Icon artwork;
    readonly Font heading = new Font("Segoe UI", 10, FontStyle.Bold);
    readonly Font body = new Font("Segoe UI", 9);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr buffer, int length, out int required);
    public static string LogonId(IntPtr token)
    {
        IntPtr buffer = Marshal.AllocHGlobal(56);
        try
        {
            int required;
            if (!GetTokenInformation(token, 10, buffer, 56, out required)) throw new InvalidOperationException("Cannot identify logon session.");
            return Marshal.ReadInt64(buffer, 8).ToString("X16");
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= 0x08000000; return value; }
    }
    public ThermoSaverStartupCard(string text, string iconPath)
    {
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(39, 39, 39);
        ForeColor = Color.White;
        Text = "ThermoSaver - status";
        var handle = Handle;
        float scale = DeviceDpi / 96f;
        ClientSize = new Size((int)(360 * scale), (int)(112 * scale));
        artwork = new Icon(iconPath);
        var picture = new PictureBox { Image = artwork.ToBitmap(), SizeMode = PictureBoxSizeMode.Zoom };
        picture.SetBounds((int)(16*scale), (int)(18*scale), (int)(32*scale), (int)(32*scale));
        var title = new Label { Text = "ThermoSaver dzia\u0142a", Font = heading };
        title.SetBounds((int)(60*scale), (int)(14*scale), (int)(250*scale), (int)(25*scale));
        var content = new Label { Text = text, Font = body };
        content.SetBounds((int)(60*scale), (int)(42*scale), (int)(280*scale), (int)(60*scale));
        var close = new Button { Text = "\u00d7", FlatStyle = FlatStyle.Flat, ForeColor = Color.White, BackColor = BackColor, TabStop = false };
        close.SetBounds((int)(326*scale), (int)(8*scale), (int)(26*scale), (int)(26*scale));
        close.FlatAppearance.BorderSize = 0;
        close.Click += delegate { Close(); };
        Controls.AddRange(new Control[] { picture, title, content, close });
        var area = Screen.PrimaryScreen.WorkingArea;
        Location = new Point(area.Right - Width - (int)(16*scale), area.Bottom - Height - (int)(16*scale));
        dismiss.Interval = 10000;
        dismiss.Tick += delegate { Close(); };
        Shown += delegate { dismiss.Start(); };
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            dismiss.Dispose();
            foreach (Control control in Controls) { var picture = control as PictureBox; if (picture != null) picture.Image.Dispose(); }
            artwork.Dispose(); heading.Dispose(); body.Dispose();
        }
        base.Dispose(disposing);
    }
}
