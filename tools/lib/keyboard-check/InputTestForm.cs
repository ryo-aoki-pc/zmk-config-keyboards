// Windows for the interactive test of tools/keyboard-check.ps1 (KcInputTestForm) and for the
// input event monitor of tools/input-monitor.ps1 (KcInputMonitorForm).
// Records Raw Input (WM_INPUT) per device: keyboard scan codes (layout independent) and
// relative mouse movement before pointer acceleration, so key taps and trackball motion can be
// checked against the expected values, and the timing of the reports can be analyzed.
// Loaded by tools/lib/keyboard-check/input-test.ps1 with Add-Type. Both windows live in this one
// file because every Add-Type call makes its own assembly: a second file could not share
// KcInputEvent / KcRawInputParser without a duplicate type name.
// Must stay C# 5 compatible (Windows PowerShell 5.1 compiles it with the .NET Framework compiler)
// and ASCII only. User-visible strings are passed in from PowerShell.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class KcInputEvent
{
    public long Time;     // milliseconds since the window was created (Stopwatch)
    public long TimeUs;   // microseconds, set by KcInputMonitorForm only (0 in KcInputTestForm)
    public long Device;
    public string Kind;   // "key" or "mouse"
    public int Scan;
    public int Prefix;    // 0, 0xE0 or 0xE1
    public bool Break;
    public int Dx;
    public int Dy;
    public int Buttons;   // RI_MOUSE_BUTTON_n_DOWN / _UP flags
    public int Wheel;     // 120 per notch, negative = toward the user (scroll down)
    public int HWheel;    // positive = right
}

public static class KcRawInputParser
{
    public const int RIM_TYPEMOUSE = 0;
    public const int RIM_TYPEKEYBOARD = 1;

    // Parses a RAWINPUT buffer returned by GetRawInputData(RID_INPUT). ptrSize is IntPtr.Size of the
    // process (the header is dwType, dwSize, hDevice, wParam). Returns null for input to ignore
    // (injected input, fake shifts, absolute pointers' movement).
    public static KcInputEvent Parse(byte[] data, int ptrSize, long time)
    {
        if (data == null || data.Length < 8 + 2 * ptrSize)
        {
            return null;
        }
        int type = BitConverter.ToInt32(data, 0);
        long device = ptrSize == 8 ? BitConverter.ToInt64(data, 8) : BitConverter.ToInt32(data, 8);
        if (device == 0)
        {
            return null; // injected (SendInput) input has no device
        }
        int off = 8 + 2 * ptrSize;
        KcInputEvent e = new KcInputEvent();
        e.Time = time;
        e.Device = device;
        if (type == RIM_TYPEKEYBOARD)
        {
            if (data.Length < off + 8)
            {
                return null;
            }
            int makeCode = BitConverter.ToUInt16(data, off);
            int flags = BitConverter.ToUInt16(data, off + 2);
            int vkey = BitConverter.ToUInt16(data, off + 6);
            if (makeCode == 0 && vkey == 0xFF)
            {
                return null;
            }
            int prefix = 0;
            if ((flags & 2) != 0)
            {
                prefix = 0xE0;
            }
            else if ((flags & 4) != 0)
            {
                prefix = 0xE1;
            }
            if (prefix == 0xE0 && (makeCode == 0x2A || makeCode == 0x36))
            {
                return null; // fake shift around Print Screen / navigation keys
            }
            e.Kind = "key";
            e.Scan = makeCode;
            e.Prefix = prefix;
            e.Break = (flags & 1) != 0;
            return e;
        }
        if (type == RIM_TYPEMOUSE)
        {
            if (data.Length < off + 20)
            {
                return null;
            }
            int usFlags = BitConverter.ToUInt16(data, off);
            int buttonFlags = BitConverter.ToUInt16(data, off + 4);
            int buttonData = BitConverter.ToInt16(data, off + 6);
            e.Kind = "mouse";
            if ((usFlags & 1) == 0)
            {
                e.Dx = BitConverter.ToInt32(data, off + 12);
                e.Dy = BitConverter.ToInt32(data, off + 16);
            }
            e.Buttons = buttonFlags & 0x03FF;
            if ((buttonFlags & 0x0400) != 0)
            {
                e.Wheel = buttonData;
            }
            if ((buttonFlags & 0x0800) != 0)
            {
                e.HWheel = buttonData;
            }
            if (e.Dx == 0 && e.Dy == 0 && e.Buttons == 0 && e.Wheel == 0 && e.HWheel == 0)
            {
                return null;
            }
            return e;
        }
        return null;
    }
}

// A button that never takes the keyboard focus, so Enter / Space from the tested keyboard
// cannot press it.
public class KcNoFocusButton : Button
{
    public KcNoFocusButton()
    {
        SetStyle(ControlStyles.Selectable, false);
        TabStop = false;
    }
}

// Draws the keyboard layout with a state per key.
public class KcKeyboardPanel : Panel
{
    public const int StateNormal = 0;
    public const int StateCurrent = 1;
    public const int StatePass = 2;
    public const int StateFail = 3;
    public const int StateSkip = 4;

    sealed class Key
    {
        public int Pos;
        public float X;
        public float Y;
        public float W;
        public float H;
        public string Legend;
        public int State;
    }

    readonly List<Key> keys = new List<Key>();

    public KcKeyboardPanel()
    {
        DoubleBuffered = true;
        SetStyle(ControlStyles.Selectable, false);
        TabStop = false;
    }

    public void SetKeys(int[] pos, double[] x, double[] y, double[] w, double[] h, string[] legends)
    {
        keys.Clear();
        for (int i = 0; i < pos.Length; i++)
        {
            Key k = new Key();
            k.Pos = pos[i];
            k.X = (float)x[i];
            k.Y = (float)y[i];
            k.W = (float)w[i];
            k.H = (float)h[i];
            k.Legend = legends[i] ?? "";
            keys.Add(k);
        }
        Invalidate();
    }

    public void SetState(int pos, int state)
    {
        foreach (Key k in keys)
        {
            if (k.Pos == pos)
            {
                k.State = state;
            }
        }
        Invalidate();
    }

    public void ClearStates()
    {
        foreach (Key k in keys)
        {
            k.State = StateNormal;
        }
        Invalidate();
    }

    static Color Fill(int state)
    {
        switch (state)
        {
            case StateCurrent: return Color.FromArgb(255, 214, 102);
            case StatePass: return Color.FromArgb(152, 222, 160);
            case StateFail: return Color.FromArgb(244, 143, 143);
            case StateSkip: return Color.FromArgb(214, 214, 214);
            default: return Color.White;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (keys.Count == 0)
        {
            return;
        }
        float minX = float.MaxValue, minY = float.MaxValue, maxX = float.MinValue, maxY = float.MinValue;
        foreach (Key k in keys)
        {
            minX = Math.Min(minX, k.X);
            minY = Math.Min(minY, k.Y);
            maxX = Math.Max(maxX, k.X + k.W);
            maxY = Math.Max(maxY, k.Y + k.H);
        }
        float pad = 10;
        float scale = Math.Min((Width - 2 * pad) / Math.Max(maxX - minX, 1), (Height - 2 * pad) / Math.Max(maxY - minY, 1));
        float offX = pad + (Width - 2 * pad - (maxX - minX) * scale) / 2;
        float offY = pad + (Height - 2 * pad - (maxY - minY) * scale) / 2;
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (Font font = new Font(Font.FontFamily, Math.Max(7f, scale * 0.22f)))
        using (Pen border = new Pen(Color.FromArgb(120, 120, 120), 1.5f))
        using (Pen current = new Pen(Color.FromArgb(200, 120, 0), 3f))
        using (StringFormat center = new StringFormat())
        {
            center.Alignment = StringAlignment.Center;
            center.LineAlignment = StringAlignment.Center;
            foreach (Key k in keys)
            {
                RectangleF r = new RectangleF(offX + (k.X - minX) * scale + 2, offY + (k.Y - minY) * scale + 2, k.W * scale - 4, k.H * scale - 4);
                using (SolidBrush b = new SolidBrush(Fill(k.State)))
                {
                    g.FillRectangle(b, r);
                }
                g.DrawRectangle(k.State == StateCurrent ? current : border, r.X, r.Y, r.Width, r.Height);
                g.DrawString(k.Legend, font, Brushes.Black, r, center);
            }
        }
    }
}

public class KcInputTestForm : Form
{
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE
    {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT
    {
        public uint VkCode;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint GetRawInputData(IntPtr rawInput, uint command, byte[] data, ref uint size, uint headerSize);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder data, ref uint size);

    [DllImport("user32.dll")]
    static extern bool ClipCursor(ref RECT rect);

    [DllImport("user32.dll", EntryPoint = "ClipCursor")]
    static extern bool ClipCursorOff(IntPtr rect);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetWindowsHookEx(int hookId, LowLevelKeyboardProc proc, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    static extern IntPtr CallNextHookEx(IntPtr hook, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr GetModuleHandle(string name);

    [DllImport("user32.dll")]
    static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extraInfo);

    const int WM_INPUT = 0x00FF;
    const int WM_KEYDOWN = 0x0100;
    const int WM_KEYUP = 0x0101;
    const int WM_CHAR = 0x0102;
    const int WM_SYSKEYDOWN = 0x0104;
    const int WM_SYSKEYUP = 0x0105;
    const int WM_SYSCHAR = 0x0106;
    const int WM_SYSCOMMAND = 0x0112;
    const int SC_KEYMENU = 0xF100;
    const uint RID_INPUT = 0x10000003;
    const uint RIDI_DEVICENAME = 0x20000007;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const int WH_KEYBOARD_LL = 13;
    const uint LLKHF_INJECTED = 0x10;
    const byte VK_MASK = 0xE8; // unassigned virtual key, used to keep Win from opening the Start menu
    const uint KEYEVENTF_KEYUP = 0x0002;

    readonly object sync = new object();
    readonly List<KcInputEvent> events = new List<KcInputEvent>();
    readonly Stopwatch clock = Stopwatch.StartNew();
    readonly Label titleLabel = new Label();
    readonly Label instructionLabel = new Label();
    readonly Label detailLabel = new Label();
    readonly Label statusLabel = new Label();
    readonly Label logLabel = new Label();
    readonly KcKeyboardPanel keyboard = new KcKeyboardPanel();
    readonly FlowLayoutPanel buttonBar = new FlowLayoutPanel();
    readonly KcNoFocusButton nextButton = new KcNoFocusButton();
    readonly KcNoFocusButton retryButton = new KcNoFocusButton();
    readonly KcNoFocusButton skipButton = new KcNoFocusButton();
    readonly KcNoFocusButton abortButton = new KcNoFocusButton();
    readonly Timer clipTimer = new Timer();
    string action = "";
    bool closed;
    bool confine;
    bool maskWin;
    IntPtr hook = IntPtr.Zero;
    LowLevelKeyboardProc hookProc;

    public KcInputTestForm()
    {
        Text = "keyboard-check";
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1100, 780);
        MinimumSize = new Size(800, 600);
        TopMost = true;
        KeyPreview = false;
        ImeMode = ImeMode.Disable;
        BackColor = Color.FromArgb(246, 247, 250);
        Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 11f);

        titleLabel.Dock = DockStyle.Top;
        titleLabel.Height = 40;
        titleLabel.Font = new Font(Font.FontFamily, 13f, FontStyle.Bold);
        titleLabel.Padding = new Padding(12, 10, 12, 0);

        instructionLabel.Dock = DockStyle.Top;
        instructionLabel.Height = 120;
        instructionLabel.Font = new Font(Font.FontFamily, 20f, FontStyle.Bold);
        instructionLabel.Padding = new Padding(12, 8, 12, 0);

        detailLabel.Dock = DockStyle.Top;
        detailLabel.Height = 70;
        detailLabel.Padding = new Padding(12, 0, 12, 0);
        detailLabel.ForeColor = Color.FromArgb(70, 70, 80);

        keyboard.Dock = DockStyle.Fill;
        keyboard.BackColor = Color.FromArgb(232, 235, 241);

        statusLabel.Dock = DockStyle.Bottom;
        statusLabel.Height = 70;
        statusLabel.Font = new Font(Font.FontFamily, 14f, FontStyle.Bold);
        statusLabel.Padding = new Padding(12, 6, 12, 0);

        logLabel.Dock = DockStyle.Bottom;
        logLabel.Height = 30;
        logLabel.Padding = new Padding(12, 4, 12, 0);
        logLabel.ForeColor = Color.FromArgb(90, 90, 100);

        buttonBar.Dock = DockStyle.Bottom;
        buttonBar.Height = 56;
        buttonBar.FlowDirection = FlowDirection.RightToLeft;
        buttonBar.Padding = new Padding(8);
        SetupButton(abortButton, "abort");
        SetupButton(skipButton, "skip");
        SetupButton(retryButton, "retry");
        SetupButton(nextButton, "next");
        buttonBar.Controls.Add(abortButton);
        buttonBar.Controls.Add(skipButton);
        buttonBar.Controls.Add(retryButton);
        buttonBar.Controls.Add(nextButton);

        Controls.Add(keyboard);
        Controls.Add(detailLabel);
        Controls.Add(instructionLabel);
        Controls.Add(titleLabel);
        Controls.Add(logLabel);
        Controls.Add(statusLabel);
        Controls.Add(buttonBar);

        clipTimer.Interval = 300;
        clipTimer.Tick += delegate { ApplyClip(); };
        clipTimer.Start();
        FormClosed += delegate
        {
            closed = true;
            ReleaseClip();
            RemoveHook();
            clipTimer.Stop();
        };
        Deactivate += delegate { ReleaseClip(); };
        Activated += delegate { ApplyClip(); };
    }

    void SetupButton(KcNoFocusButton button, string name)
    {
        button.Width = 150;
        button.Height = 38;
        button.Tag = name;
        button.Click += delegate { action = (string)button.Tag; };
    }

    // ---- called from PowerShell ----

    public long NowMs { get { return clock.ElapsedMilliseconds; } }

    public bool IsClosed { get { return closed; } }

    // True while this window has the keyboard focus (keys are swallowed and the cursor can be confined).
    public bool IsForeground { get { return IsHandleCreated && GetForegroundWindow() == Handle; } }

    public void SetButtonTexts(string next, string retry, string skip, string abort)
    {
        nextButton.Text = next;
        retryButton.Text = retry;
        skipButton.Text = skip;
        abortButton.Text = abort;
    }

    public void SetButtons(bool next, bool retry, bool skip)
    {
        nextButton.Visible = next;
        retryButton.Visible = retry;
        skipButton.Visible = skip;
    }

    public void SetTexts(string title, string instruction, string detail)
    {
        titleLabel.Text = title ?? "";
        instructionLabel.Text = instruction ?? "";
        detailLabel.Text = detail ?? "";
    }

    public void SetDetail(string detail)
    {
        detailLabel.Text = detail ?? "";
    }

    // level: 0 = neutral, 1 = ok, 2 = ng, 3 = warning
    public void SetStatus(string text, int level)
    {
        statusLabel.Text = text ?? "";
        switch (level)
        {
            case 1: statusLabel.ForeColor = Color.FromArgb(20, 120, 40); break;
            case 2: statusLabel.ForeColor = Color.FromArgb(190, 30, 30); break;
            case 3: statusLabel.ForeColor = Color.FromArgb(170, 100, 0); break;
            default: statusLabel.ForeColor = Color.FromArgb(40, 40, 50); break;
        }
    }

    public void SetLog(string text)
    {
        logLabel.Text = text ?? "";
    }

    public void SetKeys(int[] pos, double[] x, double[] y, double[] w, double[] h, string[] legends)
    {
        keyboard.SetKeys(pos, x, y, w, h, legends);
    }

    public void SetKeyState(int pos, int state)
    {
        keyboard.SetState(pos, state);
    }

    public void ClearKeyStates()
    {
        keyboard.ClearStates();
    }

    // Returns the pressed button ("next" / "retry" / "skip" / "abort") once, or "".
    public string TakeAction()
    {
        string a = action;
        action = "";
        if (closed && a.Length == 0)
        {
            return "abort";
        }
        return a;
    }

    public KcInputEvent[] TakeEvents()
    {
        lock (sync)
        {
            KcInputEvent[] a = events.ToArray();
            events.Clear();
            return a;
        }
    }

    public void ClearEvents()
    {
        lock (sync)
        {
            events.Clear();
        }
    }

    // Keeps the cursor above the button bar while mouse buttons are tested, so clicks sent by the
    // keyboard land on this window (not on the console or the desktop) and never press our buttons.
    public void Confine(bool on)
    {
        confine = on;
        if (on)
        {
            ApplyClip();
        }
        else
        {
            ReleaseClip();
        }
    }

    // Keeps the Win key of the tested keyboard from opening the Start menu while this window is in front.
    public void MaskWinKey(bool on)
    {
        maskWin = on;
        if (on && hook == IntPtr.Zero)
        {
            hookProc = HookCallback;
            hook = SetWindowsHookEx(WH_KEYBOARD_LL, hookProc, GetModuleHandle(null), 0);
        }
        else if (!on)
        {
            RemoveHook();
        }
    }

    public static string GetDeviceName(long device)
    {
        uint size = 0;
        IntPtr handle = new IntPtr(device);
        GetRawInputDeviceInfo(handle, RIDI_DEVICENAME, null, ref size);
        if (size == 0)
        {
            return "";
        }
        StringBuilder sb = new StringBuilder((int)size + 1);
        GetRawInputDeviceInfo(handle, RIDI_DEVICENAME, sb, ref size);
        return sb.ToString();
    }

    // ---- internals ----

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RAWINPUTDEVICE[] devices = new RAWINPUTDEVICE[2];
        devices[0].UsagePage = 0x01;
        devices[0].Usage = 0x06; // keyboard
        devices[0].Flags = RIDEV_INPUTSINK;
        devices[0].Target = Handle;
        devices[1].UsagePage = 0x01;
        devices[1].Usage = 0x02; // mouse
        devices[1].Flags = RIDEV_INPUTSINK;
        devices[1].Target = Handle;
        if (!RegisterRawInputDevices(devices, 2, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
        {
            throw new InvalidOperationException("RegisterRawInputDevices failed (Win32 error " + Marshal.GetLastWin32Error() + ")");
        }
    }

    protected override void WndProc(ref Message m)
    {
        switch (m.Msg)
        {
            case WM_INPUT:
                ReadRawInput(m.LParam);
                break;
            case WM_KEYDOWN:
            case WM_KEYUP:
            case WM_CHAR:
            case WM_SYSKEYDOWN:
            case WM_SYSKEYUP:
            case WM_SYSCHAR:
                // Swallow keys: Alt must not enter the menu mode, Alt+F4 / Enter / Space do nothing here.
                return;
            case WM_SYSCOMMAND:
                if (((int)m.WParam & 0xFFF0) == SC_KEYMENU)
                {
                    return;
                }
                break;
        }
        base.WndProc(ref m);
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        return true;
    }

    protected override bool ProcessDialogKey(Keys keyData)
    {
        return true;
    }

    void ReadRawInput(IntPtr handle)
    {
        uint headerSize = (uint)(8 + 2 * IntPtr.Size);
        uint size = 0;
        GetRawInputData(handle, RID_INPUT, null, ref size, headerSize);
        if (size == 0)
        {
            return;
        }
        byte[] data = new byte[size];
        if (GetRawInputData(handle, RID_INPUT, data, ref size, headerSize) == unchecked((uint)-1))
        {
            return;
        }
        KcInputEvent e = KcRawInputParser.Parse(data, IntPtr.Size, clock.ElapsedMilliseconds);
        if (e != null)
        {
            lock (sync)
            {
                events.Add(e);
            }
        }
    }

    void ApplyClip()
    {
        if (!confine || closed || !IsHandleCreated || GetForegroundWindow() != Handle)
        {
            return;
        }
        Rectangle client = RectangleToScreen(ClientRectangle);
        RECT r;
        r.Left = client.Left + 4;
        r.Top = client.Top + 4;
        r.Right = client.Right - 4;
        r.Bottom = client.Bottom - buttonBar.Height - 8;
        ClipCursor(ref r);
    }

    void ReleaseClip()
    {
        ClipCursorOff(IntPtr.Zero);
    }

    void RemoveHook()
    {
        if (hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        }
    }

    IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && maskWin && IsHandleCreated && GetForegroundWindow() == Handle)
        {
            int msg = wParam.ToInt32();
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                KBDLLHOOKSTRUCT k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                if ((k.Flags & LLKHF_INJECTED) == 0 && (k.VkCode == 0x5B || k.VkCode == 0x5C))
                {
                    // A key event while Win is held keeps Windows from opening the Start menu on release.
                    keybd_event(VK_MASK, 0, 0, UIntPtr.Zero);
                    keybd_event(VK_MASK, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                }
            }
        }
        return CallNextHookEx(hook, nCode, wParam, lParam);
    }

    protected override void Dispose(bool disposing)
    {
        ReleaseClip();
        RemoveHook();
        base.Dispose(disposing);
    }
}

// A keyboard or mouse known to Raw Input (GetRawInputDeviceList).
public sealed class KcInputDeviceEntry
{
    public long Handle;
    public int Type;   // 0 = mouse, 1 = keyboard, 2 = other HID
}

// Window for tools/input-monitor.ps1: records every keyboard / mouse Raw Input event of every device
// with a microsecond timestamp. The message loop runs on its own STA thread (Launch), so WM_INPUT is
// handled as soon as it arrives and the timestamps are not quantized by the PowerShell polling loop
// (the polling loop of KcInputTestForm handles the queued messages in 15 ms batches).
// Unlike KcInputTestForm it is not TopMost, does not confine the cursor and does not hook the Win key,
// so the user can type into other applications while recording. Keys are swallowed only while this
// window is in front (Ctrl+C / Ctrl+A are let through to copy the log).
// Every public member may be called from another thread; UI updates are marshalled with BeginInvoke.
public sealed class KcInputMonitorForm : Form
{
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE
    {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICELIST
    {
        public IntPtr Device;
        public uint Type;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint GetRawInputData(IntPtr rawInput, uint command, byte[] data, ref uint size, uint headerSize);

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint GetRawInputDeviceList(RAWINPUTDEVICELIST[] list, ref uint count, uint size);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    const int WM_INPUT = 0x00FF;
    const int WM_KEYDOWN = 0x0100;
    const int WM_KEYUP = 0x0101;
    const int WM_CHAR = 0x0102;
    const int WM_SYSKEYDOWN = 0x0104;
    const int WM_SYSKEYUP = 0x0105;
    const int WM_SYSCHAR = 0x0106;
    const int WM_SYSCOMMAND = 0x0112;
    const int SC_KEYMENU = 0xF100;
    const uint RID_INPUT = 0x10000003;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const int MaxLogChars = 400000;

    readonly object sync = new object();
    readonly List<KcInputEvent> events = new List<KcInputEvent>();
    readonly Stopwatch clock = Stopwatch.StartNew();
    readonly Label titleLabel = new Label();
    readonly Label hintLabel = new Label();
    readonly TextBox logBox = new TextBox();
    readonly Label statusLabel = new Label();
    readonly FlowLayoutPanel buttonBar = new FlowLayoutPanel();
    readonly KcNoFocusButton stopButton = new KcNoFocusButton();
    readonly KcNoFocusButton markButton = new KcNoFocusButton();
    readonly KcNoFocusButton clearButton = new KcNoFocusButton();
    volatile bool closed;
    string action = "";

    public KcInputMonitorForm(string title, string stop, string mark, string clear, string hint)
    {
        Text = title ?? "input-monitor";
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(960, 680);
        MinimumSize = new Size(640, 400);
        KeyPreview = false;
        ImeMode = ImeMode.Disable;
        BackColor = Color.FromArgb(246, 247, 250);
        Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 10f);

        titleLabel.Dock = DockStyle.Top;
        titleLabel.Height = 36;
        titleLabel.Font = new Font(Font.FontFamily, 12f, FontStyle.Bold);
        titleLabel.Padding = new Padding(12, 8, 12, 0);
        titleLabel.Text = title ?? "";

        hintLabel.Dock = DockStyle.Top;
        hintLabel.Height = 70;
        hintLabel.Padding = new Padding(12, 0, 12, 0);
        hintLabel.ForeColor = Color.FromArgb(70, 70, 80);
        hintLabel.Text = hint ?? "";

        logBox.Dock = DockStyle.Fill;
        logBox.Multiline = true;
        logBox.ReadOnly = true;
        logBox.ScrollBars = ScrollBars.Vertical;
        logBox.WordWrap = false;
        logBox.HideSelection = false;
        logBox.BackColor = Color.White;
        logBox.Font = new Font(FontFamily.GenericMonospace, 10f);

        statusLabel.Dock = DockStyle.Bottom;
        statusLabel.Height = 48;
        statusLabel.Font = new Font(Font.FontFamily, 11f, FontStyle.Bold);
        statusLabel.Padding = new Padding(12, 6, 12, 0);

        buttonBar.Dock = DockStyle.Bottom;
        buttonBar.Height = 52;
        buttonBar.FlowDirection = FlowDirection.RightToLeft;
        buttonBar.Padding = new Padding(8);
        SetupButton(stopButton, "stop", stop);
        SetupButton(markButton, "mark", mark);
        SetupButton(clearButton, "clear", clear);
        buttonBar.Controls.Add(stopButton);
        buttonBar.Controls.Add(markButton);
        buttonBar.Controls.Add(clearButton);

        Controls.Add(logBox);
        Controls.Add(hintLabel);
        Controls.Add(titleLabel);
        Controls.Add(statusLabel);
        Controls.Add(buttonBar);

        FormClosed += delegate { closed = true; };
    }

    void SetupButton(KcNoFocusButton button, string name, string text)
    {
        button.Width = 150;
        button.Height = 36;
        button.Tag = name;
        button.Text = text ?? name;
        button.Click += delegate
        {
            lock (sync)
            {
                action = (string)button.Tag;
            }
        };
    }

    // ---- called from PowerShell ----

    // Opens the window on its own STA thread and returns once it is shown (or throws after 5 s).
    public static KcInputMonitorForm Launch(string title, string stop, string mark, string clear, string hint)
    {
        KcInputMonitorForm[] box = new KcInputMonitorForm[1];
        Exception[] error = new Exception[1];
        System.Threading.ManualResetEvent ready = new System.Threading.ManualResetEvent(false);
        System.Threading.Thread thread = new System.Threading.Thread(delegate()
        {
            try
            {
                Application.EnableVisualStyles();
                KcInputMonitorForm form = new KcInputMonitorForm(title, stop, mark, clear, hint);
                form.Load += delegate
                {
                    box[0] = form;
                    ready.Set();
                };
                Application.Run(form);
            }
            catch (Exception ex)
            {
                error[0] = ex;
            }
            finally
            {
                ready.Set();
            }
        });
        thread.SetApartmentState(System.Threading.ApartmentState.STA);
        thread.IsBackground = true;
        thread.Name = "input-monitor";
        thread.Start();
        if (!ready.WaitOne(5000) || box[0] == null)
        {
            string reason = error[0] != null ? error[0].Message : "timeout";
            throw new InvalidOperationException("cannot open the monitor window (" + reason + ")");
        }
        return box[0];
    }

    // Keyboards and mice currently known to Raw Input (other HID devices are left out).
    public static KcInputDeviceEntry[] ListDevices()
    {
        uint count = 0;
        uint size = (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICELIST));
        if (GetRawInputDeviceList(null, ref count, size) == unchecked((uint)-1) || count == 0)
        {
            return new KcInputDeviceEntry[0];
        }
        RAWINPUTDEVICELIST[] list = new RAWINPUTDEVICELIST[count];
        uint got = GetRawInputDeviceList(list, ref count, size);
        if (got == unchecked((uint)-1))
        {
            return new KcInputDeviceEntry[0];
        }
        List<KcInputDeviceEntry> result = new List<KcInputDeviceEntry>();
        for (int i = 0; i < got && i < list.Length; i++)
        {
            if (list[i].Type != KcRawInputParser.RIM_TYPEMOUSE && list[i].Type != KcRawInputParser.RIM_TYPEKEYBOARD)
            {
                continue;
            }
            KcInputDeviceEntry d = new KcInputDeviceEntry();
            d.Handle = list[i].Device.ToInt64();
            d.Type = (int)list[i].Type;
            result.Add(d);
        }
        return result.ToArray();
    }

    public long NowUs { get { return clock.ElapsedTicks * 1000000L / Stopwatch.Frequency; } }

    public bool IsClosed { get { return closed; } }

    public bool IsForeground { get { return IsHandleCreated && GetForegroundWindow() == Handle; } }

    // Returns the pressed button ("stop" / "mark" / "clear") once, or "". "stop" once the window is closed.
    public string TakeAction()
    {
        lock (sync)
        {
            string a = action;
            action = "";
            if (closed && a.Length == 0)
            {
                return "stop";
            }
            return a;
        }
    }

    public KcInputEvent[] TakeEvents()
    {
        lock (sync)
        {
            KcInputEvent[] a = events.ToArray();
            events.Clear();
            return a;
        }
    }

    // Appends text (one or more lines separated by CRLF) to the log.
    public void AppendLog(string text)
    {
        Post(delegate { AppendLogCore(text); });
    }

    public void ClearLog()
    {
        Post(delegate { logBox.Clear(); });
    }

    // level: 0 = neutral, 1 = ok, 2 = ng, 3 = warning
    public void SetStatus(string text, int level)
    {
        Post(delegate { SetStatusCore(text, level); });
    }

    public void RequestClose()
    {
        if (closed || !IsHandleCreated)
        {
            return;
        }
        Post(delegate { Close(); });
    }

    // Waits until the window is closed; false on timeout.
    public bool WaitClosed(int timeoutMs)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (!closed && DateTime.UtcNow < deadline)
        {
            System.Threading.Thread.Sleep(50);
        }
        return closed;
    }

    // ---- internals ----

    // Runs an action on the UI thread (directly when called from it or before the handle exists).
    void Post(MethodInvoker work)
    {
        if (closed || IsDisposed)
        {
            return;
        }
        try
        {
            if (IsHandleCreated && InvokeRequired)
            {
                BeginInvoke(work);
            }
            else
            {
                work();
            }
        }
        catch (InvalidOperationException)
        {
            // the window is closing (ObjectDisposedException is a subclass of this one)
        }
    }

    void AppendLogCore(string text)
    {
        if (closed || IsDisposed)
        {
            return;
        }
        if (logBox.TextLength > MaxLogChars)
        {
            string old = logBox.Text;
            int cut = old.IndexOf('\n', old.Length / 2);
            logBox.Text = cut >= 0 ? old.Substring(cut + 1) : "";
        }
        logBox.AppendText((text ?? "") + "\r\n");
    }

    void SetStatusCore(string text, int level)
    {
        statusLabel.Text = text ?? "";
        switch (level)
        {
            case 1: statusLabel.ForeColor = Color.FromArgb(20, 120, 40); break;
            case 2: statusLabel.ForeColor = Color.FromArgb(190, 30, 30); break;
            case 3: statusLabel.ForeColor = Color.FromArgb(170, 100, 0); break;
            default: statusLabel.ForeColor = Color.FromArgb(40, 40, 50); break;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RAWINPUTDEVICE[] devices = new RAWINPUTDEVICE[2];
        devices[0].UsagePage = 0x01;
        devices[0].Usage = 0x06; // keyboard
        devices[0].Flags = RIDEV_INPUTSINK;
        devices[0].Target = Handle;
        devices[1].UsagePage = 0x01;
        devices[1].Usage = 0x02; // mouse
        devices[1].Flags = RIDEV_INPUTSINK;
        devices[1].Target = Handle;
        if (!RegisterRawInputDevices(devices, 2, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
        {
            throw new InvalidOperationException("RegisterRawInputDevices failed (Win32 error " + Marshal.GetLastWin32Error() + ")");
        }
    }

    protected override void WndProc(ref Message m)
    {
        switch (m.Msg)
        {
            case WM_INPUT:
                ReadRawInput(m.LParam);
                break;
            case WM_KEYDOWN:
            case WM_KEYUP:
            case WM_CHAR:
            case WM_SYSKEYDOWN:
            case WM_SYSKEYUP:
            case WM_SYSCHAR:
                // Swallow keys while this window is in front (Alt must not enter the menu mode).
                return;
            case WM_SYSCOMMAND:
                if (((int)m.WParam & 0xFFF0) == SC_KEYMENU)
                {
                    return;
                }
                break;
        }
        base.WndProc(ref m);
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == (Keys.Control | Keys.C) || keyData == (Keys.Control | Keys.A))
        {
            return base.ProcessCmdKey(ref msg, keyData); // copying the log is allowed
        }
        return true;
    }

    protected override bool ProcessDialogKey(Keys keyData)
    {
        return true;
    }

    void ReadRawInput(IntPtr handle)
    {
        long timeUs = NowUs;
        uint headerSize = (uint)(8 + 2 * IntPtr.Size);
        uint size = 0;
        GetRawInputData(handle, RID_INPUT, null, ref size, headerSize);
        if (size == 0)
        {
            return;
        }
        byte[] data = new byte[size];
        if (GetRawInputData(handle, RID_INPUT, data, ref size, headerSize) == unchecked((uint)-1))
        {
            return;
        }
        KcInputEvent e = KcRawInputParser.Parse(data, IntPtr.Size, timeUs / 1000);
        if (e != null)
        {
            e.TimeUs = timeUs;
            lock (sync)
            {
                events.Add(e);
            }
        }
    }
}

// Turns off the console's QuickEdit mode while the test window is open: a click on the console
// would otherwise start a selection that blocks the next console write.
public static class KcConsoleMode
{
    [DllImport("kernel32.dll")]
    static extern IntPtr GetStdHandle(int handle);

    [DllImport("kernel32.dll")]
    static extern bool GetConsoleMode(IntPtr handle, out uint mode);

    [DllImport("kernel32.dll")]
    static extern bool SetConsoleMode(IntPtr handle, uint mode);

    const int STD_INPUT_HANDLE = -10;
    const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    const uint ENABLE_EXTENDED_FLAGS = 0x0080;

    // Returns the previous mode, or -1 when there is no console.
    public static long DisableQuickEdit()
    {
        IntPtr h = GetStdHandle(STD_INPUT_HANDLE);
        uint mode;
        if (h == IntPtr.Zero || h == new IntPtr(-1) || !GetConsoleMode(h, out mode))
        {
            return -1;
        }
        SetConsoleMode(h, (mode & ~ENABLE_QUICK_EDIT_MODE) | ENABLE_EXTENDED_FLAGS);
        return mode;
    }

    public static void Restore(long mode)
    {
        if (mode < 0)
        {
            return;
        }
        IntPtr h = GetStdHandle(STD_INPUT_HANDLE);
        SetConsoleMode(h, (uint)mode);
    }
}
