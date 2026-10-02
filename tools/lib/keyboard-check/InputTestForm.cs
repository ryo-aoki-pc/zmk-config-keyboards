// Windows for the interactive test of tools/keyboard-check.ps1 (KcInputTestForm) and for the
// input event monitor of tools/input-monitor.ps1 (KcInputMonitorForm), built with WPF.
// Records Raw Input (WM_INPUT) per device: keyboard scan codes (layout independent) and
// relative mouse movement before pointer acceleration, so key taps and trackball motion can be
// checked against the expected values, and the timing of the reports can be analyzed.
// The look is defined in Theme.xaml, InputTestWindow.xaml and InputMonitorWindow.xaml (next to this
// file, KcUi.XamlDir), loaded at run time with XamlReader (no x:Class: the named elements are looked up
// here). Loaded by tools/lib/keyboard-check/input-test.ps1 with Add-Type. Both windows live in this one
// file because every Add-Type call makes its own assembly: a second file could not share
// KcInputEvent / KcRawInputParser / KcUi without a duplicate type name.
// Must stay C# 5 compatible (Windows PowerShell 5.1 compiles it with the .NET Framework compiler and
// treats warnings as errors) and ASCII only. User-visible strings are passed in from PowerShell.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;

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

// Helpers shared by both windows: XAML loading, message pumping, DPI, title bar, Raw Input.
public static class KcUi
{
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE
    {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [DllImport("user32.dll")]
    static extern bool SetProcessDPIAware();

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint GetRawInputData(IntPtr rawInput, uint command, byte[] data, ref uint size, uint headerSize);

    public const int WM_INPUT = 0x00FF;
    public const int WM_SYSKEYDOWN = 0x0104;
    public const int WM_SYSKEYUP = 0x0105;
    public const int WM_SYSCHAR = 0x0106;
    public const int WM_SYSCOMMAND = 0x0112;
    public const int SC_KEYMENU = 0xF100;
    const uint RID_INPUT = 0x10000003;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    const int DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19; // Windows 10 before 20H1
    const int DWMWA_CAPTION_COLOR = 35;              // Windows 11
    const int CaptionColor = 0x0020110B;             // COLORREF (0x00BBGGRR) of KcChrome (#0B1120)

    static string xamlDir = "";

    // Directory of Theme.xaml and the window XAML files (set by PowerShell before a window is created).
    public static string XamlDir
    {
        get { return xamlDir; }
        set { xamlDir = value ?? ""; }
    }

    // Makes the process system DPI aware, so the windows are drawn sharp on a high DPI screen instead
    // of being stretched by Windows. WPF does it as well when it creates its first window; calling it
    // before any window exists makes it independent of the order. A failure keeps the old behavior.
    public static void EnsureDpiAware()
    {
        try
        {
            SetProcessDPIAware();
        }
        catch (Exception)
        {
            // not available: Windows stretches the windows as before
        }
    }

    // Processes the queued messages of the calling thread (the WPF counterpart of
    // System.Windows.Forms.Application.DoEvents), for a window driven by a PowerShell polling loop.
    public static void DoEvents()
    {
        DispatcherFrame frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new DispatcherOperationCallback(ExitFrame), frame);
        Dispatcher.PushFrame(frame);
    }

    static object ExitFrame(object frame)
    {
        ((DispatcherFrame)frame).Continue = false;
        return null;
    }

    // Creates a window with the theme (Theme.xaml) and the content of a XAML file. The theme is merged
    // before the content is attached, so implicit styles (scroll bars) and DynamicResource keys resolve.
    public static Window CreateWindow(string contentFile, out FrameworkElement root)
    {
        ResourceDictionary theme = (ResourceDictionary)LoadXaml("Theme.xaml");
        Window window = new Window();
        window.Resources.MergedDictionaries.Add(theme);
        window.Style = (Style)theme["KcWindow"];
        root = (FrameworkElement)LoadXaml(contentFile);
        window.Content = root;
        return window;
    }

    static object LoadXaml(string file)
    {
        string path = System.IO.Path.Combine(xamlDir, file);
        return XamlReader.Parse(System.IO.File.ReadAllText(path, Encoding.UTF8));
    }

    // A named element of the window content (throws when the XAML does not have it).
    public static T Find<T>(FrameworkElement root, string name) where T : class
    {
        T element = root.FindName(name) as T;
        if (element == null)
        {
            throw new InvalidOperationException("element '" + name + "' (" + typeof(T).Name + ") not found in the window XAML");
        }
        return element;
    }

    // Sets a window size that fits the work area of the screen.
    public static void FitSize(Window window, double width, double height, double minWidth, double minHeight)
    {
        Rect area = SystemParameters.WorkArea;
        window.Width = Math.Min(width, area.Width * 0.95);
        window.Height = Math.Min(height, area.Height * 0.95);
        window.MinWidth = Math.Min(minWidth, window.Width);
        window.MinHeight = Math.Min(minHeight, window.Height);
    }

    // Dark title bar (Windows 10 20H1 and later; Windows 11 also takes the header color). Errors are ignored.
    public static void ApplyDarkTitleBar(IntPtr hwnd)
    {
        try
        {
            int on = 1;
            if (DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref on, 4) != 0)
            {
                DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, ref on, 4);
            }
            int color = CaptionColor;
            DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, ref color, 4);
        }
        catch (Exception)
        {
            // older Windows: the title bar keeps the system colors
        }
    }

    // Registers the window for the keyboard and mouse Raw Input, also while it is in the background.
    public static void RegisterRawInput(IntPtr hwnd)
    {
        RAWINPUTDEVICE[] devices = new RAWINPUTDEVICE[2];
        devices[0].UsagePage = 0x01;
        devices[0].Usage = 0x06; // keyboard
        devices[0].Flags = RIDEV_INPUTSINK;
        devices[0].Target = hwnd;
        devices[1].UsagePage = 0x01;
        devices[1].Usage = 0x02; // mouse
        devices[1].Flags = RIDEV_INPUTSINK;
        devices[1].Target = hwnd;
        if (!RegisterRawInputDevices(devices, 2, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
        {
            throw new InvalidOperationException("RegisterRawInputDevices failed (Win32 error " + Marshal.GetLastWin32Error() + ")");
        }
    }

    // The RAWINPUT buffer of a WM_INPUT message (null when it cannot be read).
    public static byte[] GetRawInputBytes(IntPtr handle)
    {
        uint headerSize = (uint)(8 + 2 * IntPtr.Size);
        uint size = 0;
        GetRawInputData(handle, RID_INPUT, null, ref size, headerSize);
        if (size == 0)
        {
            return null;
        }
        byte[] data = new byte[size];
        if (GetRawInputData(handle, RID_INPUT, data, ref size, headerSize) == unchecked((uint)-1))
        {
            return null;
        }
        return data;
    }

    // Saves a picture of an element as PNG (used by the tests; works for a window that is off screen).
    // Must be called on the thread of the window.
    public static void SaveSnapshot(FrameworkElement element, string path)
    {
        element.UpdateLayout();
        int width = (int)Math.Ceiling(element.ActualWidth);
        int height = (int)Math.Ceiling(element.ActualHeight);
        if (width <= 0 || height <= 0)
        {
            throw new InvalidOperationException("the window content has no size (is the window shown?)");
        }
        RenderTargetBitmap bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(element);
        PngBitmapEncoder encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using (System.IO.FileStream stream = System.IO.File.Create(path))
        {
            encoder.Save(stream);
        }
    }

    public static void SetVisible(UIElement element, bool visible)
    {
        element.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
    }

    // Swallows a key while the window is in front: Alt must not enter the menu mode, and Enter / Space /
    // Alt+F4 / F10 of the tested keyboard must do nothing.
    public static void SwallowKey(object sender, KeyEventArgs e)
    {
        e.Handled = true;
    }

    public static void SwallowText(object sender, TextCompositionEventArgs e)
    {
        e.Handled = true;
    }

    // Window procedure filter: Alt combinations must not reach DefWindowProc (menu mode, Alt+F4).
    // Returns true when the message is handled.
    public static bool FilterSystemKeys(int msg, IntPtr wParam)
    {
        switch (msg)
        {
            case WM_SYSKEYDOWN:
            case WM_SYSKEYUP:
            case WM_SYSCHAR:
                return true;
            case WM_SYSCOMMAND:
                return (wParam.ToInt64() & 0xFFF0) == SC_KEYMENU;
        }
        return false;
    }
}

// The window of the interactive test (keyboard-check.ps1). It runs on the PowerShell thread, which
// pumps it with KcUi.DoEvents.
public sealed class KcInputTestForm : IDisposable
{
    public const int StateNormal = 0;
    public const int StateCurrent = 1;
    public const int StatePass = 2;
    public const int StateFail = 3;
    public const int StateSkip = 4;

    sealed class KeyView
    {
        public int Pos;
        public int State;
        public Border Box;
        public TextBlock Legend;
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
    struct POINT
    {
        public int X;
        public int Y;
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

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder data, ref uint size);

    [DllImport("user32.dll")]
    static extern bool ClipCursor(ref RECT rect);

    [DllImport("user32.dll", EntryPoint = "ClipCursor")]
    static extern bool ClipCursorOff(IntPtr rect);

    [DllImport("user32.dll")]
    static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    static extern bool ClientToScreen(IntPtr hwnd, ref POINT point);

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

    const int WM_KEYDOWN = 0x0100;
    const uint RIDI_DEVICENAME = 0x20000007;
    const int WH_KEYBOARD_LL = 13;
    const uint LLKHF_INJECTED = 0x10;
    const byte VK_MASK = 0xE8; // unassigned virtual key, used to keep Win from opening the Start menu
    const uint KEYEVENTF_KEYUP = 0x0002;
    const double KeyUnit = 64;  // canvas units per key unit (the picture is scaled by a Viewbox)
    const double KeyGap = 3;    // half of the gap between two keys, in canvas units
    const double RoomyHeight = 700; // window content height (DIP) from which the texts have full size

    // Theme keys per key state (StateNormal .. StateSkip) and per status level (0 .. 3).
    static readonly string[] KeyFill = { "KcKeyNormalFill", "KcKeyCurrentFill", "KcKeyPassFill", "KcKeyFailFill", "KcKeySkipFill" };
    static readonly string[] KeyEdge = { "KcKeyNormalEdge", "KcKeyCurrentEdge", "KcKeyPassEdge", "KcKeyFailEdge", "KcKeySkipEdge" };
    static readonly string[] KeyInk = { "KcKeyNormalInk", "KcKeyCurrentInk", "KcKeyPassInk", "KcKeyFailInk", "KcKeySkipInk" };
    static readonly string[] StatusTint = { "KcInfoTint", "KcOkTint", "KcNgTint", "KcWarnTint" };
    static readonly string[] StatusEdge = { "KcInfoEdge", "KcOkEdge", "KcNgEdge", "KcWarnEdge" };
    static readonly string[] StatusMark = { "KcInfoMark", "KcOkMark", "KcNgMark", "KcWarnMark" };
    static readonly string[] StatusInk = { "KcInfoInk", "KcOkInk", "KcNgInk", "KcWarnInk" };

    // Status icons drawn in a 24 x 24 circle: i, check, cross, exclamation mark.
    static readonly string[] StatusIconData =
    {
        "M12,11 L12,17 M12,7.4 L12,7.6",
        "M7,12.5 L10.5,16 L17,8.5",
        "M8.5,8.5 L15.5,15.5 M15.5,8.5 L8.5,15.5",
        "M12,6.6 L12,13.4 M12,17.2 L12,17.4"
    };

    readonly object sync = new object();
    readonly List<KcInputEvent> events = new List<KcInputEvent>();
    readonly List<KeyView> keys = new List<KeyView>();
    readonly Stopwatch clock = Stopwatch.StartNew();
    readonly Window window;
    readonly FrameworkElement root;
    readonly TextBlock titleText;
    readonly TextBlock subtitleText;
    readonly Border subtitleChip;
    readonly ProgressBar stepProgress;
    readonly TextBlock instructionText;
    readonly TextBlock detailText;
    readonly Canvas keyboardCanvas;
    readonly FrameworkElement legend;
    readonly TextBlock legendCurrent;
    readonly TextBlock legendPass;
    readonly TextBlock legendFail;
    readonly TextBlock legendSkip;
    readonly Border statusBanner;
    readonly Ellipse statusMark;
    readonly Path statusIcon;
    readonly TextBlock statusText;
    readonly TextBlock logText;
    readonly Border footer;
    readonly Button nextButton;
    readonly Button retryButton;
    readonly Button skipButton;
    readonly Button abortButton;
    readonly DropShadowEffect glow = new DropShadowEffect();
    readonly DispatcherTimer clipTimer = new DispatcherTimer();
    string action = "";
    string statusValue = "";
    int statusLevel = -1;
    int progressValue = -1;
    int progressMax;
    bool closed;
    bool confine;
    bool maskWin;
    IntPtr hwnd = IntPtr.Zero;
    IntPtr hook = IntPtr.Zero;
    LowLevelKeyboardProc hookProc;

    public KcInputTestForm()
    {
        FrameworkElement content;
        window = KcUi.CreateWindow("InputTestWindow.xaml", out content);
        root = content;
        window.Title = "keyboard-check";
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        KcUi.FitSize(window, 1100, 780, 800, 600);
        window.Topmost = true;
        InputMethod.SetIsInputMethodEnabled(window, false);

        titleText = KcUi.Find<TextBlock>(root, "TitleText");
        subtitleText = KcUi.Find<TextBlock>(root, "SubtitleText");
        subtitleChip = KcUi.Find<Border>(root, "SubtitleChip");
        stepProgress = KcUi.Find<ProgressBar>(root, "StepProgress");
        instructionText = KcUi.Find<TextBlock>(root, "InstructionText");
        detailText = KcUi.Find<TextBlock>(root, "DetailText");
        keyboardCanvas = KcUi.Find<Canvas>(root, "KeyboardCanvas");
        legend = KcUi.Find<FrameworkElement>(root, "Legend");
        legendCurrent = KcUi.Find<TextBlock>(root, "LegendCurrent");
        legendPass = KcUi.Find<TextBlock>(root, "LegendPass");
        legendFail = KcUi.Find<TextBlock>(root, "LegendFail");
        legendSkip = KcUi.Find<TextBlock>(root, "LegendSkip");
        statusBanner = KcUi.Find<Border>(root, "StatusBanner");
        statusMark = KcUi.Find<Ellipse>(root, "StatusMark");
        statusIcon = KcUi.Find<Path>(root, "StatusIcon");
        statusText = KcUi.Find<TextBlock>(root, "StatusText");
        logText = KcUi.Find<TextBlock>(root, "LogText");
        footer = KcUi.Find<Border>(root, "Footer");
        nextButton = KcUi.Find<Button>(root, "NextButton");
        retryButton = KcUi.Find<Button>(root, "RetryButton");
        skipButton = KcUi.Find<Button>(root, "SkipButton");
        abortButton = KcUi.Find<Button>(root, "AbortButton");
        SetupButton(nextButton, "next");
        SetupButton(retryButton, "retry");
        SetupButton(skipButton, "skip");
        SetupButton(abortButton, "abort");

        root.SizeChanged += delegate { FitTexts(); };

        glow.Color = (Color)window.FindResource("KcKeyGlowColor");
        glow.BlurRadius = 24;
        glow.ShadowDepth = 0;
        glow.Opacity = 0.9;

        window.PreviewKeyDown += KcUi.SwallowKey;
        window.PreviewKeyUp += KcUi.SwallowKey;
        window.PreviewTextInput += KcUi.SwallowText;
        window.SourceInitialized += OnSourceInitialized;
        window.Closed += delegate
        {
            closed = true;
            ReleaseClip();
            RemoveHook();
            clipTimer.Stop();
        };
        window.Deactivated += delegate { ReleaseClip(); };
        window.Activated += delegate { ApplyClip(); };
        clipTimer.Interval = TimeSpan.FromMilliseconds(300);
        clipTimer.Tick += delegate { ApplyClip(); };
        clipTimer.Start();
    }

    void SetupButton(Button button, string name)
    {
        button.Click += delegate { action = name; };
    }

    // ---- called from PowerShell ----

    // The WPF window (the tests move it off screen before showing it).
    public Window Window { get { return window; } }

    public long NowMs { get { return clock.ElapsedMilliseconds; } }

    public bool IsClosed { get { return closed; } }

    // True while this window has the keyboard focus (keys are swallowed and the cursor can be confined).
    public bool IsForeground { get { return hwnd != IntPtr.Zero && GetForegroundWindow() == hwnd; } }

    public void Show()
    {
        window.Show();
    }

    public void Activate()
    {
        window.Activate();
    }

    public void Close()
    {
        if (!closed && hwnd != IntPtr.Zero)
        {
            window.Close();
        }
    }

    public void SetButtonTexts(string next, string retry, string skip, string abort)
    {
        nextButton.Content = next ?? "";
        retryButton.Content = retry ?? "";
        skipButton.Content = skip ?? "";
        abortButton.Content = abort ?? "";
    }

    public void SetButtons(bool next, bool retry, bool skip)
    {
        KcUi.SetVisible(nextButton, next);
        KcUi.SetVisible(retryButton, retry);
        KcUi.SetVisible(skipButton, skip);
    }

    // Starts a new step. Also hides the progress bar of the header: call SetProgress after SetTexts.
    public void SetTexts(string title, string instruction, string detail)
    {
        titleText.Text = title ?? "";
        instructionText.Text = instruction ?? "";
        SetDetail(detail);
        SetProgress(0, 0);
    }

    public void SetDetail(string detail)
    {
        detailText.Text = detail ?? "";
        KcUi.SetVisible(detailText, detailText.Text.Length > 0);
    }

    // Name shown at the right of the header (the keyboard under test).
    public void SetSubtitle(string text)
    {
        subtitleText.Text = text ?? "";
        KcUi.SetVisible(subtitleChip, subtitleText.Text.Length > 0);
    }

    // Progress of the current step (max <= 0 hides it). Does nothing when nothing changed.
    public void SetProgress(int value, int max)
    {
        if (max <= 0)
        {
            progressMax = 0;
            stepProgress.Visibility = Visibility.Hidden;
            return;
        }
        int v = Math.Max(0, Math.Min(value, max));
        if (max == progressMax && v == progressValue)
        {
            return;
        }
        progressMax = max;
        progressValue = v;
        stepProgress.Maximum = max;
        stepProgress.Value = v;
        stepProgress.Visibility = Visibility.Visible;
    }

    // level: 0 = neutral, 1 = ok, 2 = ng, 3 = warning. Does nothing when nothing changed (the
    // countdowns call it on every pump).
    public void SetStatus(string text, int level)
    {
        text = text ?? "";
        if (level < 0 || level > 3)
        {
            level = 0;
        }
        if (text == statusValue && level == statusLevel)
        {
            return;
        }
        statusValue = text;
        statusLevel = level;
        statusText.Text = text;
        if (text.Length == 0)
        {
            statusBanner.Visibility = Visibility.Hidden;
            return;
        }
        statusBanner.Background = ThemeBrush(StatusTint[level]);
        statusBanner.BorderBrush = ThemeBrush(StatusEdge[level]);
        statusMark.Fill = ThemeBrush(StatusMark[level]);
        statusText.Foreground = ThemeBrush(StatusInk[level]);
        statusIcon.Data = Geometry.Parse(StatusIconData[level]);
        statusBanner.Visibility = Visibility.Visible;
    }

    public void SetLog(string text)
    {
        logText.Text = text ?? "";
        KcUi.SetVisible(logText, logText.Text.Length > 0);
    }

    // Texts of the color legend below the keyboard picture (current key, passed, wrong key, skipped).
    public void SetKeyLegendTexts(string current, string pass, string fail, string skip)
    {
        legendCurrent.Text = current ?? "";
        legendPass.Text = pass ?? "";
        legendFail.Text = fail ?? "";
        legendSkip.Text = skip ?? "";
        KcUi.SetVisible(legend, legendCurrent.Text.Length > 0);
    }

    // Keys of the physical layout (x / y / w / h in key units).
    public void SetKeys(int[] pos, double[] x, double[] y, double[] w, double[] h, string[] legends)
    {
        keys.Clear();
        keyboardCanvas.Children.Clear();
        if (pos.Length == 0)
        {
            keyboardCanvas.Width = 0;
            keyboardCanvas.Height = 0;
            return;
        }
        double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
        for (int i = 0; i < pos.Length; i++)
        {
            minX = Math.Min(minX, x[i]);
            minY = Math.Min(minY, y[i]);
            maxX = Math.Max(maxX, x[i] + w[i]);
            maxY = Math.Max(maxY, y[i] + h[i]);
        }
        keyboardCanvas.Width = Math.Max(maxX - minX, 1) * KeyUnit;
        keyboardCanvas.Height = Math.Max(maxY - minY, 1) * KeyUnit;
        for (int i = 0; i < pos.Length; i++)
        {
            TextBlock text = new TextBlock();
            text.Text = legends[i] ?? "";
            text.FontSize = 19;
            text.FontWeight = FontWeights.SemiBold;
            text.TextAlignment = TextAlignment.Center;
            // long legends shrink to fit the key, short ones keep the font size
            Viewbox fit = new Viewbox();
            fit.Stretch = Stretch.Uniform;
            fit.StretchDirection = StretchDirection.DownOnly;
            fit.Margin = new Thickness(7, 5, 7, 5);
            fit.Child = text;
            Border box = new Border();
            box.Width = Math.Max(w[i] * KeyUnit - 2 * KeyGap, 1);
            box.Height = Math.Max(h[i] * KeyUnit - 2 * KeyGap, 1);
            box.CornerRadius = new CornerRadius(10);
            box.Child = fit;
            Canvas.SetLeft(box, (x[i] - minX) * KeyUnit + KeyGap);
            Canvas.SetTop(box, (y[i] - minY) * KeyUnit + KeyGap);
            keyboardCanvas.Children.Add(box);
            KeyView k = new KeyView();
            k.Pos = pos[i];
            k.Box = box;
            k.Legend = text;
            keys.Add(k);
            Paint(k);
        }
    }

    public void SetKeyState(int pos, int state)
    {
        foreach (KeyView k in keys)
        {
            if (k.Pos == pos)
            {
                k.State = state;
                Paint(k);
            }
        }
    }

    public void ClearKeyStates()
    {
        foreach (KeyView k in keys)
        {
            k.State = StateNormal;
            Paint(k);
        }
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

    // Saves a picture of the window content as PNG (for the tests).
    public void SaveSnapshot(string path)
    {
        KcUi.SaveSnapshot(root, path);
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

    public void Dispose()
    {
        ReleaseClip();
        RemoveHook();
        clipTimer.Stop();
        Close();
    }

    // ---- internals ----

    Brush ThemeBrush(string key)
    {
        return (Brush)window.FindResource(key);
    }

    void Paint(KeyView k)
    {
        int s = k.State >= 0 && k.State < KeyFill.Length ? k.State : StateNormal;
        k.Box.Background = ThemeBrush(KeyFill[s]);
        k.Box.BorderBrush = ThemeBrush(KeyEdge[s]);
        k.Box.BorderThickness = new Thickness(s == StateCurrent ? 3 : 1.5);
        k.Box.Effect = s == StateCurrent ? glow : null;
        Panel.SetZIndex(k.Box, s == StateCurrent ? 1 : 0);
        k.Legend.Foreground = ThemeBrush(KeyInk[s]);
    }

    // On a low window (small screen, high scaling) the long instructions would push the keyboard
    // picture out: the texts shrink with the height (down to 72 %).
    void FitTexts()
    {
        double f = Math.Max(0.72, Math.Min(1.0, root.ActualHeight / RoomyHeight));
        instructionText.FontSize = 26 * f;
        detailText.FontSize = 15 * f;
        statusText.FontSize = 16 * f;
    }

    void OnSourceInitialized(object sender, EventArgs e)
    {
        hwnd = new WindowInteropHelper(window).Handle;
        KcUi.ApplyDarkTitleBar(hwnd);
        HwndSource.FromHwnd(hwnd).AddHook(WndProc);
        KcUi.RegisterRawInput(hwnd);
    }

    IntPtr WndProc(IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == KcUi.WM_INPUT)
        {
            ReadRawInput(lParam);
        }
        else if (KcUi.FilterSystemKeys(msg, wParam))
        {
            handled = true;
        }
        return IntPtr.Zero;
    }

    void ReadRawInput(IntPtr handle)
    {
        KcInputEvent e = KcRawInputParser.Parse(KcUi.GetRawInputBytes(handle), IntPtr.Size, clock.ElapsedMilliseconds);
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
        if (!confine || closed || hwnd == IntPtr.Zero || GetForegroundWindow() != hwnd)
        {
            return;
        }
        RECT client;
        if (!GetClientRect(hwnd, out client))
        {
            return;
        }
        POINT origin;
        origin.X = 0;
        origin.Y = 0;
        if (!ClientToScreen(hwnd, ref origin))
        {
            return;
        }
        // screen pixels, like ClipCursor (PointToScreen converts from device independent units)
        int bottom = origin.Y + client.Bottom;
        try
        {
            bottom = (int)footer.PointToScreen(new Point(0, 0)).Y;
        }
        catch (InvalidOperationException)
        {
            // not laid out yet: the whole client area
        }
        RECT r;
        r.Left = origin.X + 4;
        r.Top = origin.Y + 4;
        r.Right = origin.X + client.Right - 4;
        r.Bottom = bottom - 8;
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
        if (nCode >= 0 && maskWin && hwnd != IntPtr.Zero && GetForegroundWindow() == hwnd)
        {
            int msg = wParam.ToInt32();
            if (msg == WM_KEYDOWN || msg == KcUi.WM_SYSKEYDOWN)
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
}

// A keyboard or mouse known to Raw Input (GetRawInputDeviceList).
public sealed class KcInputDeviceEntry
{
    public long Handle;
    public int Type;   // 0 = mouse, 1 = keyboard, 2 = other HID
}

// Window for tools/input-monitor.ps1: records every keyboard / mouse Raw Input event of every device
// with a microsecond timestamp. The window runs on its own STA thread (Launch), so WM_INPUT is
// handled as soon as it arrives and the timestamps are not quantized by the PowerShell polling loop
// (the polling loop of KcInputTestForm handles the queued messages in 15 ms batches).
// Unlike KcInputTestForm it is not topmost, does not confine the cursor and does not hook the Win key,
// so the user can type into other applications while recording. Keys are swallowed only while this
// window is in front (Ctrl+C / Ctrl+A are let through to copy the log).
// Every public member may be called from another thread; UI updates are marshalled to the window thread.
public sealed class KcInputMonitorForm : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICELIST
    {
        public IntPtr Device;
        public uint Type;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint GetRawInputDeviceList(RAWINPUTDEVICELIST[] list, ref uint count, uint size);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    const int MaxLogChars = 400000;

    // Theme keys of the status text per level (0 = neutral, 1 = ok, 2 = ng, 3 = warning).
    static readonly string[] StatusInk = { "KcTextMuted", "KcOkMark", "KcNgMark", "KcWarnMark" };

    readonly object sync = new object();
    readonly List<KcInputEvent> events = new List<KcInputEvent>();
    readonly Stopwatch clock = Stopwatch.StartNew();
    readonly Window window;
    readonly FrameworkElement root;
    readonly TextBlock titleText;
    readonly TextBlock hintText;
    readonly TextBox logBox;
    readonly TextBlock statusText;
    readonly Button stopButton;
    readonly Button markButton;
    readonly Button clearButton;
    volatile bool closed;
    string action = "";
    IntPtr hwnd = IntPtr.Zero;
    int logLength;

    public KcInputMonitorForm(string title, string stop, string mark, string clear, string hint)
    {
        FrameworkElement content;
        window = KcUi.CreateWindow("InputMonitorWindow.xaml", out content);
        root = content;
        window.Title = title ?? "input-monitor";
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        KcUi.FitSize(window, 960, 680, 640, 400);
        InputMethod.SetIsInputMethodEnabled(window, false);

        titleText = KcUi.Find<TextBlock>(root, "TitleText");
        hintText = KcUi.Find<TextBlock>(root, "HintText");
        logBox = KcUi.Find<TextBox>(root, "LogBox");
        statusText = KcUi.Find<TextBlock>(root, "StatusText");
        stopButton = KcUi.Find<Button>(root, "StopButton");
        markButton = KcUi.Find<Button>(root, "MarkButton");
        clearButton = KcUi.Find<Button>(root, "ClearButton");
        titleText.Text = title ?? "";
        hintText.Text = hint ?? "";
        SetupButton(stopButton, "stop", stop);
        SetupButton(markButton, "mark", mark);
        SetupButton(clearButton, "clear", clear);

        window.PreviewKeyDown += SwallowKeyButCopy;
        window.PreviewKeyUp += SwallowKeyButCopy;
        window.PreviewTextInput += KcUi.SwallowText;
        window.SourceInitialized += OnSourceInitialized;
        window.Closed += delegate { closed = true; };
    }

    void SetupButton(Button button, string name, string text)
    {
        button.Content = text ?? name;
        button.Click += delegate
        {
            lock (sync)
            {
                action = name;
            }
        };
    }

    // ---- called from PowerShell ----

    // Opens the window on its own STA thread and returns once it is shown (or throws after 15 s).
    public static KcInputMonitorForm Launch(string title, string stop, string mark, string clear, string hint)
    {
        KcInputMonitorForm[] box = new KcInputMonitorForm[1];
        Exception[] error = new Exception[1];
        ManualResetEvent ready = new ManualResetEvent(false);
        Thread thread = new Thread(delegate()
        {
            try
            {
                KcUi.EnsureDpiAware();
                Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
                // An exception in a UI callback must not end the process (this is a background thread).
                dispatcher.UnhandledException += delegate(object sender, DispatcherUnhandledExceptionEventArgs e)
                {
                    e.Handled = true;
                };
                KcInputMonitorForm form = new KcInputMonitorForm(title, stop, mark, clear, hint);
                form.window.Loaded += delegate
                {
                    box[0] = form;
                    ready.Set();
                };
                form.window.Closed += delegate
                {
                    dispatcher.BeginInvokeShutdown(DispatcherPriority.Background);
                };
                form.window.Show();
                Dispatcher.Run();
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
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Name = "input-monitor";
        thread.Start();
        if (!ready.WaitOne(15000) || box[0] == null)
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

    // The WPF window (the tests show it off screen; use it on the window thread only).
    public Window Window { get { return window; } }

    public long NowUs { get { return clock.ElapsedTicks * 1000000L / Stopwatch.Frequency; } }

    public bool IsClosed { get { return closed; } }

    public bool IsForeground { get { return hwnd != IntPtr.Zero && GetForegroundWindow() == hwnd; } }

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
        Post(delegate
        {
            logBox.Clear();
            logLength = 0;
        });
    }

    // level: 0 = neutral, 1 = ok, 2 = ng, 3 = warning
    public void SetStatus(string text, int level)
    {
        Post(delegate { SetStatusCore(text, level); });
    }

    public void RequestClose()
    {
        if (closed || hwnd == IntPtr.Zero)
        {
            return;
        }
        Post(delegate { window.Close(); });
    }

    // Waits until the window is closed; false on timeout.
    public bool WaitClosed(int timeoutMs)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (!closed && DateTime.UtcNow < deadline)
        {
            Thread.Sleep(50);
        }
        return closed;
    }

    // Saves a picture of the window content as PNG (for the tests; call it on the window thread).
    public void SaveSnapshot(string path)
    {
        KcUi.SaveSnapshot(root, path);
    }

    public void Dispose()
    {
        RequestClose();
    }

    // ---- internals ----

    // Runs an action on the window thread (directly when called from it).
    void Post(Action work)
    {
        if (closed)
        {
            return;
        }
        try
        {
            Dispatcher dispatcher = window.Dispatcher;
            if (dispatcher.CheckAccess())
            {
                work();
            }
            else
            {
                dispatcher.BeginInvoke(DispatcherPriority.Normal, work);
            }
        }
        catch (InvalidOperationException)
        {
            // the window is closing
        }
    }

    void AppendLogCore(string text)
    {
        if (closed)
        {
            return;
        }
        string line = (text ?? "") + "\r\n";
        if (logLength + line.Length > MaxLogChars)
        {
            string old = logBox.Text;
            int cut = old.IndexOf('\n', old.Length / 2);
            string kept = cut >= 0 ? old.Substring(cut + 1) : "";
            logBox.Text = kept;
            logLength = kept.Length;
        }
        // follow the end of the log only while it is shown (so a selection to copy is not scrolled away)
        bool atEnd = logBox.VerticalOffset + logBox.ViewportHeight >= logBox.ExtentHeight - 2;
        logBox.AppendText(line);
        logLength += line.Length;
        if (atEnd)
        {
            logBox.ScrollToEnd();
        }
    }

    void SetStatusCore(string text, int level)
    {
        if (level < 0 || level > 3)
        {
            level = 0;
        }
        statusText.Text = text ?? "";
        statusText.Foreground = (Brush)window.FindResource(StatusInk[level]);
    }

    // Swallows the keys while this window is in front; Ctrl+C / Ctrl+A still reach the log to copy it.
    static void SwallowKeyButCopy(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers == ModifierKeys.Control && (e.Key == Key.C || e.Key == Key.A))
        {
            return;
        }
        e.Handled = true;
    }

    void OnSourceInitialized(object sender, EventArgs e)
    {
        hwnd = new WindowInteropHelper(window).Handle;
        KcUi.ApplyDarkTitleBar(hwnd);
        HwndSource.FromHwnd(hwnd).AddHook(WndProc);
        KcUi.RegisterRawInput(hwnd);
    }

    IntPtr WndProc(IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == KcUi.WM_INPUT)
        {
            ReadRawInput(lParam);
        }
        else if (KcUi.FilterSystemKeys(msg, wParam))
        {
            handled = true;
        }
        return IntPtr.Zero;
    }

    void ReadRawInput(IntPtr handle)
    {
        long timeUs = NowUs;
        KcInputEvent e = KcRawInputParser.Parse(KcUi.GetRawInputBytes(handle), IntPtr.Size, timeUs / 1000);
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
