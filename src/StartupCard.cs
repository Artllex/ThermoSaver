using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

public sealed class ThermoSaverMenuColors : ProfessionalColorTable
{
    readonly Color background, selected, border;
    public ThermoSaverMenuColors(bool dark)
    {
        UseSystemColors = false;
        background = dark ? Color.FromArgb(32,32,32) : Color.FromArgb(249,249,249);
        selected = dark ? Color.FromArgb(55,55,55) : Color.FromArgb(229,239,249);
        border = dark ? Color.FromArgb(75,75,75) : Color.FromArgb(200,200,200);
    }
    public override Color ToolStripDropDownBackground { get { return background; } }
    public override Color ImageMarginGradientBegin { get { return background; } }
    public override Color ImageMarginGradientMiddle { get { return background; } }
    public override Color ImageMarginGradientEnd { get { return background; } }
    public override Color MenuBorder { get { return border; } }
    public override Color MenuItemSelected { get { return selected; } }
    public override Color MenuItemSelectedGradientBegin { get { return selected; } }
    public override Color MenuItemSelectedGradientEnd { get { return selected; } }
    public override Color MenuItemBorder { get { return selected; } }
    public override Color CheckBackground { get { return selected; } }
    public override Color CheckSelectedBackground { get { return selected; } }
    public override Color CheckPressedBackground { get { return selected; } }
}

public sealed class ThermoSaverMenuRenderer : ToolStripProfessionalRenderer
{
    public ThermoSaverMenuRenderer(bool dark) : base(new ThermoSaverMenuColors(dark)) { RoundedEdges = false; }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
    {
        ControlPaint.DrawMenuGlyph(e.Graphics, e.ImageRectangle, MenuGlyph.Checkmark, e.Item.ForeColor, e.Item.BackColor);
    }
}

public sealed class ThermoSaverTrayMenu : ContextMenuStrip
{
    readonly Timer outsideClick = new Timer { Interval = 50 };
    bool? appliedTheme;
    public bool DarkTheme { get { return appliedTheme == true; } }
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    public ThermoSaverTrayMenu()
    {
        Opening += delegate { RefreshSystemTheme(); };
        ItemAdded += delegate(object sender, ToolStripItemEventArgs e) { StyleItem(e.Item); };
        RefreshSystemTheme();
        Opened += delegate { outsideClick.Start(); };
        Closed += delegate { outsideClick.Stop(); };
        outsideClick.Tick += delegate
        {
            bool outside = !Bounds.Contains(Cursor.Position);
            if (GetAsyncKeyState(27) < 0 || (outside && (GetAsyncKeyState(1) < 0 || GetAsyncKeyState(2) < 0))) Close();
        };
    }
    void StyleItem(ToolStripItem item)
    {
        float scale = DeviceDpi / 96f;
        item.Padding = new Padding((int)(6*scale),(int)(3*scale),(int)(6*scale),(int)(3*scale));
        item.ForeColor = ForeColor;
        item.BackColor = BackColor;
    }
    public void RefreshSystemTheme()
    {
        bool dark = false;
        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
            {
                object value = key == null ? null : key.GetValue("SystemUsesLightTheme", key.GetValue("AppsUseLightTheme", 1));
                dark = value != null && Convert.ToInt32(value) == 0;
            }
        }
        catch { }
        ApplyTheme(dark);
    }
    public void ApplyTheme(bool dark)
    {
        appliedTheme = dark;
        if (SystemInformation.HighContrast)
        {
            RenderMode = ToolStripRenderMode.System;
            BackColor = SystemColors.Menu;
            ForeColor = SystemColors.MenuText;
        }
        else
        {
            Renderer = new ThermoSaverMenuRenderer(dark);
            BackColor = dark ? Color.FromArgb(32,32,32) : Color.FromArgb(249,249,249);
            ForeColor = dark ? Color.FromArgb(240,240,240) : Color.FromArgb(32,32,32);
        }
        int margin = Math.Max(1,(int)(3 * DeviceDpi / 96f));
        Padding = new Padding(margin);
        foreach (ToolStripItem item in Items) StyleItem(item);
        Invalidate();
    }
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= 0x08000000; return value; }
    }
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x21) { message.Result = new IntPtr(3); return; }
        base.WndProc(ref message);
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) outsideClick.Dispose();
        base.Dispose(disposing);
    }
}

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
