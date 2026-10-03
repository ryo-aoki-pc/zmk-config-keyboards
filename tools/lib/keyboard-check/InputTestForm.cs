// Windows for the interactive test of tools/keyboard-check.ps1 (KcInputTestForm), the layer trace of
// keyboard-check.ps1 -Mode Trace (KcLayerTraceForm), the input event monitor of tools/input-monitor.ps1
// (KcInputMonitorForm) and the flashing tool tools/flash.ps1 (KcFlashForm), built with WPF.
// Records Raw Input (WM_INPUT) per device: keyboard scan codes (layout independent) and
// relative mouse movement before pointer acceleration, so key taps and trackball motion can be
// checked against the expected values, and the timing of the reports can be analyzed.
// The look is defined in Theme.xaml, InputTestWindow.xaml, LayerTraceWindow.xaml, InputMonitorWindow.xaml and
// FlashWindow.xaml (next to this file, KcUi.XamlDir), loaded at run time with XamlReader (no x:Class: the
// named elements are looked up here). Loaded by tools/lib/keyboard-check/input-test.ps1 with Add-Type. The windows live in this one
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

// Drawing helpers shared by the windows: theme brushes, chips, arrows and key caps. The brushes are
// looked up in the resources of the window (Theme.xaml).
public static class KcDraw
{
    // States of the key caps (Caps).
    public const int CapNeutral = 0;
    public const int CapOk = 1;
    public const int CapNg = 2;
    public const int CapPending = 3;

    static readonly string[] CapFill = { "KcCapFill", "KcOkTint", "KcNgTint", "KcKeySkipFill" };
    static readonly string[] CapEdge = { "KcCapEdge", "KcOkEdge", "KcNgEdge", "KcKeySkipEdge" };
    static readonly string[] CapInk = { "KcCapInk", "KcOkInk", "KcNgInk", "KcKeySkipInk" };

    // Theme keys per status level (0 = info, 1 = ok, 2 = ng, 3 = warning) of the banners.
    public static readonly string[] StatusTint = { "KcInfoTint", "KcOkTint", "KcNgTint", "KcWarnTint" };
    public static readonly string[] StatusEdge = { "KcInfoEdge", "KcOkEdge", "KcNgEdge", "KcWarnEdge" };
    public static readonly string[] StatusMark = { "KcInfoMark", "KcOkMark", "KcNgMark", "KcWarnMark" };
    public static readonly string[] StatusInk = { "KcInfoInk", "KcOkInk", "KcNgInk", "KcWarnInk" };

    // Status icons drawn in a 24 x 24 circle: i, check, cross, exclamation mark.
    public static readonly string[] StatusIconData =
    {
        "M12,11 L12,17 M12,7.4 L12,7.6",
        "M7,12.5 L10.5,16 L17,8.5",
        "M8.5,8.5 L15.5,15.5 M15.5,8.5 L8.5,15.5",
        "M12,6.6 L12,13.4 M12,17.2 L12,17.4"
    };

    // Arrow between chips (12 x 10).
    const string ArrowData = "M0,5 L11,5 M7,1 L11,5 L7,9";

    public static Brush Res(FrameworkElement owner, string key)
    {
        return (Brush)owner.FindResource(key);
    }

    public static int Clamp(int v, int min, int max)
    {
        return Math.Max(min, Math.Min(max, v));
    }

    // A rounded chip with an optional small caption above the text.
    public static Border Chip(FrameworkElement owner, string caption, string text, string fill, string edge, string ink, double fontSize)
    {
        StackPanel stack = new StackPanel();
        Brush inkBrush = Res(owner, ink);
        if (!string.IsNullOrEmpty(caption))
        {
            TextBlock c = new TextBlock();
            c.Text = caption;
            c.FontSize = 11;
            c.Foreground = inkBrush;
            c.Opacity = 0.75;
            stack.Children.Add(c);
        }
        TextBlock t = new TextBlock();
        t.Text = text ?? "";
        t.FontSize = fontSize;
        t.FontWeight = FontWeights.SemiBold;
        t.Foreground = inkBrush;
        stack.Children.Add(t);
        Border chip = new Border();
        chip.CornerRadius = new CornerRadius(8);
        chip.Padding = new Thickness(11, 3, 11, 4);
        chip.BorderThickness = new Thickness(1.5);
        chip.Background = Res(owner, fill);
        chip.BorderBrush = Res(owner, edge);
        chip.VerticalAlignment = VerticalAlignment.Center;
        chip.Child = stack;
        return chip;
    }

    public static Path Arrow(FrameworkElement owner)
    {
        Path arrow = new Path();
        arrow.Data = Geometry.Parse(ArrowData);
        arrow.Stroke = Res(owner, "KcLayerArrow");
        arrow.StrokeThickness = 2;
        arrow.StrokeStartLineCap = PenLineCap.Round;
        arrow.StrokeEndLineCap = PenLineCap.Round;
        arrow.StrokeLineJoin = PenLineJoin.Round;
        arrow.Width = 12;
        arrow.Height = 10;
        arrow.Margin = new Thickness(8, 0, 8, 0);
        arrow.VerticalAlignment = VerticalAlignment.Center;
        return arrow;
    }

    // Appends the items and their states to a signature (to skip redrawing when nothing changed).
    public static void AppendSignature(StringBuilder sig, string[] items, int[] states)
    {
        sig.Append('#');
        for (int i = 0; i < items.Length; i++)
        {
            sig.Append(items[i]).Append(':').Append(i < states.Length ? states[i] : 0).Append(';');
        }
    }

    // Fills a panel with key caps (states: CapNeutral .. CapPending); emptyText when there is none.
    public static void Caps(FrameworkElement owner, Panel panel, string[] caps, int[] states, string emptyText)
    {
        panel.Children.Clear();
        if (caps.Length == 0 && !string.IsNullOrEmpty(emptyText))
        {
            TextBlock none = new TextBlock();
            none.Text = emptyText;
            none.FontSize = 14;
            none.Foreground = Res(owner, "KcTextFaint");
            none.VerticalAlignment = VerticalAlignment.Center;
            panel.Children.Add(none);
            return;
        }
        for (int i = 0; i < caps.Length; i++)
        {
            int s = i < states.Length ? Clamp(states[i], 0, CapFill.Length - 1) : CapNeutral;
            TextBlock t = new TextBlock();
            t.Text = caps[i] ?? "";
            t.FontSize = 15;
            t.FontWeight = FontWeights.SemiBold;
            t.Foreground = Res(owner, CapInk[s]);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            Border cap = new Border();
            cap.MinWidth = 38;
            cap.CornerRadius = new CornerRadius(7);
            cap.Padding = new Thickness(10, 4, 10, 5);
            cap.Margin = new Thickness(0, 2, 6, 2);
            cap.BorderThickness = new Thickness(1.5, 1.5, 1.5, 3.5);
            cap.Background = Res(owner, CapFill[s]);
            cap.BorderBrush = Res(owner, CapEdge[s]);
            cap.Child = t;
            panel.Children.Add(cap);
        }
    }
}

// The keyboard picture of the windows: one rounded key per physical key, colored by its state, with a
// legend (one or two lines) and an optional badge at the top right corner. The canvas is scaled by a Viewbox.
public sealed class KcKeyboardView
{
    public const int StateNormal = 0;
    public const int StateCurrent = 1;
    public const int StatePass = 2;
    public const int StateFail = 3;
    public const int StateSkip = 4;
    public const int StateHold = 5;   // a layer key held
    public const int StateMod = 6;    // a modifier held
    public const int StateDanger = 7; // must not be pressed (bootloader, reset, Bluetooth)
    public const int StateCombo = 8;  // pressed together with other keys

    const double KeyUnit = 64;  // canvas units per key unit
    const double KeyGap = 3;    // half of the gap between two keys, in canvas units
    const double BadgeSize = 26;

    // Theme keys per key state (StateNormal .. StateCombo).
    static readonly string[] KeyFill = { "KcKeyNormalFill", "KcKeyCurrentFill", "KcKeyPassFill", "KcKeyFailFill", "KcKeySkipFill",
                                         "KcKeyHoldFill", "KcKeyModFill", "KcKeyDangerFill", "KcKeyComboFill" };
    static readonly string[] KeyEdge = { "KcKeyNormalEdge", "KcKeyCurrentEdge", "KcKeyPassEdge", "KcKeyFailEdge", "KcKeySkipEdge",
                                         "KcKeyHoldEdge", "KcKeyModEdge", "KcKeyDangerEdge", "KcKeyComboEdge" };
    static readonly string[] KeyInk = { "KcKeyNormalInk", "KcKeyCurrentInk", "KcKeyPassInk", "KcKeyFailInk", "KcKeySkipInk",
                                        "KcKeyHoldInk", "KcKeyModInk", "KcKeyDangerInk", "KcKeyComboInk" };

    sealed class KeyView
    {
        public int Pos;
        public int State;
        public Border Box;
        public TextBlock Legend;
        public string BaseLegend;
        public Border Badge;
        public TextBlock BadgeText;
    }

    readonly FrameworkElement owner;
    readonly Canvas canvas;
    readonly List<KeyView> keys = new List<KeyView>();
    readonly DropShadowEffect glow = new DropShadowEffect();

    public KcKeyboardView(FrameworkElement owner, Canvas canvas)
    {
        this.owner = owner;
        this.canvas = canvas;
        glow.Color = (Color)owner.FindResource("KcKeyGlowColor");
        glow.BlurRadius = 24;
        glow.ShadowDepth = 0;
        glow.Opacity = 0.9;
    }

    // Keys of the physical layout (x / y / w / h in key units).
    public void SetKeys(int[] pos, double[] x, double[] y, double[] w, double[] h, string[] legends)
    {
        keys.Clear();
        canvas.Children.Clear();
        if (pos.Length == 0)
        {
            canvas.Width = 0;
            canvas.Height = 0;
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
        canvas.Width = Math.Max(maxX - minX, 1) * KeyUnit;
        canvas.Height = Math.Max(maxY - minY, 1) * KeyUnit;
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
            double left = (x[i] - minX) * KeyUnit + KeyGap;
            double top = (y[i] - minY) * KeyUnit + KeyGap;
            Canvas.SetLeft(box, left);
            Canvas.SetTop(box, top);
            canvas.Children.Add(box);
            // badge at the top right corner: order of the presses or the tap count
            TextBlock badgeText = new TextBlock();
            badgeText.FontSize = 15;
            badgeText.FontWeight = FontWeights.Bold;
            badgeText.HorizontalAlignment = HorizontalAlignment.Center;
            badgeText.VerticalAlignment = VerticalAlignment.Center;
            badgeText.Foreground = KcDraw.Res(owner, "KcBadgeInk");
            Border badge = new Border();
            badge.MinWidth = BadgeSize;
            badge.Height = BadgeSize;
            badge.Padding = new Thickness(5, 0, 5, 0);
            badge.CornerRadius = new CornerRadius(BadgeSize / 2);
            badge.Background = KcDraw.Res(owner, "KcBadgeFill");
            badge.BorderBrush = KcDraw.Res(owner, "KcBg");
            badge.BorderThickness = new Thickness(2);
            badge.Child = badgeText;
            badge.Visibility = Visibility.Collapsed;
            Canvas.SetLeft(badge, left + box.Width - BadgeSize + 6);
            Canvas.SetTop(badge, top - 8);
            Panel.SetZIndex(badge, 3);
            canvas.Children.Add(badge);
            KeyView k = new KeyView();
            k.Pos = pos[i];
            k.Box = box;
            k.Legend = text;
            k.BaseLegend = text.Text;
            k.Badge = badge;
            k.BadgeText = badgeText;
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

    // Legends of the keys of a layer (pos[i] gets legends[i]; a line break makes two lines).
    public void SetKeyLegends(int[] pos, string[] legends)
    {
        for (int i = 0; i < pos.Length && i < legends.Length; i++)
        {
            foreach (KeyView k in keys)
            {
                if (k.Pos == pos[i])
                {
                    k.Legend.Text = legends[i] ?? "";
                }
            }
        }
    }

    // Back to the legends given to SetKeys (the BASE layer).
    public void ResetKeyLegends()
    {
        foreach (KeyView k in keys)
        {
            k.Legend.Text = k.BaseLegend;
        }
    }

    // Small badge on a key ("" hides it).
    public void SetKeyBadge(int pos, string text)
    {
        foreach (KeyView k in keys)
        {
            if (k.Pos == pos)
            {
                k.BadgeText.Text = text ?? "";
                KcUi.SetVisible(k.Badge, k.BadgeText.Text.Length > 0);
            }
        }
    }

    public void ClearKeyBadges()
    {
        foreach (KeyView k in keys)
        {
            k.BadgeText.Text = "";
            k.Badge.Visibility = Visibility.Collapsed;
        }
    }

    void Paint(KeyView k)
    {
        int s = k.State >= 0 && k.State < KeyFill.Length ? k.State : StateNormal;
        k.Box.Background = KcDraw.Res(owner, KeyFill[s]);
        k.Box.BorderBrush = KcDraw.Res(owner, KeyEdge[s]);
        bool strong = s == StateCurrent || s == StateHold || s == StateMod || s == StateCombo;
        k.Box.BorderThickness = new Thickness(s == StateCurrent ? 3 : (strong ? 2.5 : 1.5));
        k.Box.Effect = s == StateCurrent ? glow : null;
        Panel.SetZIndex(k.Box, s == StateCurrent ? 1 : 0);
        k.Legend.Foreground = KcDraw.Res(owner, KeyInk[s]);
    }
}

// Keeps the Win key of the tested keyboard from opening the Start menu while a window is in front (a
// low level keyboard hook). handle returns the window to guard, or IntPtr.Zero to let everything pass.
public sealed class KcWinKeyMask : IDisposable
{
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
    const int WH_KEYBOARD_LL = 13;
    const uint LLKHF_INJECTED = 0x10;
    const byte VK_MASK = 0xE8; // unassigned virtual key, used to keep Win from opening the Start menu
    const uint KEYEVENTF_KEYUP = 0x0002;

    readonly Func<IntPtr> handle;
    IntPtr hook = IntPtr.Zero;
    LowLevelKeyboardProc proc;

    public KcWinKeyMask(Func<IntPtr> handle)
    {
        this.handle = handle;
    }

    public void Enable(bool on)
    {
        if (on && hook == IntPtr.Zero)
        {
            proc = Callback;
            hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
        }
        else if (!on && hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        }
    }

    public void Dispose()
    {
        Enable(false);
    }

    IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        IntPtr h = handle();
        if (nCode >= 0 && h != IntPtr.Zero && GetForegroundWindow() == h)
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

// The window of the interactive test (keyboard-check.ps1). It runs on the PowerShell thread, which
// pumps it with KcUi.DoEvents.
public sealed class KcInputTestForm : IDisposable
{
    public const int StateNormal = KcKeyboardView.StateNormal;
    public const int StateCurrent = KcKeyboardView.StateCurrent;
    public const int StatePass = KcKeyboardView.StatePass;
    public const int StateFail = KcKeyboardView.StateFail;
    public const int StateSkip = KcKeyboardView.StateSkip;
    public const int StateHold = KcKeyboardView.StateHold;     // a layer key held during the step
    public const int StateMod = KcKeyboardView.StateMod;       // a modifier held during the step
    public const int StateDanger = KcKeyboardView.StateDanger; // must not be pressed (bootloader, reset, Bluetooth)
    public const int StateCombo = KcKeyboardView.StateCombo;   // pressed together with other keys

    // Kinds of the chips of SetSequence.
    public const int ChipLayer = 0;
    public const int ChipMod = 1;
    public const int ChipTap = 2;
    public const int ChipCombo = 3;
    public const int ChipRelease = 4;
    public const int ChipCheck = 5;

    // Kinds of the chips of SetLayerPath and states of SetLayerOverview.
    public const int PathStart = 0;
    public const int PathHeld = 1;
    public const int PathTarget = 2;
    public const int PathSwitched = 3;
    public const int LayerIdle = 0;
    public const int LayerTesting = 1;
    public const int LayerPass = 2;
    public const int LayerFail = 3;
    public const int LayerSkip = 4;

    // States of the key caps of SetOutputs.
    public const int CapNeutral = KcDraw.CapNeutral;
    public const int CapOk = KcDraw.CapOk;
    public const int CapNg = KcDraw.CapNg;
    public const int CapPending = KcDraw.CapPending;

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

    const uint RIDI_DEVICENAME = 0x20000007;
    const double RoomyHeight = 700; // window content height (DIP) from which the texts have full size

    // Theme keys per chip kind (ChipLayer .. ChipCheck), per path kind and per overview state.
    static readonly string[] ChipFill = { "KcKeyHoldFill", "KcKeyModFill", "KcKeyCurrentFill", "KcKeyComboFill", "KcLayerIdleFill", "KcKeyPassFill" };
    static readonly string[] ChipEdge = { "KcKeyHoldEdge", "KcKeyModEdge", "KcKeyCurrentEdge", "KcKeyComboEdge", "KcLayerIdleEdge", "KcKeyPassEdge" };
    static readonly string[] ChipInk = { "KcKeyHoldInk", "KcKeyModInk", "KcKeyCurrentInk", "KcKeyComboInk", "KcLayerIdleInk", "KcKeyPassInk" };
    static readonly string[] PathFill = { "KcLayerIdleFill", "KcKeyHoldFill", "KcLayerOnFill", "KcKeyComboFill" };
    static readonly string[] PathEdge = { "KcLayerIdleEdge", "KcKeyHoldEdge", "KcLayerOnEdge", "KcKeyComboEdge" };
    static readonly string[] PathInk = { "KcLayerIdleInk", "KcKeyHoldInk", "KcLayerOnInk", "KcKeyComboInk" };
    static readonly string[] OverviewFill = { "KcLayerIdleFill", "KcLayerOnFill", "KcOkTint", "KcNgTint", "KcKeySkipFill" };
    static readonly string[] OverviewEdge = { "KcLayerIdleEdge", "KcLayerOnEdge", "KcOkEdge", "KcNgEdge", "KcKeySkipEdge" };
    static readonly string[] OverviewInk = { "KcLayerIdleInk", "KcLayerOnInk", "KcOkInk", "KcNgInk", "KcKeySkipInk" };
    readonly object sync = new object();
    readonly List<KcInputEvent> events = new List<KcInputEvent>();
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
    readonly FrameworkElement legendHoldItem;
    readonly FrameworkElement legendModItem;
    readonly FrameworkElement legendDangerItem;
    readonly TextBlock legendHold;
    readonly TextBlock legendMod;
    readonly TextBlock legendDanger;
    readonly FrameworkElement layerStrip;
    readonly Panel layerPath;
    readonly Panel layerOverview;
    readonly TextBlock layerOverviewCaption;
    readonly Panel sequencePanel;
    readonly FrameworkElement outputPanel;
    readonly TextBlock expectedCaption;
    readonly TextBlock actualCaption;
    readonly Panel expectedCaps;
    readonly Panel actualCaps;
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
    readonly KcKeyboardView keyboard;
    readonly KcWinKeyMask winMask;
    readonly DispatcherTimer clipTimer = new DispatcherTimer();
    string action = "";
    string statusValue = "";
    int statusLevel = -1;
    int progressValue = -1;
    int progressMax;
    string outputsSignature = "";
    string overviewSignature = "";
    bool closed;
    bool confine;
    bool maskWin;
    IntPtr hwnd = IntPtr.Zero;

    public KcInputTestForm()
    {
        FrameworkElement content;
        window = KcUi.CreateWindow("InputTestWindow.xaml", out content);
        root = content;
        window.Title = "keyboard-check";
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        // minimum height: with the steps of the behaviors test (layer strip, chips, key caps of the input)
        // the keyboard picture still has room
        KcUi.FitSize(window, 1100, 780, 800, 680);
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
        legendHoldItem = KcUi.Find<FrameworkElement>(root, "LegendHoldItem");
        legendModItem = KcUi.Find<FrameworkElement>(root, "LegendModItem");
        legendDangerItem = KcUi.Find<FrameworkElement>(root, "LegendDangerItem");
        legendHold = KcUi.Find<TextBlock>(root, "LegendHold");
        legendMod = KcUi.Find<TextBlock>(root, "LegendMod");
        legendDanger = KcUi.Find<TextBlock>(root, "LegendDanger");
        layerStrip = KcUi.Find<FrameworkElement>(root, "LayerStrip");
        layerPath = KcUi.Find<Panel>(root, "LayerPath");
        layerOverview = KcUi.Find<Panel>(root, "LayerOverview");
        layerOverviewCaption = KcUi.Find<TextBlock>(root, "LayerOverviewCaption");
        sequencePanel = KcUi.Find<Panel>(root, "SequencePanel");
        outputPanel = KcUi.Find<FrameworkElement>(root, "OutputPanel");
        expectedCaption = KcUi.Find<TextBlock>(root, "ExpectedCaption");
        actualCaption = KcUi.Find<TextBlock>(root, "ActualCaption");
        expectedCaps = KcUi.Find<Panel>(root, "ExpectedCaps");
        actualCaps = KcUi.Find<Panel>(root, "ActualCaps");
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

        keyboard = new KcKeyboardView(window, keyboardCanvas);
        winMask = new KcWinKeyMask(delegate { return maskWin ? hwnd : IntPtr.Zero; });

        window.PreviewKeyDown += KcUi.SwallowKey;
        window.PreviewKeyUp += KcUi.SwallowKey;
        window.PreviewTextInput += KcUi.SwallowText;
        window.SourceInitialized += OnSourceInitialized;
        window.Closed += delegate
        {
            closed = true;
            ReleaseClip();
            winMask.Enable(false);
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
        statusBanner.Background = ThemeBrush(KcDraw.StatusTint[level]);
        statusBanner.BorderBrush = ThemeBrush(KcDraw.StatusEdge[level]);
        statusMark.Fill = ThemeBrush(KcDraw.StatusMark[level]);
        statusText.Foreground = ThemeBrush(KcDraw.StatusInk[level]);
        statusIcon.Data = Geometry.Parse(KcDraw.StatusIconData[level]);
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
        keyboard.SetKeys(pos, x, y, w, h, legends);
    }

    public void SetKeyState(int pos, int state)
    {
        keyboard.SetKeyState(pos, state);
    }

    public void ClearKeyStates()
    {
        keyboard.ClearKeyStates();
    }

    // Legends of the keys of a layer (pos[i] gets legends[i]; a line break makes two lines). Keys not
    // listed keep their legend.
    public void SetKeyLegends(int[] pos, string[] legends)
    {
        keyboard.SetKeyLegends(pos, legends);
    }

    // Back to the legends given to SetKeys (the BASE layer).
    public void ResetKeyLegends()
    {
        keyboard.ResetKeyLegends();
    }

    // Small badge on a key ("" hides it): order of the presses (1, 2, ...) or the tap count (x2).
    public void SetKeyBadge(int pos, string text)
    {
        keyboard.SetKeyBadge(pos, text);
    }

    public void ClearKeyBadges()
    {
        keyboard.ClearKeyBadges();
    }

    // Texts of the extra swatches of the color legend (held layer key, held modifier, must not press);
    // an empty text hides its swatch.
    public void SetExtraLegendTexts(string hold, string mod, string danger)
    {
        legendHold.Text = hold ?? "";
        legendMod.Text = mod ?? "";
        legendDanger.Text = danger ?? "";
        KcUi.SetVisible(legendHoldItem, legendHold.Text.Length > 0);
        KcUi.SetVisible(legendModItem, legendMod.Text.Length > 0);
        KcUi.SetVisible(legendDangerItem, legendDanger.Text.Length > 0);
    }

    // Layers the step goes through, in order, joined by arrows (kinds: PathStart .. PathSwitched).
    // An empty array hides the path (and the strip when there is no overview either).
    public void SetLayerPath(string[] names, int[] kinds)
    {
        layerPath.Children.Clear();
        for (int i = 0; i < names.Length; i++)
        {
            if (i > 0)
            {
                layerPath.Children.Add(KcDraw.Arrow(window));
            }
            int kind = i < kinds.Length ? KcDraw.Clamp(kinds[i], 0, PathFill.Length - 1) : PathStart;
            Border chip = KcDraw.Chip(window, null, names[i], PathFill[kind], PathEdge[kind], PathInk[kind], 15);
            chip.Margin = new Thickness(0, 2, 0, 2);
            if (kind == PathTarget)
            {
                chip.BorderThickness = new Thickness(2);
            }
            layerPath.Children.Add(chip);
        }
        UpdateLayerStrip();
    }

    // All layers as small chips with their result (states: LayerIdle .. LayerSkip). Does nothing when
    // nothing changed. An empty array hides the overview.
    public void SetLayerOverview(string caption, string[] names, int[] states)
    {
        StringBuilder sig = new StringBuilder(caption ?? "");
        for (int i = 0; i < names.Length; i++)
        {
            sig.Append('|').Append(names[i]).Append(':').Append(i < states.Length ? states[i] : 0);
        }
        if (sig.ToString() == overviewSignature)
        {
            return;
        }
        overviewSignature = sig.ToString();
        layerOverviewCaption.Text = names.Length > 0 ? (caption ?? "") : "";
        layerOverview.Children.Clear();
        for (int i = 0; i < names.Length; i++)
        {
            int s = i < states.Length ? KcDraw.Clamp(states[i], 0, OverviewFill.Length - 1) : LayerIdle;
            Border chip = KcDraw.Chip(window, null, names[i], OverviewFill[s], OverviewEdge[s], OverviewInk[s], 12);
            chip.Padding = new Thickness(8, 2, 8, 2);
            chip.Margin = new Thickness(0, 2, 6, 2);
            layerOverview.Children.Add(chip);
        }
        UpdateLayerStrip();
    }

    // The presses of the step as chips: captions[i] (small, e.g. "hold") above texts[i], colored by
    // kinds[i] (ChipLayer .. ChipCheck); joiners[i] is put before chip i ("+" or "" for an arrow).
    // An empty array hides the row.
    public void SetSequence(string[] captions, string[] texts, int[] kinds, string[] joiners)
    {
        sequencePanel.Children.Clear();
        for (int i = 0; i < texts.Length; i++)
        {
            if (i > 0)
            {
                string j = i < joiners.Length ? joiners[i] : "";
                if (string.IsNullOrEmpty(j))
                {
                    sequencePanel.Children.Add(KcDraw.Arrow(window));
                }
                else
                {
                    TextBlock plus = new TextBlock();
                    plus.Text = j;
                    plus.FontSize = 18;
                    plus.FontWeight = FontWeights.Bold;
                    plus.Foreground = ThemeBrush("KcLayerArrow");
                    plus.VerticalAlignment = VerticalAlignment.Center;
                    plus.Margin = new Thickness(8, 0, 8, 0);
                    sequencePanel.Children.Add(plus);
                }
            }
            int kind = i < kinds.Length ? KcDraw.Clamp(kinds[i], 0, ChipFill.Length - 1) : ChipTap;
            string caption = i < captions.Length ? captions[i] : "";
            Border chip = KcDraw.Chip(window, caption, texts[i], ChipFill[kind], ChipEdge[kind], ChipInk[kind], 16);
            chip.Margin = new Thickness(0, 3, 0, 3);
            sequencePanel.Children.Add(chip);
        }
        KcUi.SetVisible(sequencePanel, texts.Length > 0);
    }

    // Expected and actual input as key caps (states: CapNeutral .. CapPending). emptyText is shown when
    // there is no actual input yet. Does nothing when nothing changed (called on every check).
    public void SetOutputs(string expectedTitle, string[] expected, int[] expectedStates,
                           string actualTitle, string[] actual, int[] actualStates, string emptyText)
    {
        StringBuilder sig = new StringBuilder();
        sig.Append(expectedTitle).Append('|').Append(actualTitle).Append('|').Append(emptyText);
        KcDraw.AppendSignature(sig, expected, expectedStates);
        KcDraw.AppendSignature(sig, actual, actualStates);
        if (sig.ToString() == outputsSignature)
        {
            return;
        }
        outputsSignature = sig.ToString();
        expectedCaption.Text = expectedTitle ?? "";
        actualCaption.Text = actualTitle ?? "";
        KcDraw.Caps(window, expectedCaps, expected, expectedStates, "");
        KcDraw.Caps(window, actualCaps, actual, actualStates, emptyText);
        outputPanel.Visibility = Visibility.Visible;
    }

    public void ClearOutputs()
    {
        outputsSignature = "";
        expectedCaps.Children.Clear();
        actualCaps.Children.Clear();
        outputPanel.Visibility = Visibility.Collapsed;
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
        winMask.Enable(on);
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
        winMask.Dispose();
        clipTimer.Stop();
        Close();
    }

    // ---- internals ----

    Brush ThemeBrush(string key)
    {
        return (Brush)window.FindResource(key);
    }

    void UpdateLayerStrip()
    {
        KcUi.SetVisible(layerStrip, layerPath.Children.Count > 0 || layerOverview.Children.Count > 0);
    }

    // On a low window (small screen, high scaling) the long instructions would push the keyboard
    // picture out: the texts shrink with the height (down to 72 %), and so do the layer strip, the
    // chips of the presses and the key caps of the input (with the steps of the behaviors test).
    void FitTexts()
    {
        double f = Math.Max(0.72, Math.Min(1.0, root.ActualHeight / RoomyHeight));
        instructionText.FontSize = 26 * f;
        detailText.FontSize = 15 * f;
        statusText.FontSize = 16 * f;
        ScaleTransform scale = new ScaleTransform(f, f);
        layerStrip.LayoutTransform = scale;
        sequencePanel.LayoutTransform = scale;
        outputPanel.LayoutTransform = scale;
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

// The window of keyboard-check.ps1 -Mode Trace: how the layers change and how each pressed key is
// resolved, read from the log of the ZMK logging firmware (the log is parsed in PowerShell, zmk-log.ps1).
// Driven by a PowerShell polling loop (KcUi.DoEvents) like KcInputTestForm. It is not topmost and does not
// record Raw Input; keys typed while it is in front are swallowed and the Win key is masked.
public sealed class KcLayerTraceForm : IDisposable
{
    // States of the layer chips (SetLayers).
    public const int LayerOff = 0;
    public const int LayerOn = 1;
    public const int LayerTop = 2;
    // States of the rows of the resolution (SetResolve).
    public const int RowSkipped = 0;   // active, not looked at (below the resolved layer)
    public const int RowTrans = 1;     // &trans: went on to the next layer
    public const int RowResolved = 2;  // the binding was taken from this layer
    public const int RowMismatch = 3;  // the log names another behavior than the expected values

    const int MaxTimeline = 400;

    static readonly string[] LayerFill = { "KcLayerIdleFill", "KcKeyHoldFill", "KcLayerOnFill" };
    static readonly string[] LayerEdge = { "KcLayerIdleEdge", "KcKeyHoldEdge", "KcLayerOnEdge" };
    static readonly string[] LayerInk = { "KcLayerIdleInk", "KcKeyHoldInk", "KcLayerOnInk" };
    static readonly string[] RowFill = { "KcLayerIdleFill", "KcKeySkipFill", "KcLayerOnFill", "KcNgTint" };
    static readonly string[] RowEdge = { "KcLayerIdleEdge", "KcKeySkipEdge", "KcLayerOnEdge", "KcNgEdge" };
    static readonly string[] RowInk = { "KcLayerIdleInk", "KcKeySkipInk", "KcLayerOnInk", "KcNgInk" };
    static readonly string[] Marks = { "KcTextFaint", "KcOkMark", "KcNgMark", "KcWarnMark" };
    static readonly string[] StatusInk = { "KcTextMuted", "KcOkMark", "KcNgMark", "KcWarnMark" };

    readonly Window window;
    readonly FrameworkElement root;
    readonly TextBlock titleText;
    readonly TextBlock keyboardText;
    readonly Ellipse portMark;
    readonly TextBlock portText;
    readonly TextBlock layersCaption;
    readonly Panel layerChips;
    readonly TextBlock hintText;
    readonly TextBlock pictureCaption;
    readonly TextBlock resolveTitle;
    readonly Panel cascadePanel;
    readonly Panel stepsPanel;
    readonly TextBlock outputCaption;
    readonly Panel outputCaps;
    readonly TextBlock timelineCaption;
    readonly ListBox timeline;
    readonly TextBlock statusText;
    readonly Button stopButton;
    readonly Button pauseButton;
    readonly Button clearButton;
    readonly Button saveButton;
    readonly KcKeyboardView keyboard;
    readonly KcWinKeyMask winMask;
    string action = "";
    string layersSignature = "";
    string resolveSignature = "";
    bool selectionChanged;
    bool closed;
    IntPtr hwnd = IntPtr.Zero;

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    public KcLayerTraceForm()
    {
        FrameworkElement content;
        window = KcUi.CreateWindow("LayerTraceWindow.xaml", out content);
        root = content;
        window.Title = "keyboard-check";
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        KcUi.FitSize(window, 1200, 840, 860, 620);
        InputMethod.SetIsInputMethodEnabled(window, false);

        titleText = KcUi.Find<TextBlock>(root, "TitleText");
        keyboardText = KcUi.Find<TextBlock>(root, "KeyboardText");
        portMark = KcUi.Find<Ellipse>(root, "PortMark");
        portText = KcUi.Find<TextBlock>(root, "PortText");
        layersCaption = KcUi.Find<TextBlock>(root, "LayersCaption");
        layerChips = KcUi.Find<Panel>(root, "LayerChips");
        hintText = KcUi.Find<TextBlock>(root, "HintText");
        pictureCaption = KcUi.Find<TextBlock>(root, "PictureCaption");
        resolveTitle = KcUi.Find<TextBlock>(root, "ResolveTitle");
        cascadePanel = KcUi.Find<Panel>(root, "CascadePanel");
        stepsPanel = KcUi.Find<Panel>(root, "StepsPanel");
        outputCaption = KcUi.Find<TextBlock>(root, "OutputCaption");
        outputCaps = KcUi.Find<Panel>(root, "OutputCaps");
        timelineCaption = KcUi.Find<TextBlock>(root, "TimelineCaption");
        timeline = KcUi.Find<ListBox>(root, "Timeline");
        statusText = KcUi.Find<TextBlock>(root, "StatusText");
        stopButton = KcUi.Find<Button>(root, "StopButton");
        pauseButton = KcUi.Find<Button>(root, "PauseButton");
        clearButton = KcUi.Find<Button>(root, "ClearButton");
        saveButton = KcUi.Find<Button>(root, "SaveButton");
        SetupButton(stopButton, "stop");
        SetupButton(pauseButton, "pause");
        SetupButton(clearButton, "clear");
        SetupButton(saveButton, "save");
        timeline.SelectionChanged += delegate { selectionChanged = true; };

        keyboard = new KcKeyboardView(window, KcUi.Find<Canvas>(root, "KeyboardCanvas"));
        winMask = new KcWinKeyMask(delegate { return hwnd; });

        window.PreviewKeyDown += KcUi.SwallowKey;
        window.PreviewKeyUp += KcUi.SwallowKey;
        window.PreviewTextInput += KcUi.SwallowText;
        window.SourceInitialized += OnSourceInitialized;
        window.Closed += delegate
        {
            closed = true;
            winMask.Enable(false);
        };
    }

    void SetupButton(Button button, string name)
    {
        button.Click += delegate { action = name; };
    }

    // ---- called from PowerShell ----

    public Window Window { get { return window; } }

    public bool IsClosed { get { return closed; } }

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

    public void SetButtonTexts(string stop, string pause, string clear, string save)
    {
        stopButton.Content = stop ?? "";
        pauseButton.Content = pause ?? "";
        clearButton.Content = clear ?? "";
        saveButton.Content = save ?? "";
    }

    public void SetTexts(string title, string hint)
    {
        titleText.Text = title ?? "";
        hintText.Text = hint ?? "";
        KcUi.SetVisible(hintText, hintText.Text.Length > 0);
    }

    public void SetCaptions(string layers, string picture, string output, string timelineTitle)
    {
        layersCaption.Text = layers ?? "";
        pictureCaption.Text = picture ?? "";
        outputCaption.Text = output ?? "";
        timelineCaption.Text = timelineTitle ?? "";
    }

    // Caption of the keyboard picture (which layer it shows).
    public void SetPictureCaption(string text)
    {
        pictureCaption.Text = text ?? "";
    }

    public void SetKeyboardName(string text)
    {
        keyboardText.Text = text ?? "";
    }

    // level: 0 = neutral, 1 = ok (receiving), 2 = ng, 3 = warning
    public void SetPort(string text, int level)
    {
        portText.Text = text ?? "";
        portMark.Fill = KcDraw.Res(window, Marks[KcDraw.Clamp(level, 0, Marks.Length - 1)]);
    }

    public void SetStatus(string text, int level)
    {
        statusText.Text = text ?? "";
        statusText.Foreground = KcDraw.Res(window, StatusInk[KcDraw.Clamp(level, 0, StatusInk.Length - 1)]);
    }

    public void SetKeys(int[] pos, double[] x, double[] y, double[] w, double[] h, string[] legends)
    {
        keyboard.SetKeys(pos, x, y, w, h, legends);
    }

    public void SetKeyState(int pos, int state)
    {
        keyboard.SetKeyState(pos, state);
    }

    public void ClearKeyStates()
    {
        keyboard.ClearKeyStates();
    }

    public void SetKeyLegends(int[] pos, string[] legends)
    {
        keyboard.SetKeyLegends(pos, legends);
    }

    // All layers as chips (states: LayerOff / LayerOn / LayerTop). Does nothing when nothing changed.
    public void SetLayers(string[] names, int[] states)
    {
        StringBuilder sig = new StringBuilder();
        KcDraw.AppendSignature(sig, names, states);
        if (sig.ToString() == layersSignature)
        {
            return;
        }
        layersSignature = sig.ToString();
        layerChips.Children.Clear();
        for (int i = 0; i < names.Length; i++)
        {
            int s = i < states.Length ? KcDraw.Clamp(states[i], 0, LayerFill.Length - 1) : LayerOff;
            Border chip = KcDraw.Chip(window, null, names[i], LayerFill[s], LayerEdge[s], LayerInk[s], 14);
            chip.Margin = new Thickness(0, 2, 8, 2);
            if (s == LayerTop)
            {
                chip.BorderThickness = new Thickness(2);
            }
            layerChips.Children.Add(chip);
        }
    }

    // How a key was resolved: one row per layer from the top (rowLayers[i] / rowTexts[i], states RowSkipped ..
    // RowMismatch), the steps of the behavior and the keys sent. Does nothing when nothing changed.
    public void SetResolve(string title, string[] rowLayers, string[] rowTexts, int[] rowStates, string[] steps,
                           string[] outputs, string emptyOutput)
    {
        StringBuilder sig = new StringBuilder(title ?? "");
        KcDraw.AppendSignature(sig, rowLayers, rowStates);
        KcDraw.AppendSignature(sig, rowTexts, new int[0]);
        KcDraw.AppendSignature(sig, steps, new int[0]);
        KcDraw.AppendSignature(sig, outputs, new int[0]);
        if (sig.ToString() == resolveSignature)
        {
            return;
        }
        resolveSignature = sig.ToString();
        resolveTitle.Text = title ?? "";
        cascadePanel.Children.Clear();
        for (int i = 0; i < rowLayers.Length; i++)
        {
            int s = i < rowStates.Length ? KcDraw.Clamp(rowStates[i], 0, RowFill.Length - 1) : RowSkipped;
            Border chip = KcDraw.Chip(window, null, rowLayers[i], RowFill[s], RowEdge[s], RowInk[s], 13);
            chip.MinWidth = 110;
            chip.Margin = new Thickness(0, 0, 10, 0);
            TextBlock text = new TextBlock();
            text.Text = i < rowTexts.Length ? (rowTexts[i] ?? "") : "";
            text.FontSize = 14;
            text.TextWrapping = TextWrapping.Wrap;
            text.VerticalAlignment = VerticalAlignment.Center;
            text.Foreground = KcDraw.Res(window, s == RowResolved ? "KcText" : "KcTextMuted");
            if (s == RowResolved || s == RowMismatch)
            {
                text.FontWeight = FontWeights.SemiBold;
            }
            DockPanel row = new DockPanel();
            row.Margin = new Thickness(0, 0, 0, 6);
            DockPanel.SetDock(chip, Dock.Left);
            row.Children.Add(chip);
            row.Children.Add(text);
            cascadePanel.Children.Add(row);
        }
        stepsPanel.Children.Clear();
        for (int i = 0; i < steps.Length; i++)
        {
            TextBlock t = new TextBlock();
            t.Text = steps[i] ?? "";
            t.FontSize = 14;
            t.TextWrapping = TextWrapping.Wrap;
            t.Margin = new Thickness(0, 2, 0, 2);
            t.Foreground = KcDraw.Res(window, "KcText");
            stepsPanel.Children.Add(t);
        }
        int[] none = new int[outputs.Length];
        KcDraw.Caps(window, outputCaps, outputs, none, emptyOutput);
    }

    // Adds a line at the top of the timeline (the newest first).
    public void AddTimeline(string line)
    {
        timeline.Items.Insert(0, line ?? "");
        while (timeline.Items.Count > MaxTimeline)
        {
            timeline.Items.RemoveAt(timeline.Items.Count - 1);
        }
    }

    // Rewrites a line of the timeline (fromTop: 0 = the newest), e.g. when more log lines of the key came.
    public void SetTimelineLine(int fromTop, string text)
    {
        if (fromTop < 0 || fromTop >= timeline.Items.Count)
        {
            return;
        }
        string line = text ?? "";
        if (line == (timeline.Items[fromTop] as string))
        {
            return;
        }
        int selected = timeline.SelectedIndex;
        bool changed = selectionChanged;
        timeline.Items[fromTop] = line;
        if (selected == fromTop)
        {
            timeline.SelectedIndex = selected;
        }
        selectionChanged = changed;
    }

    public void ClearTimeline()
    {
        timeline.Items.Clear();
    }

    // Index of the selected line (0 = the newest), or -1.
    public int SelectedIndex { get { return timeline.SelectedIndex; } }

    // True once after the user selected another line.
    public bool TakeSelectionChanged()
    {
        bool c = selectionChanged;
        selectionChanged = false;
        return c;
    }

    public void ClearSelection()
    {
        timeline.SelectedIndex = -1;
        selectionChanged = false;
    }

    // Returns the pressed button ("stop" / "pause" / "clear" / "save") once, or "". "stop" once closed.
    public string TakeAction()
    {
        string a = action;
        action = "";
        if (closed && a.Length == 0)
        {
            return "stop";
        }
        return a;
    }

    public void MaskWinKey(bool on)
    {
        winMask.Enable(on);
    }

    public void SaveSnapshot(string path)
    {
        KcUi.SaveSnapshot(root, path);
    }

    public void Dispose()
    {
        winMask.Dispose();
        Close();
    }

    // ---- internals ----

    void OnSourceInitialized(object sender, EventArgs e)
    {
        hwnd = new WindowInteropHelper(window).Handle;
        KcUi.ApplyDarkTitleBar(hwnd);
        HwndSource.FromHwnd(hwnd).AddHook(WndProc);
    }

    IntPtr WndProc(IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (KcUi.FilterSystemKeys(msg, wParam))
        {
            handled = true;
        }
        return IntPtr.Zero;
    }
}

// The window of tools/flash.ps1: choose a keyboard, a build (latest / PR / past custom build) and the
// options, then follow the steps while the flashing scripts run (their output is shown in the log).
// The window runs on a thread of its own (Launch) so the PowerShell thread can download and run the
// child processes; every setter is posted to the window thread. The buttons and the selections are
// queued as action strings ("keyboard:LisM", "build:firmware-pr-12", "option:mode:Both", "start", ...)
// and taken with TakeActions(). Keys typed while the window is in front (the keyboard being flashed may
// type Q / P) are swallowed, and nothing in the window takes the keyboard focus.
public sealed class KcFlashForm : IDisposable
{
    public const int PageSelect = 0;
    public const int PageRun = 1;
    // Levels of the banners, the notes and the log lines.
    public const int LevelInfo = 0;
    public const int LevelOk = 1;
    public const int LevelNg = 2;
    public const int LevelWarn = 3;
    public const int LevelFaint = 4;
    // States of the steps.
    public const int StepPending = 0;
    public const int StepActive = 1;
    public const int StepDone = 2;
    public const int StepFailed = 3;
    // Kinds of the builds.
    public const int KindLatest = 0;
    public const int KindPr = 1;
    public const int KindCustom = 2;
    // States of the pull requests.
    public const int PrNone = 0;
    public const int PrOpen = 1;
    public const int PrMerged = 2;
    public const int PrClosed = 3;
    // Styles of the option groups.
    public const int StyleChoices = 0;
    public const int StyleSegments = 1;

    const int MaxLogLines = 3000;

    static readonly string[] KindFill = { "KcLayerOnFill", "KcKeyHoldFill", "KcLayerIdleFill" };
    static readonly string[] KindEdge = { "KcLayerOnEdge", "KcKeyHoldEdge", "KcLayerIdleEdge" };
    static readonly string[] KindInk = { "KcLayerOnInk", "KcKeyHoldInk", "KcLayerIdleInk" };
    static readonly string[] PrFill = { "KcLayerIdleFill", "KcOkTint", "KcKeyHoldFill", "KcNgTint" };
    static readonly string[] PrEdge = { "KcLayerIdleEdge", "KcOkEdge", "KcKeyHoldEdge", "KcNgEdge" };
    static readonly string[] PrInk = { "KcLayerIdleInk", "KcOkInk", "KcKeyHoldInk", "KcNgInk" };
    static readonly string[] LineInk = { "KcText", "KcOkMark", "KcNgMark", "KcWarnMark", "KcTextFaint" };
    static readonly string[] FooterInk = { "KcTextMuted", "KcOkMark", "KcNgMark", "KcWarnMark", "KcTextFaint" };

    readonly object sync = new object();
    readonly List<string> actions = new List<string>();
    readonly Window window;
    readonly FrameworkElement root;
    readonly TextBlock appCaption;
    readonly TextBlock titleText;
    readonly TextBlock subtitleText;
    readonly ProgressBar stepProgress;
    readonly Border sourceChip;
    readonly Ellipse sourceMark;
    readonly TextBlock sourceText;
    readonly FrameworkElement selectPage;
    readonly FrameworkElement runPage;
    readonly TextBlock keyboardsCaption;
    readonly Panel keyboardList;
    readonly TextBlock buildsCaption;
    readonly Panel filterPanel;
    readonly Button refreshButton;
    readonly Border buildsMessage;
    readonly TextBlock buildsMessageText;
    readonly Panel buildList;
    readonly TextBlock optionsCaption;
    readonly Panel optionsPanel;
    readonly TextBlock planCaption;
    readonly Panel planSteps;
    readonly Border planNote;
    readonly TextBlock planNoteText;
    readonly TextBlock runStepsCaption;
    readonly Panel runSteps;
    readonly Border banner;
    readonly Ellipse bannerMark;
    readonly Path bannerIcon;
    readonly TextBlock bannerTitle;
    readonly TextBlock bannerText;
    readonly TextBlock logCaption;
    readonly RichTextBox logBox;
    readonly Button cancelButton;
    readonly Button startButton;
    readonly Button continueButton;
    readonly Button retryButton;
    readonly Button backButton;
    readonly Button closeButton;
    readonly TextBlock statusText;
    readonly Dictionary<string, RadioButton> keyboardItems = new Dictionary<string, RadioButton>();
    readonly Dictionary<string, RadioButton> buildItems = new Dictionary<string, RadioButton>();
    readonly List<FrameworkElement> planStepRows = new List<FrameworkElement>();
    readonly List<FrameworkElement> runStepRows = new List<FrameworkElement>();
    string[] stepTitles = new string[0];
    int[] stepStates = new int[0];
    bool suppress;
    bool closeGuard;
    bool forceClose;
    bool lastLogPartial;
    string statusValue = "";
    int statusLevel = -1;
    volatile bool closed;

    public KcFlashForm(string title)
    {
        FrameworkElement content;
        window = KcUi.CreateWindow("FlashWindow.xaml", out content);
        root = content;
        window.Title = title ?? "flash";
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        KcUi.FitSize(window, 1220, 800, 1000, 600);
        InputMethod.SetIsInputMethodEnabled(window, false);

        appCaption = KcUi.Find<TextBlock>(root, "AppCaption");
        titleText = KcUi.Find<TextBlock>(root, "TitleText");
        subtitleText = KcUi.Find<TextBlock>(root, "SubtitleText");
        stepProgress = KcUi.Find<ProgressBar>(root, "StepProgress");
        sourceChip = KcUi.Find<Border>(root, "SourceChip");
        sourceMark = KcUi.Find<Ellipse>(root, "SourceMark");
        sourceText = KcUi.Find<TextBlock>(root, "SourceText");
        selectPage = KcUi.Find<FrameworkElement>(root, "SelectPage");
        runPage = KcUi.Find<FrameworkElement>(root, "RunPage");
        keyboardsCaption = KcUi.Find<TextBlock>(root, "KeyboardsCaption");
        keyboardList = KcUi.Find<Panel>(root, "KeyboardList");
        buildsCaption = KcUi.Find<TextBlock>(root, "BuildsCaption");
        filterPanel = KcUi.Find<Panel>(root, "FilterPanel");
        refreshButton = KcUi.Find<Button>(root, "RefreshButton");
        buildsMessage = KcUi.Find<Border>(root, "BuildsMessage");
        buildsMessageText = KcUi.Find<TextBlock>(root, "BuildsMessageText");
        buildList = KcUi.Find<Panel>(root, "BuildList");
        optionsCaption = KcUi.Find<TextBlock>(root, "OptionsCaption");
        optionsPanel = KcUi.Find<Panel>(root, "OptionsPanel");
        planCaption = KcUi.Find<TextBlock>(root, "PlanCaption");
        planSteps = KcUi.Find<Panel>(root, "PlanSteps");
        planNote = KcUi.Find<Border>(root, "PlanNote");
        planNoteText = KcUi.Find<TextBlock>(root, "PlanNoteText");
        runStepsCaption = KcUi.Find<TextBlock>(root, "RunStepsCaption");
        runSteps = KcUi.Find<Panel>(root, "RunSteps");
        banner = KcUi.Find<Border>(root, "Banner");
        bannerMark = KcUi.Find<Ellipse>(root, "BannerMark");
        bannerIcon = KcUi.Find<Path>(root, "BannerIcon");
        bannerTitle = KcUi.Find<TextBlock>(root, "BannerTitle");
        bannerText = KcUi.Find<TextBlock>(root, "BannerText");
        logCaption = KcUi.Find<TextBlock>(root, "LogCaption");
        logBox = KcUi.Find<RichTextBox>(root, "LogBox");
        cancelButton = KcUi.Find<Button>(root, "CancelButton");
        startButton = KcUi.Find<Button>(root, "StartButton");
        continueButton = KcUi.Find<Button>(root, "ContinueButton");
        retryButton = KcUi.Find<Button>(root, "RetryButton");
        backButton = KcUi.Find<Button>(root, "BackButton");
        closeButton = KcUi.Find<Button>(root, "CloseButton");
        statusText = KcUi.Find<TextBlock>(root, "StatusText");

        System.Windows.Documents.FlowDocument doc = new System.Windows.Documents.FlowDocument();
        doc.PagePadding = new Thickness(0);
        logBox.Document = doc;

        SetupButton(cancelButton, "cancel");
        SetupButton(startButton, "start");
        SetupButton(continueButton, "continue");
        SetupButton(retryButton, "retry");
        SetupButton(backButton, "back");
        SetupButton(closeButton, "close");
        SetupButton(refreshButton, "refresh");
        SetButtonsCore(true, false, false, false, false, true);
        SetBannerCore("", "", LevelInfo);

        window.PreviewKeyDown += SwallowKeyButCopy;
        window.PreviewKeyUp += SwallowKeyButCopy;
        window.PreviewTextInput += KcUi.SwallowText;
        window.SourceInitialized += OnSourceInitialized;
        window.Closing += OnClosing;
        window.Closed += delegate { closed = true; };
    }

    // Opens the window on its own STA thread and returns once it is shown (or throws after 15 s).
    public static KcFlashForm Launch(string title)
    {
        KcFlashForm[] box = new KcFlashForm[1];
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
                KcFlashForm form = new KcFlashForm(title);
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
                form.window.Activate();
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
        thread.Name = "flash";
        thread.Start();
        if (!ready.WaitOne(15000) || box[0] == null)
        {
            string reason = error[0] != null ? error[0].Message : "timeout";
            throw new InvalidOperationException("cannot open the flashing window (" + reason + ")");
        }
        return box[0];
    }

    // ---- called from PowerShell ----

    // The WPF window (the tests show it off screen; use it on the window thread only).
    public Window Window { get { return window; } }

    public bool IsClosed { get { return closed; } }

    // The queued actions (oldest first); "close" once the window has been closed.
    public string[] TakeActions()
    {
        lock (sync)
        {
            if (closed && actions.Count == 0)
            {
                return new string[] { "close" };
            }
            string[] a = actions.ToArray();
            actions.Clear();
            return a;
        }
    }

    // While on, closing the window (title bar) only queues "close": PowerShell stops the running step
    // and then calls RequestClose.
    public void SetCloseGuard(bool on)
    {
        closeGuard = on;
    }

    public void RequestClose()
    {
        forceClose = true;
        Post(delegate
        {
            if (!closed)
            {
                window.Close();
            }
        });
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

    public void SetTexts(string caption, string title, string subtitle)
    {
        Post(delegate
        {
            appCaption.Text = caption ?? "";
            titleText.Text = title ?? "";
            subtitleText.Text = subtitle ?? "";
        });
    }

    public void SetCaptions(string keyboards, string builds, string options, string steps, string log)
    {
        Post(delegate
        {
            keyboardsCaption.Text = keyboards ?? "";
            buildsCaption.Text = builds ?? "";
            optionsCaption.Text = options ?? "";
            planCaption.Text = steps ?? "";
            runStepsCaption.Text = steps ?? "";
            logCaption.Text = log ?? "";
        });
    }

    public void SetButtonTexts(string close, string back, string cancel, string retry, string cont, string start, string refresh)
    {
        Post(delegate
        {
            closeButton.Content = close ?? "";
            backButton.Content = back ?? "";
            cancelButton.Content = cancel ?? "";
            retryButton.Content = retry ?? "";
            continueButton.Content = cont ?? "";
            startButton.Content = start ?? "";
            refreshButton.Content = refresh ?? "";
        });
    }

    // Which footer buttons are shown.
    public void SetButtons(bool close, bool back, bool cancel, bool retry, bool cont, bool start)
    {
        Post(delegate { SetButtonsCore(close, back, cancel, retry, cont, start); });
    }

    public void SetStartEnabled(bool enabled)
    {
        Post(delegate { startButton.IsEnabled = enabled; });
    }

    // The chip at the top right: where the build list came from ("" hides it).
    public void SetSource(string text, int level)
    {
        Post(delegate
        {
            sourceText.Text = text ?? "";
            sourceMark.Fill = Res(KcDraw.StatusMark[KcDraw.Clamp(level, 0, KcDraw.StatusMark.Length - 1)]);
            KcUi.SetVisible(sourceChip, sourceText.Text.Length > 0);
        });
    }

    // The status line of the footer. Does nothing when nothing changed (called on every tick).
    public void SetStatus(string text, int level)
    {
        Post(delegate
        {
            text = text ?? "";
            if (text == statusValue && level == statusLevel)
            {
                return;
            }
            statusValue = text;
            statusLevel = level;
            statusText.Text = text;
            statusText.Foreground = Res(FooterInk[KcDraw.Clamp(level, 0, FooterInk.Length - 1)]);
        });
    }

    // The thin bar under the header (max 0 hides it).
    public void SetProgress(int value, int max)
    {
        Post(delegate
        {
            if (max <= 0)
            {
                stepProgress.Visibility = Visibility.Hidden;
                return;
            }
            stepProgress.Maximum = max;
            stepProgress.Value = Math.Max(0, Math.Min(value, max));
            stepProgress.Visibility = Visibility.Visible;
        });
    }

    public void ShowPage(int page)
    {
        Post(delegate
        {
            KcUi.SetVisible(selectPage, page == PageSelect);
            KcUi.SetVisible(runPage, page == PageRun);
        });
    }

    // The keyboard list, grouped by groups[i] (a caption before each new group).
    public void SetKeyboards(string[] keys, string[] names, string[] details, string[] groups)
    {
        Post(delegate
        {
            keyboardList.Children.Clear();
            keyboardItems.Clear();
            string group = null;
            for (int i = 0; i < keys.Length; i++)
            {
                string g = At(groups, i);
                if (g != group)
                {
                    group = g;
                    TextBlock caption = new TextBlock();
                    caption.Text = g;
                    caption.Style = (Style)window.FindResource("KcGroupCaption");
                    keyboardList.Children.Add(caption);
                }
                StackPanel content = new StackPanel();
                content.Children.Add(Text(At(names, i), 14, FontWeights.SemiBold, "KcText"));
                TextBlock detail = Text(At(details, i), 12, FontWeights.Normal, "KcTextFaint");
                detail.Margin = new Thickness(0, 1, 0, 0);
                content.Children.Add(detail);
                RadioButton item = Radio("KcNavItem", content, "keyboard:" + keys[i]);
                keyboardItems[keys[i]] = item;
                keyboardList.Children.Add(item);
            }
        });
    }

    public void SelectKeyboard(string key)
    {
        Post(delegate { Check(keyboardItems, key); });
    }

    // The filter of the build list (segments).
    public void SetBuildFilters(string[] keys, string[] labels, string selected)
    {
        Post(delegate
        {
            filterPanel.Children.Clear();
            for (int i = 0; i < keys.Length; i++)
            {
                RadioButton item = Radio("KcSegment", At(labels, i), "filter:" + keys[i]);
                item.Padding = new Thickness(12, 4, 12, 5);
                filterPanel.Children.Add(item);
                if (keys[i] == selected)
                {
                    SetChecked(item);
                }
            }
        });
    }

    // The build list: a card per build (badge by kind, title, detail and the state of its pull request).
    public void SetBuilds(string[] keys, int[] kinds, string[] badges, string[] titles, string[] details, int[] prStates,
        string[] prStateTexts, string[] tooltips, string selectedKey)
    {
        Post(delegate
        {
            buildList.Children.Clear();
            buildItems.Clear();
            for (int i = 0; i < keys.Length; i++)
            {
                int kind = KcDraw.Clamp(AtInt(kinds, i), 0, KindFill.Length - 1);
                int pr = KcDraw.Clamp(AtInt(prStates, i), 0, PrFill.Length - 1);
                DockPanel top = new DockPanel();
                if (pr != PrNone && At(prStateTexts, i).Length > 0)
                {
                    Border state = MakeTag(At(prStateTexts, i), PrFill[pr], PrEdge[pr], PrInk[pr]);
                    DockPanel.SetDock(state, Dock.Right);
                    top.Children.Add(state);
                }
                Border badge = MakeTag(At(badges, i), KindFill[kind], KindEdge[kind], KindInk[kind]);
                badge.HorizontalAlignment = HorizontalAlignment.Left;
                top.Children.Add(badge);
                StackPanel content = new StackPanel();
                content.Children.Add(top);
                TextBlock t = Text(At(titles, i), 14, FontWeights.SemiBold, "KcText");
                t.Margin = new Thickness(0, 7, 0, 0);
                t.TextTrimming = TextTrimming.CharacterEllipsis;
                content.Children.Add(t);
                TextBlock d = Text(At(details, i), 12, FontWeights.Normal, "KcTextFaint");
                d.FontFamily = (FontFamily)window.FindResource("KcMonoFont");
                d.Margin = new Thickness(0, 3, 0, 0);
                d.TextTrimming = TextTrimming.CharacterEllipsis;
                content.Children.Add(d);
                RadioButton item = Radio("KcBuildItem", content, "build:" + keys[i]);
                if (At(tooltips, i).Length > 0)
                {
                    item.ToolTip = At(tooltips, i);
                }
                buildItems[keys[i]] = item;
                buildList.Children.Add(item);
            }
            Check(buildItems, selectedKey);
        });
    }

    // The note above the build list ("" hides it): loading, offline, no builds.
    public void SetBuildsMessage(string text, int level)
    {
        Post(delegate { Note(buildsMessage, buildsMessageText, text, level); });
    }

    public void ClearOptionGroups()
    {
        Post(delegate { optionsPanel.Children.Clear(); });
    }

    // One option group: choices (a vertical list with descriptions) or segments (a row; the description of
    // the selected one below). A hidden group keeps its place in the order.
    public void AddOptionGroup(string group, string caption, int style, string[] keys, string[] labels, string[] details,
        string selected, bool visible)
    {
        Post(delegate
        {
            StackPanel box = new StackPanel();
            TextBlock c = new TextBlock();
            c.Text = caption ?? "";
            c.Style = (Style)window.FindResource("KcSectionCaption");
            c.Margin = new Thickness(0, 12, 0, 8);
            box.Children.Add(c);
            if (style == StyleChoices)
            {
                StackPanel list = new StackPanel();
                for (int i = 0; i < keys.Length; i++)
                {
                    StackPanel content = new StackPanel();
                    content.Children.Add(Text(At(labels, i), 13.5, FontWeights.SemiBold, "KcText"));
                    if (At(details, i).Length > 0)
                    {
                        TextBlock d = Text(At(details, i), 12, FontWeights.Normal, "KcTextMuted");
                        d.Margin = new Thickness(0, 2, 0, 0);
                        content.Children.Add(d);
                    }
                    RadioButton item = Radio("KcChoice", content, "option:" + group + ":" + keys[i]);
                    list.Children.Add(item);
                    if (keys[i] == selected)
                    {
                        SetChecked(item);
                    }
                }
                box.Children.Add(list);
            }
            else
            {
                Border bar = new Border();
                bar.Style = (Style)window.FindResource("KcSegmentBar");
                System.Windows.Controls.Primitives.UniformGrid row = new System.Windows.Controls.Primitives.UniformGrid();
                row.Rows = 1;
                bar.Child = row;
                box.Children.Add(bar);
                TextBlock hint = Text("", 12, FontWeights.Normal, "KcTextMuted");
                hint.Margin = new Thickness(2, 6, 0, 0);
                box.Children.Add(hint);
                for (int i = 0; i < keys.Length; i++)
                {
                    string detail = At(details, i);
                    RadioButton item = Radio("KcSegment", At(labels, i), "option:" + group + ":" + keys[i]);
                    item.Checked += delegate
                    {
                        hint.Text = detail;
                        KcUi.SetVisible(hint, detail.Length > 0);
                    };
                    row.Children.Add(item);
                    if (keys[i] == selected)
                    {
                        SetChecked(item);
                    }
                }
                KcUi.SetVisible(hint, hint.Text.Length > 0);
            }
            KcUi.SetVisible(box, visible);
            optionsPanel.Children.Add(box);
        });
    }

    // The note under the steps of the select page ("" hides it).
    public void SetPlanNote(string text, int level)
    {
        Post(delegate { Note(planNote, planNoteText, text, level); });
    }

    // The steps (shown on both pages).
    public void SetSteps(string[] titles, string[] details, int[] states)
    {
        Post(delegate
        {
            stepTitles = titles ?? new string[0];
            stepStates = new int[stepTitles.Length];
            FillSteps(planSteps, planStepRows, details, states);
            FillSteps(runSteps, runStepRows, details, states);
        });
    }

    public void SetStepState(int index, int state)
    {
        Post(delegate
        {
            if (index < 0 || index >= stepStates.Length)
            {
                return;
            }
            stepStates[index] = state;
            UpdateStepRow(planStepRows, index);
            UpdateStepRow(runStepRows, index);
        });
    }

    // The banner of the run page: what to do now, or the result.
    public void SetBanner(string title, string text, int level)
    {
        Post(delegate { SetBannerCore(title, text, level); });
    }

    // Appends a line to the log. partial: the line is replaced by the next one (a progress line).
    public void AppendLog(string text, int level, bool partial)
    {
        Post(delegate { AppendLogCore(text, level, partial); });
    }

    public void ClearLog()
    {
        Post(delegate
        {
            logBox.Document.Blocks.Clear();
            lastLogPartial = false;
        });
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

    void Enqueue(string action)
    {
        lock (sync)
        {
            actions.Add(action);
        }
    }

    void SetupButton(Button button, string name)
    {
        button.Click += delegate { Enqueue(name); };
    }

    Brush Res(string key)
    {
        return KcDraw.Res(window, key);
    }

    static string At(string[] a, int i)
    {
        return a != null && i < a.Length && a[i] != null ? a[i] : "";
    }

    static int AtInt(int[] a, int i)
    {
        return a != null && i < a.Length ? a[i] : 0;
    }

    TextBlock Text(string text, double size, FontWeight weight, string ink)
    {
        TextBlock t = new TextBlock();
        t.Text = text ?? "";
        t.FontSize = size;
        t.FontWeight = weight;
        t.Foreground = Res(ink);
        t.TextWrapping = TextWrapping.NoWrap;
        return t;
    }

    // A small rounded tag (the kind of a build, the state of a pull request).
    Border MakeTag(string text, string fill, string edge, string ink)
    {
        TextBlock t = Text(text, 11.5, FontWeights.SemiBold, ink);
        Border b = new Border();
        b.CornerRadius = new CornerRadius(6);
        b.Padding = new Thickness(8, 1, 8, 2);
        b.BorderThickness = new Thickness(1);
        b.Background = Res(fill);
        b.BorderBrush = Res(edge);
        b.VerticalAlignment = VerticalAlignment.Center;
        b.Child = t;
        return b;
    }

    RadioButton Radio(string style, object content, string action)
    {
        RadioButton r = new RadioButton();
        r.Style = (Style)window.FindResource(style);
        r.Content = content;
        r.Checked += delegate
        {
            if (!suppress)
            {
                Enqueue(action);
            }
        };
        return r;
    }

    // Checks a radio button without queuing an action.
    void SetChecked(RadioButton r)
    {
        suppress = true;
        try
        {
            r.IsChecked = true;
        }
        finally
        {
            suppress = false;
        }
    }

    void Check(Dictionary<string, RadioButton> items, string key)
    {
        RadioButton r;
        if (key != null && items.TryGetValue(key, out r))
        {
            SetChecked(r);
            r.BringIntoView();
            return;
        }
        suppress = true;
        try
        {
            foreach (RadioButton other in items.Values)
            {
                other.IsChecked = false;
            }
        }
        finally
        {
            suppress = false;
        }
    }

    void Note(Border box, TextBlock text, string value, int level)
    {
        value = value ?? "";
        text.Text = value;
        int l = KcDraw.Clamp(level, 0, KcDraw.StatusTint.Length - 1);
        box.Background = Res(KcDraw.StatusTint[l]);
        box.BorderBrush = Res(KcDraw.StatusEdge[l]);
        text.Foreground = Res(KcDraw.StatusInk[l]);
        KcUi.SetVisible(box, value.Length > 0);
    }

    void SetButtonsCore(bool close, bool back, bool cancel, bool retry, bool cont, bool start)
    {
        KcUi.SetVisible(closeButton, close);
        KcUi.SetVisible(backButton, back);
        KcUi.SetVisible(cancelButton, cancel);
        KcUi.SetVisible(retryButton, retry);
        KcUi.SetVisible(continueButton, cont);
        KcUi.SetVisible(startButton, start);
    }

    void SetBannerCore(string title, string text, int level)
    {
        int l = KcDraw.Clamp(level, 0, KcDraw.StatusTint.Length - 1);
        bannerTitle.Text = title ?? "";
        bannerText.Text = text ?? "";
        KcUi.SetVisible(bannerText, bannerText.Text.Length > 0);
        banner.Background = Res(KcDraw.StatusTint[l]);
        banner.BorderBrush = Res(KcDraw.StatusEdge[l]);
        bannerMark.Fill = Res(KcDraw.StatusMark[l]);
        bannerTitle.Foreground = Res(KcDraw.StatusInk[l]);
        bannerText.Foreground = Res(KcDraw.StatusInk[l]);
        bannerIcon.Data = Geometry.Parse(KcDraw.StatusIconData[l]);
        KcUi.SetVisible(banner, bannerTitle.Text.Length > 0);
    }

    void FillSteps(Panel panel, List<FrameworkElement> rows, string[] details, int[] states)
    {
        panel.Children.Clear();
        rows.Clear();
        for (int i = 0; i < stepTitles.Length; i++)
        {
            stepStates[i] = AtInt(states, i);
            Grid mark = new Grid();
            mark.Width = 26;
            mark.Height = 26;
            mark.Margin = new Thickness(0, 0, 12, 0);
            mark.VerticalAlignment = VerticalAlignment.Top;
            mark.Children.Add(new Ellipse());
            TextBlock number = Text((i + 1).ToString(), 12.5, FontWeights.Bold, "KcText");
            number.HorizontalAlignment = HorizontalAlignment.Center;
            number.VerticalAlignment = VerticalAlignment.Center;
            mark.Children.Add(number);
            Path icon = new Path();
            icon.Style = (Style)window.FindResource("KcStatusIcon");
            icon.RenderTransformOrigin = new Point(0.5, 0.5);
            icon.RenderTransform = new ScaleTransform(0.8, 0.8);
            icon.HorizontalAlignment = HorizontalAlignment.Center;
            icon.VerticalAlignment = VerticalAlignment.Center;
            mark.Children.Add(icon);
            StackPanel texts = new StackPanel();
            TextBlock t = Text(stepTitles[i], 13.5, FontWeights.SemiBold, "KcText");
            t.TextWrapping = TextWrapping.Wrap;
            texts.Children.Add(t);
            TextBlock d = Text(At(details, i), 12, FontWeights.Normal, "KcTextFaint");
            d.FontFamily = (FontFamily)window.FindResource("KcMonoFont");
            d.TextWrapping = TextWrapping.Wrap;
            d.Margin = new Thickness(0, 2, 0, 0);
            texts.Children.Add(d);
            DockPanel row = new DockPanel();
            row.Margin = new Thickness(0, 0, 0, 12);
            DockPanel.SetDock(mark, Dock.Left);
            row.Children.Add(mark);
            row.Children.Add(texts);
            row.Tag = mark;
            rows.Add(row);
            panel.Children.Add(row);
            UpdateStepRow(rows, i);
        }
    }

    void UpdateStepRow(List<FrameworkElement> rows, int index)
    {
        if (index >= rows.Count)
        {
            return;
        }
        Grid mark = (Grid)rows[index].Tag;
        Ellipse circle = (Ellipse)mark.Children[0];
        TextBlock number = (TextBlock)mark.Children[1];
        Path icon = (Path)mark.Children[2];
        int state = stepStates[index];
        circle.StrokeThickness = 1.5;
        if (state == StepDone || state == StepFailed)
        {
            circle.Fill = Res(state == StepDone ? "KcOkMark" : "KcNgMark");
            circle.Stroke = circle.Fill;
            icon.Data = Geometry.Parse(KcDraw.StatusIconData[state == StepDone ? 1 : 2]);
            icon.Visibility = Visibility.Visible;
            number.Visibility = Visibility.Collapsed;
        }
        else
        {
            bool active = state == StepActive;
            circle.Fill = Res(active ? "KcAccent" : "KcSurface");
            circle.Stroke = Res(active ? "KcAccentLight" : "KcBorder");
            number.Foreground = Res(active ? "KcOnAccent" : "KcTextMuted");
            icon.Visibility = Visibility.Collapsed;
            number.Visibility = Visibility.Visible;
        }
        rows[index].Opacity = state == StepPending ? 0.75 : 1.0;
    }

    void AppendLogCore(string text, int level, bool partial)
    {
        System.Windows.Documents.BlockCollection blocks = logBox.Document.Blocks;
        Brush ink = Res(LineInk[KcDraw.Clamp(level, 0, LineInk.Length - 1)]);
        // follow the end of the log only while it is shown (so a selection to copy is not scrolled away)
        bool atEnd = logBox.VerticalOffset + logBox.ViewportHeight >= logBox.ExtentHeight - 2;
        System.Windows.Documents.Paragraph p;
        if (lastLogPartial && blocks.LastBlock is System.Windows.Documents.Paragraph)
        {
            p = (System.Windows.Documents.Paragraph)blocks.LastBlock;
            p.Inlines.Clear();
        }
        else
        {
            p = new System.Windows.Documents.Paragraph();
            p.Margin = new Thickness(0);
            blocks.Add(p);
            while (blocks.Count > MaxLogLines)
            {
                blocks.Remove(blocks.FirstBlock);
            }
        }
        System.Windows.Documents.Run run = new System.Windows.Documents.Run(text ?? "");
        run.Foreground = ink;
        p.Inlines.Add(run);
        lastLogPartial = partial;
        if (atEnd)
        {
            logBox.ScrollToEnd();
        }
    }

    void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        if (closeGuard && !forceClose)
        {
            e.Cancel = true;
            Enqueue("close");
        }
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
        IntPtr hwnd = new WindowInteropHelper(window).Handle;
        KcUi.ApplyDarkTitleBar(hwnd);
        HwndSource.FromHwnd(hwnd).AddHook(WndProc);
    }

    IntPtr WndProc(IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (KcUi.FilterSystemKeys(msg, wParam))
        {
            handled = true;
        }
        return IntPtr.Zero;
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
