// Headless pointing pipeline. ASCII only; C# 5 / Windows PowerShell 5.1.
// References: pinned xy-accel/aml-threshold modules; ZMK v0.3.0 scaler/temp-layer;
// keyball39 via keymap.c and lib/keyball/keyball.c; QMK auto mouse state machine.
// Inputs are ordered X then Y(sync) driver frames, before listener transforms.
// This models firmware arithmetic and a virtual report clock, not a sensor or transport.
using System;
using System.Collections.Generic;

public sealed class KcPointerConfig
{
    public string Engine = "zmk";
    public int MinFactor = 500, MaxFactor = 1300, SpeedThreshold = 1000, SpeedMax = 4000;
    public int XNumerator = 1, XDenominator = 1, YNumerator = 1, YDenominator = 1;
    public int ScrollNumerator = 1, ScrollDenominator = 16;
    // Transform bits are simulator-owned: invert X=1, invert Y=2, swap X/Y=4.
    public int Transform, ScrollTransform;
    public int ScrollXSign = 1, ScrollYSign = 1;
    public int AmlThreshold = 10, AmlTimeoutMs = 10000, PriorIdleMs = 200;
    public int ReportIntervalMs = 8, ScrollInhibitorMs = 50, DebounceMs = 25;
    public int[] ExcludedPositions = new int[0];
    // Driver-side scroll conversion is accepted only after its arithmetic is modeled.
    public bool ScrollSupported = true;

    public KcPointerConfig Clone() { return (KcPointerConfig)MemberwiseClone(); }

    public void Validate()
    {
        if (Engine != "zmk" && Engine != "keyball") throw new ArgumentException("Unknown pointer engine: " + Engine);
        if (MinFactor < 100 || MinFactor > 1000 || MaxFactor < 1000 || MaxFactor > 4000 ||
            SpeedThreshold <= 0 || SpeedMax <= SpeedThreshold) throw new ArgumentException("Invalid acceleration configuration");
        if (XNumerator <= 0 || XDenominator <= 0 || YNumerator <= 0 || YDenominator <= 0 ||
            ScrollNumerator <= 0 || ScrollDenominator <= 0) throw new ArgumentException("Pointer scalers must be positive");
        if (Transform < 0 || Transform > 7 || ScrollTransform < 0 || ScrollTransform > 7 ||
            Math.Abs(ScrollXSign) != 1 || Math.Abs(ScrollYSign) != 1) throw new ArgumentException("Unsupported pointer transform");
        if (AmlThreshold < 0 || AmlThreshold > 32767 || AmlTimeoutMs <= 0 || PriorIdleMs < 0 ||
            ReportIntervalMs <= 0 || ScrollInhibitorMs < 0 || DebounceMs < 0) throw new ArgumentException("Invalid AML timing");
        if (Engine == "keyball")
        {
            int lo = MinFactor * 256 / 1000, hi = MaxFactor * 256 / 1000;
            int threshold = SpeedThreshold * 16 * ReportIntervalMs / 1000;
            int max = SpeedMax * 16 * ReportIntervalMs / 1000;
            if (threshold <= 0 || max <= threshold || (256 - lo) * threshold > 65535 ||
                (hi - 256) * (max - threshold) > 65535) throw new ArgumentException("Unsupported Keyball Q8 acceleration constants");
            double sx = (double)XNumerator / XDenominator, sy = (double)YNumerator / YDenominator;
            if (sx < 0.5 || sx > 2 || sy < 0.5 || sy > 2) throw new ArgumentException("Keyball axis scalers must be 0.5-2");
        }
    }
}

public sealed class KcMouseReport
{
    public long Time;
    public int X, Y, Wheel, HWheel, Buttons;
    public string Side = "right", Reason = "move";
}

public sealed class KcPointerLayerTransition
{
    public long Time;
    public bool Active;
    public string Reason;
}

public sealed class KcPointerSim
{
    sealed class Slot
    {
        public KcPointerConfig Config;
        public long LastSync, WindowStart, LastMove;
        public int WindowDistance, Speed, Factor, ReportX, ReportY;
        public int AccelX, AccelY, ScaleX, ScaleY, ScrollX, ScrollY;
        public int SumX, SumY, PendingX, PendingY;
        public bool Armed;
    }

    readonly Dictionary<string, Slot> slots = new Dictionary<string, Slot>();
    readonly KcPointerConfig config;
    long now, lastKey, lastKeycode, activeTime, amlDeadline = -1, nextPoll;
    long scrollChanged;
    int mouseKeys;
    bool scroll, observedLayerActive;
    public bool AmlActive { get; private set; }
    public int Buttons { get; private set; }
    public long Now { get { return now; } }
    public List<KcMouseReport> Reports = new List<KcMouseReport>();
    public List<KcPointerLayerTransition> Transitions = new List<KcPointerLayerTransition>();

    public KcPointerSim(KcPointerConfig configuration)
    {
        if (configuration == null) throw new ArgumentNullException("configuration");
        configuration.Validate();
        config = configuration.Clone();
        nextPoll = config.ReportIntervalMs;
        AddSide("right", configuration);
    }

    public void AddSide(string side, KcPointerConfig configuration)
    {
        if (String.IsNullOrEmpty(side)) throw new ArgumentException("Pointer side is required");
        configuration.Validate();
        if (configuration.Engine != config.Engine) throw new ArgumentException("Mixed pointer engines are unsupported");
        if (now != 0) throw new InvalidOperationException("Add pointer sides before advancing time");
        slots[side] = new Slot { Config = configuration.Clone(), Factor = configuration.MinFactor };
    }

    public long NextDeadline
    {
        get
        {
            if (config.Engine == "keyball") return nextPoll;
            return amlDeadline;
        }
    }

    static int Clamp(long value, int lo, int hi) { return (int)Math.Max(lo, Math.Min(hi, value)); }
    static int Distance(int x, int y)
    {
        int ax = Math.Abs(x), ay = Math.Abs(y);
        return ax > ay ? ax + ay / 2 : ay + ax / 2;
    }
    static int Sqrt(long value)
    {
        int root = (int)Math.Sqrt(value);
        while ((long)(root + 1) * (root + 1) <= value) root++;
        while ((long)root * root > value) root--;
        return root;
    }
    static void Transform(ref int x, ref int y, int bits)
    {
        if ((bits & 4) != 0) { int tmp = x; x = y; y = tmp; }
        if ((bits & 1) != 0) x = -x;
        if ((bits & 2) != 0) y = -y;
    }
    static int Scale(int value, int numerator, int denominator, ref int remainder)
    {
        // ZMK's intermediate is int16_t, including its wrap on overflow.
        int total = unchecked((short)(value * numerator + remainder));
        int result = total / denominator;
        remainder = total - result * denominator;
        return result;
    }
    static int Q8(int value, int factor, ref int remainder)
    {
        long total = (long)value * factor + remainder;
        long result = total >> 8; // AVR signed arithmetic shift: floor, including negatives.
        remainder = (int)(total & 255);
        return Clamp(result, -32767, 32767);
    }
    static int ZmkFactor(KcPointerConfig c, int speed)
    {
        if (speed >= c.SpeedMax) return c.MaxFactor;
        if (speed <= c.SpeedThreshold) return c.MinFactor + (int)((long)(1000 - c.MinFactor) * speed / c.SpeedThreshold);
        return 1000 + (int)((long)(c.MaxFactor - 1000) * (speed - c.SpeedThreshold) / (c.SpeedMax - c.SpeedThreshold));
    }
    static int KeyballFactor(KcPointerConfig c, int speed)
    {
        int min = c.MinFactor * 256 / 1000, max = c.MaxFactor * 256 / 1000;
        int threshold = c.SpeedThreshold * 16 * c.ReportIntervalMs / 1000;
        int ceiling = c.SpeedMax * 16 * c.ReportIntervalMs / 1000;
        if (speed >= ceiling) return max;
        if (speed <= threshold) return min + (256 - min) * speed / threshold;
        return 256 + (max - 256) * (speed - threshold) / (ceiling - threshold);
    }

    public void AdvanceTo(long time)
    {
        if (time < now || time < 0) throw new ArgumentException("Pointer time must be nonnegative and monotonic");
        if (config.Engine == "keyball")
        {
            while (nextPoll <= time)
            {
                now = nextPoll;
                nextPoll += config.ReportIntervalMs;
                PollKeyball();
            }
        }
        else if (amlDeadline >= 0 && amlDeadline <= time)
        {
            now = amlDeadline;
            Deactivate("aml_timeout");
        }
        now = time;
    }

    void Activate(string reason)
    {
        if (!AmlActive)
        {
            AmlActive = true;
            observedLayerActive = true;
            Transitions.Add(new KcPointerLayerTransition { Time = now, Active = true, Reason = reason });
        }
        activeTime = now;
        amlDeadline = now + config.AmlTimeoutMs;
    }
    void Deactivate(string reason)
    {
        if (AmlActive)
        {
            AmlActive = false;
            observedLayerActive = false;
            Transitions.Add(new KcPointerLayerTransition { Time = now, Active = false, Reason = reason });
        }
        amlDeadline = -1;
    }
    static void ResetGate(Slot s) { s.Armed = false; s.SumX = 0; s.SumY = 0; }

    public void SetScroll(long time, bool active)
    {
        AdvanceTo(time);
        if (active != scroll) scrollChanged = now;
        scroll = active;
    }

    // Mirror external layer changes (&to, toggles). The keyboard already emitted
    // that transition, so cancel our timer without synthesizing another output.
    public void ObserveLayer(long time, bool active)
    {
        AdvanceTo(time);
        observedLayerActive = active;
        if (!active) { AmlActive = false; amlDeadline = -1; }
    }

    public void Key(long time, bool down, bool modifier, bool mouseRelated)
    {
        AdvanceTo(time);
        lastKey = now;
        if (config.Engine == "zmk")
        {
            // The threshold processor sees all physical positions, including releases.
            if (down && !mouseRelated && config.ExcludedPositions.Length > 0) Deactivate("aml_key");
            return;
        }
        if (mouseRelated)
        {
            mouseKeys = Math.Max(0, mouseKeys + (down ? 1 : -1));
            lastKey = 0; // QMK mouse keys clear the typing-delay timer.
        }
        else if (down)
        {
            Deactivate(modifier ? "aml_modifier" : "aml_key");
            mouseKeys = 0;
            activeTime = 0;
        }
    }

    public void Keycode(long time, long timestamp)
    {
        AdvanceTo(time);
        lastKeycode = timestamp;
    }

    void TempLayer(string reason)
    {
        if (AmlActive || now - lastKeycode >= config.PriorIdleMs) Activate(reason);
    }

    public void Button(long time, int button, bool down)
    {
        AdvanceTo(time);
        if (button < 1 || button > 8) throw new ArgumentException("Mouse button must be 1-8");
        int bit = 1 << (button - 1);
        if (down) Buttons |= bit; else Buttons &= ~bit;
        if (config.Engine == "zmk") TempLayer("aml_button");
        Emit("right", 0, 0, 0, 0, "button", true);
    }

    void Emit(string side, int x, int y, int wheel, int hWheel, string reason, bool force)
    {
        if (!force && x == 0 && y == 0 && wheel == 0 && hWheel == 0) return;
        Reports.Add(new KcMouseReport { Time = now, Side = side, X = x, Y = y, Wheel = wheel,
            HWheel = hWheel, Buttons = Buttons, Reason = reason });
    }

    public void Move(long time, int x, int y, bool asScroll) { MoveSide(time, "right", x, y, asScroll); }

    public void MoveSide(long time, string side, int x, int y, bool asScroll)
    {
        AdvanceTo(time);
        Slot s;
        if (!slots.TryGetValue(side, out s)) throw new ArgumentException("Unknown pointer side: " + side);
        if (x < -32767 || x > 32767 || y < -32767 || y > 32767) throw new ArgumentException("Pointer frame exceeds signed 16-bit range");
        if (asScroll && !s.Config.ScrollSupported) throw new NotSupportedException("This driver's raw scroll conversion is not modeled");
        SetScroll(time, asScroll);
        if (config.Engine == "keyball")
        {
            s.PendingX = Clamp((long)s.PendingX + x, -32768, 32767);
            s.PendingY = Clamp((long)s.PendingY + y, -32768, 32767);
            return;
        }
        KcPointerConfig c = s.Config;
        if (asScroll)
        {
            TempLayer("aml_scroll"); // The processor precedes scaling, even for a zero wheel output.
            Transform(ref x, ref y, c.ScrollTransform);
            int h = Scale(x * c.ScrollXSign, c.ScrollNumerator, c.ScrollDenominator, ref s.ScrollX);
            int v = Scale(y * c.ScrollYSign, c.ScrollNumerator, c.ScrollDenominator, ref s.ScrollY);
            Emit(side, 0, 0, Clamp(v, -127, 127), Clamp(h, -127, 127), "scroll", false);
            return;
        }
        Transform(ref x, ref y, c.Transform);
        x = Scale(x, c.XNumerator, c.XDenominator, ref s.ScaleX);
        y = Scale(y, c.YNumerator, c.YDenominator, ref s.ScaleY);
        // Transform swaps event codes, not their delivery order: sync stays on the original Y.
        if ((c.Transform & 4) == 0)
        {
            x = ZmkAxis(s, x, true, false);
            y = ZmkAxis(s, y, false, true);
            GateZmk(s, x, true); GateZmk(s, y, false);
        }
        else
        {
            y = ZmkAxis(s, y, false, false);
            x = ZmkAxis(s, x, true, true);
            GateZmk(s, y, false); GateZmk(s, x, true);
        }
        Emit(side, x, y, 0, 0, "move", false);
    }

    int ZmkAxis(Slot s, int value, bool xAxis, bool sync)
    {
        if (s.LastSync == 0 || now - s.LastSync > 50)
        {
            s.Speed = 0; s.Factor = s.Config.MinFactor;
            s.ReportX = 0; s.ReportY = 0; s.WindowStart = now - 50; s.WindowDistance = 0;
        }
        if (xAxis) s.ReportX += value; else s.ReportY += value;
        long total = (long)value * s.Factor + (xAxis ? s.AccelX : s.AccelY);
        long output = total / 1000;
        int residual = (int)(total - output * 1000);
        if (xAxis) s.AccelX = residual; else s.AccelY = residual;
        if (sync)
        {
            int x = Math.Min(Math.Abs(s.ReportX), 32767), y = Math.Min(Math.Abs(s.ReportY), 32767);
            s.WindowDistance = Math.Min(s.WindowDistance + Sqrt((long)x * x + (long)y * y), 32767);
            s.ReportX = 0; s.ReportY = 0; s.LastSync = now;
            long elapsed = now - s.WindowStart;
            if (elapsed >= 8)
            {
                int speed = s.WindowDistance * 1000 / (int)Math.Min(elapsed, 50);
                s.Speed = (s.Speed + speed) / 2;
                s.Factor = ZmkFactor(s.Config, s.Speed);
                s.WindowStart = now; s.WindowDistance = 0;
            }
        }
        return Clamp(output, -32768, 32767);
    }

    void GateZmk(Slot s, int value, bool xAxis)
    {
        if (AmlActive || observedLayerActive) { ResetGate(s); TempLayer("aml_move"); return; }
        if (now - lastKey < config.PriorIdleMs) { ResetGate(s); return; }
        if (value == 0) return;
        if (now - s.LastMove > 100) ResetGate(s);
        s.LastMove = now;
        if (!s.Armed)
        {
            if (xAxis) s.SumX = Clamp((long)s.SumX + value, -32768, 32767);
            else s.SumY = Clamp((long)s.SumY + value, -32768, 32767);
            if (Distance(s.SumX, s.SumY) < config.AmlThreshold) return;
            s.Armed = true;
        }
        TempLayer("aml_threshold");
    }

    void PollKeyball()
    {
        int totalX = 0, totalY = 0, totalV = 0, totalH = 0;
        foreach (KeyValuePair<string, Slot> pair in slots)
        {
            Slot s = pair.Value;
            KcPointerConfig c = s.Config;
            if (now - scrollChanged < c.ScrollInhibitorMs) { s.PendingX = 0; s.PendingY = 0; }
            int x = s.PendingX, y = s.PendingY, v = 0, h = 0;
            if (scroll)
            {
                // The residual is raw motion and survives until consumed or an inhibitor clears it.
                int rx = x * c.ScrollNumerator / c.ScrollDenominator;
                int ry = y * c.ScrollNumerator / c.ScrollDenominator;
                s.PendingX -= rx * c.ScrollDenominator / c.ScrollNumerator;
                s.PendingY -= ry * c.ScrollDenominator / c.ScrollNumerator;
                Transform(ref rx, ref ry, c.ScrollTransform);
                h = Clamp(rx * c.ScrollXSign, -127, 127); v = Clamp(ry * c.ScrollYSign, -127, 127);
                x = 0; y = 0;
            }
            else
            {
                s.PendingX = 0; s.PendingY = 0;
                Transform(ref x, ref y, c.Transform);
                int scaleX = (int)(((long)c.XNumerator * 256 + c.XDenominator / 2) / c.XDenominator);
                int scaleY = (int)(((long)c.YNumerator * 256 + c.YDenominator / 2) / c.YDenominator);
                x = Q8(x, scaleX, ref s.ScaleX); y = Q8(y, scaleY, ref s.ScaleY);
                s.Speed = (s.Speed + Math.Min(Distance(x, y), 1023) * 16) / 2;
                int factor = KeyballFactor(c, s.Speed);
                x = Clamp(Q8(x, factor, ref s.AccelX), -127, 127);
                y = Clamp(Q8(y, factor, ref s.AccelY), -127, 127);
            }
            totalX += x; totalY += y; totalV += v; totalH += h;
            Emit(pair.Key, x, y, v, h, scroll ? "scroll" : "move", false);
        }
        if (now - activeTime <= config.DebounceMs || now - lastKey <= config.PriorIdleMs) return;
        bool active = Buttons != 0 || totalH != 0 || totalV != 0;
        Slot gate = slots["right"];
        if (active || AmlActive)
        {
            ResetGate(gate);
            active = active || totalX != 0 || totalY != 0;
        }
        else if (totalX != 0 || totalY != 0)
        {
            if (now - gate.LastMove > 100) ResetGate(gate);
            gate.LastMove = now;
            gate.SumX += totalX; gate.SumY += totalY;
            active = Distance(gate.SumX, gate.SumY) >= config.AmlThreshold;
            if (active) ResetGate(gate);
        }
        if (active || mouseKeys > 0) Activate("aml_move");
        else if (AmlActive && now - activeTime > config.AmlTimeoutMs) Deactivate("aml_timeout");
    }
}
