// Hold-tap simulators for keyboard-check ("tap-hold timing" view, hold-tap.ps1).
// ASCII only, C# 5 (Windows PowerShell 5.1 Add-Type treats warnings as errors).
// No WPF and no types shared with InputTestForm.cs, so it is a separate file that pwsh on Linux can also compile
// (tools/tests/hold-tap.Tests.ps1 runs the ZMK and QMK test vectors through it).
//
// KcZmkHoldTapSim: ZMK v0.3.0 app/src/behaviors/behavior_hold_tap.c, with the parts of keymap.c,
//   hid_listener.c, event_manager.c and the system workqueue that decide the order of events.
// KcQmkTapHoldSim: QMK (vial-qmk, the tree the Keyboard Quantizer Mini builds) quantum/action_tapping.c
//   process_tapping, with the mod-tap / layer-tap parts of quantum/action.c.
//
// Times are milliseconds. Inputs are physical key events (position, pressed, time).

using System;
using System.Collections.Generic;

public sealed class KcHtBinding
{
    // kp (Usage, Mods = implicit mods) / mo (Layer) / ht (Behavior, Hold, Tap) / none / other (Label)
    // mods (QMK mod-tap hold: Mods)
    public string Kind = "none";
    public int Usage = -1;
    public int Mods;
    public int Layer = -1;
    public string Label = "";
    public string Behavior = "";
    public string Src = "";
    public KcHtBinding Hold;
    public KcHtBinding Tap;
}

public sealed class KcHtZmkConfig
{
    public string Flavor = "hold-preferred";
    public int Term = 200;
    public int QuickTap = -1;
    public int PriorIdle = -1;
    public bool RetroTap;
    public bool Hwu;
    public bool HwuLinger;
    public bool TriggerOnRelease;
    public int[] TriggerPositions = new int[0];

    public KcHtZmkConfig Clone()
    {
        KcHtZmkConfig c = (KcHtZmkConfig)MemberwiseClone();
        c.TriggerPositions = (int[])TriggerPositions.Clone();
        return c;
    }
}

public sealed class KcHtQmkSettings
{
    public int TappingTerm = 200;
    public bool PermissiveHold;
    public bool HoldOnOtherKeyPress;
    public bool RetroTapping;
    public int QuickTapTerm = 200;
    public bool ChordalHold;
    public int FlowTapTerm;
    public int TapCodeDelay;
    // vial-qmk compiles CHORDAL_HOLD and FLOW_TAP_TERM in (and switches them with the settings above).
    // false = upstream QMK built without them (used by the QMK test vectors).
    public bool ChordalCompiled = true;
    public bool FlowCompiled = true;

    public KcHtQmkSettings Clone()
    {
        return (KcHtQmkSettings)MemberwiseClone();
    }
}

public sealed class KcHtKeymap
{
    public Dictionary<int, Dictionary<int, KcHtBinding>> Keys = new Dictionary<int, Dictionary<int, KcHtBinding>>();
    public Dictionary<string, KcHtZmkConfig> Behaviors = new Dictionary<string, KcHtZmkConfig>(StringComparer.Ordinal);
    // QMK: settings and the chordal hold hand of each position ('L' / 'R' / '*')
    public KcHtQmkSettings Qmk = new KcHtQmkSettings();
    public Dictionary<int, char> Hands = new Dictionary<int, char>();
    // QMK: the matrix cell of each position (keys with the same cell are the same key for QMK). Missing = pos
    public Dictionary<int, int> Cells = new Dictionary<int, int>();

    public void Set(int pos, int layer, KcHtBinding b)
    {
        Dictionary<int, KcHtBinding> on;
        if (!Keys.TryGetValue(pos, out on))
        {
            on = new Dictionary<int, KcHtBinding>();
            Keys[pos] = on;
        }
        on[layer] = b;
    }

    public void SetBehavior(string name, KcHtZmkConfig config)
    {
        Behaviors[name] = config;
    }

    public void SetHand(int pos, char hand)
    {
        Hands[pos] = hand;
    }

    public void SetCell(int pos, int cell)
    {
        Cells[pos] = cell;
    }

    public int Cell(int pos)
    {
        int c;
        if (Cells.TryGetValue(pos, out c)) return c;
        return pos;
    }

    // Copy that shares the bindings but has its own behavior configs / QMK settings.
    public KcHtKeymap WithBehavior(string name, KcHtZmkConfig config)
    {
        KcHtKeymap k = ShallowCopy();
        k.Behaviors[name] = config;
        return k;
    }

    public KcHtKeymap WithQmk(KcHtQmkSettings settings)
    {
        KcHtKeymap k = ShallowCopy();
        k.Qmk = settings;
        return k;
    }

    KcHtKeymap ShallowCopy()
    {
        KcHtKeymap k = new KcHtKeymap();
        k.Keys = Keys;
        k.Hands = Hands;
        k.Cells = Cells;
        k.Qmk = Qmk;
        k.Behaviors = new Dictionary<string, KcHtZmkConfig>(Behaviors, StringComparer.Ordinal);
        return k;
    }

    static readonly KcHtBinding NoneBinding = new KcHtBinding();

    // Highest active layer that has a binding (missing = &trans), or 0.
    public int ResolveLayer(int pos, int[] layersDesc)
    {
        Dictionary<int, KcHtBinding> on;
        if (Keys.TryGetValue(pos, out on))
        {
            for (int i = 0; i < layersDesc.Length; i++)
            {
                if (on.ContainsKey(layersDesc[i])) return layersDesc[i];
            }
        }
        return 0;
    }

    public KcHtBinding At(int pos, int layer)
    {
        Dictionary<int, KcHtBinding> on;
        KcHtBinding b;
        if (Keys.TryGetValue(pos, out on) && on.TryGetValue(layer, out b)) return b;
        return NoneBinding;
    }

    // Highest active layer that has a binding (missing = &trans).
    public KcHtBinding Resolve(int pos, int[] layersDesc)
    {
        Dictionary<int, KcHtBinding> on;
        if (Keys.TryGetValue(pos, out on))
        {
            for (int i = 0; i < layersDesc.Length; i++)
            {
                KcHtBinding b;
                if (on.TryGetValue(layersDesc[i], out b)) return b;
            }
        }
        return NoneBinding;
    }

    public char Hand(int pos)
    {
        char h;
        if (Hands.TryGetValue(pos, out h)) return h;
        return '*';
    }
}

public sealed class KcHtInput
{
    public int Pos;
    public bool Down;
    public long T;
    // filled by the simulators
    public long At = -1;        // when the key event was processed (its timestamp)
    public bool Captured;       // held back while a hold-tap was undecided
    public long ReplayAt = -1;  // when it was released from the capture

    public static KcHtInput Make(int pos, bool down, long t)
    {
        KcHtInput i = new KcHtInput();
        i.Pos = pos;
        i.Down = down;
        i.T = t;
        return i;
    }

    public KcHtInput Copy()
    {
        return Make(Pos, Down, T);
    }
}

public sealed class KcHtDecision
{
    public int Pos;
    public int Index = -1;      // input index of the press
    public long PressT;
    public long DecideT;
    public string Status = "";  // ZMK: tap / hold-timer / hold-interrupt. QMK: tap / hold
    public string Moment = "";  // ZMK: key-up / other-key-down / other-key-up / timer / quick-tap. QMK: see KcQmkTapHoldSim
    public string Flavor = "";
    public string Behavior = "";
    public bool Retro;
    public long RetroT = -1;
    public bool Positional;     // ZMK: hold-trigger-key-positions turned a hold into a tap
    public int FirstOther = -1;
    public int Other = -1;      // the other key that decided it (-1 = none)
}

public sealed class KcHtOutput
{
    public long T;
    public bool Down;
    public string Kind = "key"; // key / layer / other
    public int Usage = -1;
    public int Mods;
    public int Layer = -1;
    public string Label = "";
    public int Pos = -1;
}

public sealed class KcHtResult
{
    public List<KcHtDecision> Decisions = new List<KcHtDecision>();
    public List<KcHtOutput> Hid = new List<KcHtOutput>();
    public List<KcHtInput> Inputs = new List<KcHtInput>();
    public List<string> Lines = new List<string>();
    public long EndT;
    public bool Approx;         // an 'other' binding was used (its effect is only approximated)
}

// ---------------------------------------------------------------------------------------------------------
// ZMK v0.3.0
//
// - Key input is processed as system workqueue work. An input takes two hops (kscan work -> position event
//   work), so a timer that expires at the same time runs first. The timestamp of the position event is the
//   time it is processed.
// - Listeners: position events: hold-tap -> keymap. Keycode events: hold-tap -> HID.
// - While a hold-tap is undecided, other key presses (and releases of keys whose press was captured) are
//   captured and raised again after the decision, starting at the hold-tap listener, with their original
//   timestamps. While another hold-tap becomes undecided during that, each event waits 10ms (k_msleep).
//   Modifier keycode events are also captured.
// - tickMs > 0 reproduces the native_posix tests (10ms ticks): timeouts are rounded up to ticks plus one tick,
//   times are tick multiples, and each input happens a wait (difference of T) after the previous input was
//   processed (kscan_mock).
// ---------------------------------------------------------------------------------------------------------
public sealed class KcZmkHoldTapSim
{
    const int CapturedMax = 40;

    sealed class Ht
    {
        public int Pos;
        public string Status = "undecided";
        public KcHtZmkConfig Cfg;
        public long Ts;
        public int FirstOther = -1;
        public KcHtBinding Hold;
        public KcHtBinding Tap;
        public string Behavior;
        public int Index;
        public Work Timer;
        public KcHtDecision Decision;
    }

    sealed class Work
    {
        public int Kind;    // 0 timer, 1 kscan (hop 1), 2 position event (hop 2)
        public long Ready;
        public int Seq;
        public Ht Ht;
        public int Index;
    }

    sealed class PosEv
    {
        public int Pos;
        public bool State;
        public long Ts;
        public int Index;
    }

    sealed class CodeEv
    {
        public int Usage;
        public int Mods;
        public bool Pressed;
        public long Ts;
        public int Pos;
        public string Label;
    }

    sealed class Cap
    {
        public PosEv Pos;
        public CodeEv Code;
    }

    readonly KcHtKeymap keymap;
    readonly KcHtInput[] events;
    readonly int tick;
    readonly bool trace;
    readonly KcHtResult result = new KcHtResult();
    long clock;
    int seq;
    readonly List<int> layers = new List<int>();
    readonly Dictionary<int, int[]> pressLayers = new Dictionary<int, int[]>();
    readonly List<Ht> active = new List<Ht>();
    Ht undecided;
    readonly Cap[] captured = new Cap[CapturedMax];
    int lastPos = int.MinValue;
    long lastT = -1000000000L;
    readonly List<Work> pending = new List<Work>();
    readonly List<Work> queue = new List<Work>();
    readonly HashSet<int> hidDown = new HashSet<int>();

    KcZmkHoldTapSim(KcHtKeymap keymap, KcHtInput[] events, int tickMs, bool trace)
    {
        this.keymap = keymap;
        this.events = events;
        this.tick = tickMs;
        this.trace = trace;
        layers.Add(0);
    }

    public static KcHtResult Run(KcHtKeymap keymap, KcHtInput[] events, int tickMs, bool trace)
    {
        KcZmkHoldTapSim s = new KcZmkHoldTapSim(keymap, events ?? new KcHtInput[0], tickMs, trace);
        s.Execute();
        return s.result;
    }

    void Line(string text)
    {
        if (trace) result.Lines.Add(text);
    }

    // ---- workqueue

    long Due(long delay)
    {
        if (delay < 0) delay = 0;
        if (tick <= 0) return clock + delay;
        long now = (clock / tick) * tick;
        return now + ((delay + tick - 1) / tick) * tick + tick;
    }

    static int Rank(Work w)
    {
        return w.Kind == 0 ? 0 : 1;
    }

    void MoveReady()
    {
        List<Work> ready = null;
        for (int i = 0; i < pending.Count; i++)
        {
            if (pending[i].Ready <= clock)
            {
                if (ready == null) ready = new List<Work>();
                ready.Add(pending[i]);
            }
        }
        if (ready == null) return;
        foreach (Work w in ready) pending.Remove(w);
        ready.Sort(delegate(Work a, Work b)
        {
            int c = a.Ready.CompareTo(b.Ready);
            if (c != 0) return c;
            c = Rank(a).CompareTo(Rank(b));
            if (c != 0) return c;
            return a.Seq.CompareTo(b.Seq);
        });
        queue.AddRange(ready);
    }

    void Execute()
    {
        KcHtInput[] ev = events;
        for (int i = 0; i < ev.Length; i++)
        {
            KcHtInput info = ev[i].Copy();
            result.Inputs.Add(info);
            if (tick <= 0 || i == 0)
            {
                Work w = new Work();
                w.Kind = 1;
                w.Ready = ev[i].T;
                w.Seq = ++seq;
                w.Index = i;
                pending.Add(w);
            }
        }
        if (ev.Length > 0) clock = ev[0].T;
        int guard = 0;
        while (true)
        {
            if (++guard > 1000000) throw new InvalidOperationException("hold-tap simulation does not end");
            MoveReady();
            if (queue.Count == 0)
            {
                if (pending.Count == 0) break;
                long next = long.MaxValue;
                foreach (Work p in pending)
                {
                    if (p.Ready < next) next = p.Ready;
                }
                if (next > clock) clock = next;
                continue;
            }
            Work w = queue[0];
            queue.RemoveAt(0);
            if (w.Kind == 0)
            {
                w.Ht.Timer = null;
                Decide(w.Ht, "timer");
            }
            else if (w.Kind == 1)
            {
                Work h2 = new Work();
                h2.Kind = 2;
                h2.Ready = clock;
                h2.Seq = w.Seq;
                h2.Index = w.Index;
                queue.Add(h2);
                if (tick > 0 && w.Index + 1 < ev.Length)
                {
                    Work n = new Work();
                    n.Kind = 1;
                    n.Ready = Due(ev[w.Index + 1].T - ev[w.Index].T);
                    n.Seq = ++seq;
                    n.Index = w.Index + 1;
                    pending.Add(n);
                }
            }
            else
            {
                KcHtInput info = result.Inputs[w.Index];
                info.At = clock;
                PosEv pe = new PosEv();
                pe.Pos = info.Pos;
                pe.State = info.Down;
                pe.Ts = clock;
                pe.Index = w.Index;
                RaisePosition(pe);
            }
        }
        result.EndT = clock;
    }

    void AddTimer(Ht ht)
    {
        Work w = new Work();
        w.Kind = 0;
        w.Ready = Due(ht.Ts + ht.Cfg.Term - clock);
        w.Seq = ++seq;
        w.Ht = ht;
        ht.Timer = w;
        pending.Add(w);
    }

    void CancelTimer(Ht ht)
    {
        if (ht.Timer == null) return;
        pending.Remove(ht.Timer);
        queue.Remove(ht.Timer);
        ht.Timer = null;
    }

    // ---- listeners

    void RaisePosition(PosEv ev)
    {
        if (PositionListener(ev)) return;
        Keymap(ev);
    }

    void RaiseKeycode(CodeEv kc)
    {
        if (KeycodeListener(kc)) return;
        HidListener(kc);
    }

    static bool IsMod(int usage)
    {
        return usage >= 0xE0 && usage <= 0xE7;
    }

    void HidListener(CodeEv kc)
    {
        bool isMod = IsMod(kc.Usage);
        int implicitMods = isMod ? 0 : kc.Mods;
        int explicitMods = isMod ? kc.Mods : 0;
        if (kc.Pressed)
        {
            if (!isMod && hidDown.Contains(kc.Usage))
            {
                Line(string.Format("kp_pressed: unregistering usage_page 0x07 keycode 0x{0:X2} since it was already pressed", kc.Usage));
                AddOutput(false, "key", kc.Usage, kc.Mods, -1, kc.Label, kc.Pos);
            }
            hidDown.Add(kc.Usage);
            Line(string.Format("kp_pressed: usage_page 0x07 keycode 0x{0:X2} implicit_mods 0x{1:X2} explicit_mods 0x{2:X2}", kc.Usage, implicitMods, explicitMods));
        }
        else
        {
            hidDown.Remove(kc.Usage);
            Line(string.Format("kp_released: usage_page 0x07 keycode 0x{0:X2} implicit_mods 0x{1:X2} explicit_mods 0x{2:X2}", kc.Usage, implicitMods, explicitMods));
        }
        AddOutput(kc.Pressed, "key", kc.Usage, kc.Mods, -1, kc.Label, kc.Pos);
    }

    void AddOutput(bool down, string kind, int usage, int mods, int layer, string label, int pos)
    {
        KcHtOutput o = new KcHtOutput();
        o.T = clock;
        o.Down = down;
        o.Kind = kind;
        o.Usage = usage;
        o.Mods = mods;
        o.Layer = layer;
        o.Label = label ?? "";
        o.Pos = pos;
        result.Hid.Add(o);
    }

    void StoreLastTapped(long ts)
    {
        if (ts > lastT)
        {
            lastPos = int.MinValue;
            lastT = ts;
        }
    }

    // true = captured
    bool KeycodeListener(CodeEv kc)
    {
        bool isMod = IsMod(kc.Usage);
        if (kc.Pressed && !isMod) StoreLastTapped(kc.Ts);
        Ht u = undecided;
        if (u == null) return false;
        if (!isMod) return false;
        if (u.Cfg.Hwu && u.Status == "undecided") return false;
        Cap c = new Cap();
        c.Code = kc;
        Capture(c);
        return true;
    }

    void Capture(Cap c)
    {
        for (int i = 0; i < CapturedMax; i++)
        {
            if (captured[i] == null)
            {
                captured[i] = c;
                return;
            }
        }
    }

    bool HaveCapturedKeydown(int pos)
    {
        for (int i = 0; i < CapturedMax; i++)
        {
            Cap c = captured[i];
            if (c == null) return false;
            if (c.Pos == null) continue;
            if (c.Pos.Pos == pos && c.Pos.State) return true;
        }
        return false;
    }

    bool PositionListener(PosEv ev)
    {
        UpdateHoldStatusForRetroTap(ev.Pos);
        Ht u = undecided;
        if (u == null) return false;
        if (u.Cfg.TriggerOnRelease != ev.State && u.FirstOther == -1) u.FirstOther = ev.Pos;
        if (u.Pos == ev.Pos) return false;
        if (ev.Ts > u.Ts + u.Cfg.Term) Decide(u, "timer");
        if (undecided == null) return false;
        if (!ev.State && !HaveCapturedKeydown(ev.Pos)) return false;
        Cap c = new Cap();
        c.Pos = ev;
        Capture(c);
        if (ev.Index >= 0) result.Inputs[ev.Index].Captured = true;
        lastOther = ev.Pos;
        Decide(undecided, ev.State ? "other-key-down" : "other-key-up");
        return true;
    }

    int lastOther = -1;

    // ---- keymap

    void Keymap(PosEv ev)
    {
        int[] ls;
        if (ev.State)
        {
            List<int> sorted = new List<int>(layers);
            sorted.Sort();
            sorted.Reverse();
            ls = sorted.ToArray();
            pressLayers[ev.Pos] = ls;
        }
        else if (!pressLayers.TryGetValue(ev.Pos, out ls))
        {
            // released without a press: the default layer (initial zmk_keymap_active_behavior_layer)
            ls = new int[] { 0 };
        }
        KcHtBinding b = keymap.Resolve(ev.Pos, ls);
        Invoke(b, ev.Pos, ev.State, ev.Ts, ev.Index);
    }

    void Invoke(KcHtBinding b, int pos, bool pressed, long ts, int index)
    {
        switch (b.Kind)
        {
            case "kp":
                {
                    CodeEv kc = new CodeEv();
                    kc.Usage = b.Usage;
                    kc.Mods = b.Mods;
                    kc.Pressed = pressed;
                    kc.Ts = ts;
                    kc.Pos = pos;
                    kc.Label = b.Label;
                    RaiseKeycode(kc);
                    break;
                }
            case "mo":
                Line(string.Format("mo_{0}: position {1} layer {2}", pressed ? "pressed" : "released", pos, b.Layer));
                if (pressed)
                {
                    if (!layers.Contains(b.Layer)) layers.Add(b.Layer);
                }
                else if (b.Layer != 0)
                {
                    layers.Remove(b.Layer);
                }
                AddOutput(pressed, "layer", -1, 0, b.Layer, b.Label, pos);
                break;
            case "ht":
                if (pressed) HtPressed(b, pos, ts, index); else HtReleased(pos, ts);
                break;
            case "other":
                if (pressed)
                {
                    StoreLastTapped(ts);
                    result.Approx = true;
                }
                AddOutput(pressed, "other", -1, 0, -1, b.Label, pos);
                break;
        }
    }

    // ---- hold-tap

    KcHtZmkConfig ConfigOf(string name)
    {
        KcHtZmkConfig c;
        if (keymap.Behaviors.TryGetValue(name, out c)) return c;
        return new KcHtZmkConfig();
    }

    void HtPressed(KcHtBinding b, int pos, long ts, int index)
    {
        if (undecided != null)
        {
            Line("ht_binding_pressed: ERROR another hold-tap behavior is undecided.");
            return;
        }
        Ht ht = new Ht();
        ht.Pos = pos;
        ht.Cfg = ConfigOf(b.Behavior);
        ht.Ts = ts;
        ht.Hold = b.Hold ?? new KcHtBinding();
        ht.Tap = b.Tap ?? new KcHtBinding();
        ht.Behavior = b.Behavior;
        ht.Index = index;
        active.Add(ht);
        Line(string.Format("ht_binding_pressed: {0} new undecided hold_tap", pos));
        undecided = ht;
        bool quick = false;
        if (lastT + ht.Cfg.PriorIdle > ts) quick = true;
        else if (lastPos == pos && lastT + ht.Cfg.QuickTap > ts) quick = true;
        if (quick) Decide(ht, "quick-tap");
        Decide(ht, "key-down");
        AddTimer(ht);
    }

    void HtReleased(int pos, long ts)
    {
        Ht ht = null;
        foreach (Ht a in active)
        {
            if (a.Pos == pos)
            {
                ht = a;
                break;
            }
        }
        if (ht == null)
        {
            Line("ht_binding_released: ACTIVE_HOLD_TAP_CLEANED_UP_TOO_EARLY");
            return;
        }
        CancelTimer(ht);
        if (ts > ht.Ts + ht.Cfg.Term) Decide(ht, "timer");
        Decide(ht, "key-up");
        if (ht.Cfg.RetroTap && ht.Status == "hold-timer")
        {
            ReleaseBinding(ht);
            Line(string.Format("decide_retro_tap: {0} retro tap", ht.Pos));
            ht.Status = "tap";
            if (ht.Decision != null)
            {
                ht.Decision.Retro = true;
                ht.Decision.Status = "tap";
                ht.Decision.RetroT = clock;
            }
            PressBinding(ht);
        }
        ReleaseBinding(ht);
        if (ht.Cfg.Hwu && ht.Cfg.HwuLinger) Invoke(ht.Hold, ht.Pos, false, ht.Ts, -1);
        Line(string.Format("ht_binding_released: {0} cleaning up hold-tap", pos));
        active.Remove(ht);
    }

    static string FlavorDecision(string flavor, string moment)
    {
        switch (flavor)
        {
            case "hold-preferred":
                if (moment == "key-up" || moment == "quick-tap") return "tap";
                if (moment == "other-key-down") return "hold-interrupt";
                if (moment == "timer") return "hold-timer";
                break;
            case "balanced":
                if (moment == "key-up" || moment == "quick-tap") return "tap";
                if (moment == "other-key-up") return "hold-interrupt";
                if (moment == "timer") return "hold-timer";
                break;
            case "tap-preferred":
                if (moment == "key-up" || moment == "quick-tap") return "tap";
                if (moment == "timer") return "hold-timer";
                break;
            case "tap-unless-interrupted":
                if (moment == "key-up" || moment == "quick-tap" || moment == "timer") return "tap";
                if (moment == "other-key-down") return "hold-interrupt";
                break;
        }
        return "undecided";
    }

    void Decide(Ht ht, string moment)
    {
        if (ht.Status != "undecided") return;
        if (!object.ReferenceEquals(ht, undecided))
        {
            Line("ht_decide: ERROR found undecided tap hold that is not the active tap hold");
            return;
        }
        KcHtZmkConfig cfg = ht.Cfg;
        if (cfg.Hwu && moment == "key-down")
        {
            Line(string.Format("ht_decide: {0} hold behavior pressed while undecided", ht.Pos));
            Invoke(ht.Hold, ht.Pos, true, ht.Ts, -1);
            return;
        }
        string status = FlavorDecision(cfg.Flavor, moment);
        if (status == "undecided") return;
        ht.Status = status;
        bool positional = false;
        int[] trig = cfg.TriggerPositions ?? new int[0];
        if (trig.Length > 0 && ht.FirstOther != -1 && Array.IndexOf(trig, ht.FirstOther) < 0)
        {
            if (ht.Status != "tap") positional = true;
            ht.Status = "tap";
        }
        Line(string.Format("ht_decide: {0} decided {1} ({2} decision moment {3})", ht.Pos, ht.Status, cfg.Flavor, moment));
        KcHtDecision d = new KcHtDecision();
        d.Pos = ht.Pos;
        d.Index = ht.Index;
        d.PressT = ht.Ts;
        d.DecideT = clock;
        d.Status = ht.Status;
        d.Moment = moment;
        d.Flavor = cfg.Flavor;
        d.Behavior = ht.Behavior;
        d.Positional = positional;
        d.FirstOther = ht.FirstOther;
        d.Other = (moment == "other-key-down" || moment == "other-key-up") ? lastOther : -1;
        ht.Decision = d;
        result.Decisions.Add(d);
        undecided = null;
        PressBinding(ht);
        ReleaseCaptured();
    }

    void PressBinding(Ht ht)
    {
        KcHtZmkConfig cfg = ht.Cfg;
        if (cfg.RetroTap && ht.Status == "hold-timer") return;
        if (ht.Status == "hold-timer" || ht.Status == "hold-interrupt")
        {
            if (cfg.Hwu) return;
            Invoke(ht.Hold, ht.Pos, true, ht.Ts, -1);
        }
        else
        {
            if (cfg.Hwu && !cfg.HwuLinger) Invoke(ht.Hold, ht.Pos, false, ht.Ts, -1);
            // store_last_hold_tapped
            lastPos = ht.Pos;
            lastT = ht.Ts;
            Invoke(ht.Tap, ht.Pos, true, ht.Ts, -1);
        }
    }

    void ReleaseBinding(Ht ht)
    {
        if (ht.Cfg.RetroTap && ht.Status == "hold-timer") return;
        if (ht.Status == "hold-timer" || ht.Status == "hold-interrupt")
        {
            Invoke(ht.Hold, ht.Pos, false, ht.Ts, -1);
        }
        else
        {
            Invoke(ht.Tap, ht.Pos, false, ht.Ts, -1);
        }
    }

    void UpdateHoldStatusForRetroTap(int ignorePos)
    {
        for (int i = 0; i < active.Count; i++)
        {
            Ht ht = active[i];
            if (ht.Pos == ignorePos || !ht.Cfg.RetroTap) continue;
            if (ht.Status == "hold-timer")
            {
                Line(string.Format("update_hold_status_for_retro_tap: Update hold tap {0} status to hold-interrupt", ht.Pos));
                ht.Status = "hold-interrupt";
                PressBinding(ht);
            }
        }
    }

    void ReleaseCaptured()
    {
        if (undecided != null) return;
        for (int i = 0; i < CapturedMax; i++)
        {
            Cap c = captured[i];
            if (c == null) return;
            captured[i] = null;
            if (undecided != null)
            {
                // a new hold-tap became undecided: k_msleep(10) before each event
                clock = Due(10);
            }
            if (c.Code != null)
            {
                RaiseKeycode(c.Code);
            }
            else
            {
                if (c.Pos.Index >= 0)
                {
                    KcHtInput info = result.Inputs[c.Pos.Index];
                    if (info.ReplayAt < 0) info.ReplayAt = clock;
                }
                RaisePosition(c.Pos);
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------------------
// QMK (vial-qmk, Keyboard Quantizer Mini)
//
// - Each input is a matrix scan event with time = the time it is processed (later than the key if the loop
//   was blocked by wait_ms). Without a key change the loop makes a tick event every ms; ticks only matter when
//   the tapping term of the tapping key runs out, so they are made at tapping_key.time + tapping term.
// - process_tapping and the waiting buffer are ported as written, including the vial build's CHORDAL_HOLD and
//   FLOW_TAP_TERM code (switched by the Vial settings). RETRO_SHIFT and auto shift are not built in vial.
// - process_action: mod-tap (register_mods / register_code + wait_ms(tap_code_delay)), layer-tap (layer_on /
//   register_code), MO, plain keys, and retro tapping (action_exec / process_action).
// - Decisions: Status tap / hold. Moment: release (tapped within the term), timeout, permissive (permissive
//   hold), other-press (hold on other key press), chordal (chordal hold: same hand), flow-tap, quick-tap
//   (pressed again within the quick tap term), retro (retro tapping sent the tap on release).
// ---------------------------------------------------------------------------------------------------------
public sealed class KcQmkTapHoldSim
{
    const int WbSize = 8;
    const int RegisteredTapsSize = 8;

    sealed class Rec
    {
        public int Pos = -1;
        public bool Pressed;
        public long Time;
        public bool Tick = true;  // TICK_EVENT (also an empty record = NOEVENT)
        public int TapCount;
        public bool Interrupted;
        public int Index = -1;

        public Rec Clone()
        {
            return (Rec)MemberwiseClone();
        }
    }

    readonly KcHtKeymap keymap;
    readonly KcHtQmkSettings st;
    readonly KcHtInput[] events;
    readonly bool trace;
    readonly KcHtResult result = new KcHtResult();
    long clock;

    Rec tappingKey = new Rec();
    readonly Rec[] wb = new Rec[WbSize];
    int wbHead;
    int wbTail;
    readonly List<int> layers = new List<int>();
    readonly Dictionary<int, int> sourceLayer = new Dictionary<int, int>();
    readonly int[] registeredTaps = new int[RegisteredTapsSize];
    int numRegisteredTaps;
    KcHtBinding flowPrevKeycode;
    long flowPrevTime;
    bool flowExpired = true;
    bool retroPrimed;
    KcHtBinding retroCurrKey;
    int retroCurrMods;
    int retroNextMods;
    int realMods;
    int weakMods;
    readonly List<int> keys = new List<int>();
    readonly Dictionary<int, string> labels = new Dictionary<int, string>();
    int sentMods;
    readonly List<int> sentKeys = new List<int>();
    string moment = "";
    int momentOther = -1;

    KcQmkTapHoldSim(KcHtKeymap keymap, KcHtInput[] events, bool trace)
    {
        this.keymap = keymap;
        this.st = keymap.Qmk ?? new KcHtQmkSettings();
        this.events = events;
        this.trace = trace;
        layers.Add(0);
    }

    public static KcHtResult Run(KcHtKeymap keymap, KcHtInput[] events, bool trace)
    {
        KcQmkTapHoldSim s = new KcQmkTapHoldSim(keymap, events ?? new KcHtInput[0], trace);
        s.Execute();
        return s.result;
    }

    void Execute()
    {
        for (int i = 0; i < events.Length; i++) result.Inputs.Add(events[i].Copy());
        // in time order (same time: in the given order)
        int[] order = new int[events.Length];
        for (int i = 0; i < order.Length; i++) order[i] = i;
        Array.Sort(order, delegate(int a, int b)
        {
            int c = events[a].T.CompareTo(events[b].T);
            return c != 0 ? c : a.CompareTo(b);
        });
        if (events.Length > 0) clock = events[order[0]].T;
        for (int oi = 0; oi < order.Length; oi++)
        {
            int i = order[oi];
            long t = events[i].T;
            RunTicksBefore(t);
            if (t > clock) clock = t;
            Rec r = new Rec();
            r.Pos = events[i].Pos;
            r.Pressed = events[i].Down;
            r.Time = clock;
            r.Tick = false;
            r.Index = i;
            result.Inputs[i].At = clock;
            ActionExec(r);
        }
        RunTicksBefore(long.MaxValue);
        result.EndT = clock;
    }

    // tick events (one per ms without key changes) up to before time t: only the ones that can change something
    void RunTicksBefore(long t)
    {
        int guard = 0;
        while (++guard < 1000)
        {
            long due;
            if (!tappingKey.Tick)
            {
                due = tappingKey.Time + st.TappingTerm;
                if (due <= clock) due = clock + 1;
            }
            else if (wbHead != wbTail)
            {
                due = clock + 1;
            }
            else
            {
                return;
            }
            if (due >= t) return;
            clock = due;
            Rec tick = new Rec();
            tick.Time = clock;
            ActionExec(tick);
        }
    }

    void Line(string text)
    {
        if (trace) result.Lines.Add(text);
    }

    int Next(int i)
    {
        return (i + 1) % WbSize;
    }

    void Wait(int ms)
    {
        if (ms > 0) clock += ms;
    }

    // ---- keymap (layer_switch_get_action / source layer cache)

    int[] LayersDesc()
    {
        List<int> l = new List<int>(layers);
        l.Sort();
        l.Reverse();
        return l.ToArray();
    }

    KcHtBinding CurrentAction(int pos)
    {
        return keymap.Resolve(pos, LayersDesc());
    }

    int CurrentLayer(int pos)
    {
        return keymap.ResolveLayer(pos, LayersDesc());
    }

    int CachedLayer(int pos)
    {
        int l;
        if (sourceLayer.TryGetValue(pos, out l)) return l;
        return 0;
    }

    // get_record_keycode(record, false): the keycode on the cached layer
    KcHtBinding KeycodeOf(Rec r)
    {
        if (r.Tick) return null;
        return keymap.At(r.Pos, CachedLayer(r.Pos));
    }

    static bool IsMtOrLt(KcHtBinding b)
    {
        return b != null && b.Kind == "ht";
    }

    bool IsTapRecord(Rec r)
    {
        if (r.Tick) return false;
        return CurrentAction(r.Pos).Kind == "ht";
    }

    bool KeyEq(int a, int b)
    {
        if (a < 0 || b < 0) return false;
        return keymap.Cell(a) == keymap.Cell(b);
    }

    bool IsTappingRecord(Rec r)
    {
        return !tappingKey.Tick && KeyEq(tappingKey.Pos, r.Pos);
    }

    bool WithinTappingTerm(Rec e)
    {
        return e.Time - tappingKey.Time < st.TappingTerm;
    }

    bool WithinQuickTapTerm(Rec e)
    {
        return e.Time - tappingKey.Time < st.QuickTapTerm;
    }

    // ---- action_exec

    void ActionExec(Rec ev)
    {
        if (!ev.Tick)
        {
            KcHtBinding kc = keymap.At(ev.Pos, CachedLayer(ev.Pos));
            if (ev.Pressed)
            {
                retroPrimed = false;
                retroCurrKey = kc;
            }
            else if (object.ReferenceEquals(retroCurrKey, kc))
            {
                retroPrimed = true;
            }
            if (ev.Pressed)
            {
                weakMods = 0;
                // pre_process_record_quantum: get_record_keycode(record, true) updates the layer cache
                sourceLayer[ev.Pos] = CurrentLayer(ev.Pos);
            }
        }
        ActionTappingProcess(ev);
    }

    void ActionTappingProcess(Rec record)
    {
        if (!ProcessTapping(record))
        {
            if (!record.Tick)
            {
                if (Next(wbHead) == wbTail)
                {
                    // overflow: clear all
                    wbHead = 0;
                    wbTail = 0;
                    tappingKey = new Rec();
                }
                else
                {
                    wb[wbHead] = record.Clone();
                    wbHead = Next(wbHead);
                    if (record.Index >= 0) result.Inputs[record.Index].Captured = true;
                }
            }
        }
        for (; wbTail != wbHead; wbTail = Next(wbTail))
        {
            if (!ProcessTapping(wb[wbTail])) break;
        }
    }

    // ---- process_tapping (quantum/action_tapping.c)

    bool ProcessTapping(Rec keyp)
    {
        if ((st.ChordalCompiled || st.FlowCompiled) && !keyp.Tick && !keyp.Pressed)
        {
            int ri = RegisteredTapFind(keyp.Pos);
            if (ri != -1)
            {
                keyp.TapCount = 1;
                RegisteredTapsDelIndex(ri);
            }
        }

        if (tappingKey.Tick)
        {
            if (keyp.Tick)
            {
                // tick
            }
            else if (keyp.Pressed && IsTapRecord(keyp))
            {
                if (st.FlowCompiled && FlowTapKeyIfWithinTerm(keyp, flowPrevTime)) return true;
                tappingKey = keyp.Clone();
                WaitingBufferScanTap();
            }
            else
            {
                ProcessRecord(keyp);
            }
            return true;
        }

        KcHtBinding tappingKeycode = KeycodeOf(tappingKey);

        if (tappingKey.Pressed)
        {
            if (WithinTappingTerm(keyp))
            {
                if (keyp.Tick) return true;
                if (tappingKey.TapCount == 0)
                {
                    if (IsTappingRecord(keyp) && !keyp.Pressed)
                    {
                        // first tap!
                        tappingKey.TapCount = 1;
                        Decided("release", -1);
                        ProcessRecord(tappingKey);
                        keyp.TapCount = tappingKey.TapCount;
                        keyp.Interrupted = tappingKey.Interrupted;
                        if (st.FlowCompiled)
                        {
                            long prevTime = tappingKey.Time;
                            for (; wbTail != wbHead; wbTail = Next(wbTail))
                            {
                                Rec record = wb[wbTail];
                                if (!record.Pressed) break;
                                long nextTime = record.Time;
                                if (!IsTapRecord(record)) ProcessRecord(record);
                                else if (!FlowTapKeyIfWithinTerm(record, prevTime)) break;
                                prevTime = nextTime;
                            }
                        }
                        return false;
                    }
                    else if (st.ChordalCompiled && IsMtOrLt(tappingKeycode) && !keyp.Pressed && WaitingBufferTyped(keyp) && !GetChordalHold(tappingKey, keyp))
                    {
                        // key release that is not a chord with the tapping key
                        tappingKey.TapCount = 1;
                        RegisteredTapsAdd(tappingKey.Pos);
                        Decided("chordal", keyp.Pos);
                        ProcessRecord(tappingKey);
                        tappingKey = new Rec();
                        WaitingBufferChordalHoldTapsUntil(keyp.Pos);
                        return false;
                    }
                    else if (!keyp.Pressed && WaitingBufferTyped(keyp) && st.PermissiveHold)
                    {
                        // permissive hold: a key pressed and released within the term
                        Decided("permissive", keyp.Pos);
                        ProcessRecord(tappingKey);
                        if (st.ChordalCompiled)
                        {
                            int firstTap = WaitingBufferFindChordalHoldTap();
                            if (firstTap < WbSize)
                            {
                                for (; wbTail != firstTap; wbTail = Next(wbTail)) ProcessRecord(wb[wbTail]);
                            }
                            WaitingBufferChordalHoldTapsUntil(keyp.Pos);
                        }
                        tappingKey = new Rec();
                        return false;
                    }
                    else if (!keyp.Pressed && !WaitingBufferTyped(keyp))
                    {
                        // release of a key pressed before tapping starts: modifiers and layers are kept back
                        KcHtBinding action = CurrentAction(keyp.Pos);
                        if (action.Kind == "kp" && action.Usage >= 0xE0 && action.Usage <= 0xE7) return false;
                        if (action.Kind == "mo") return false;
                        if (action.Kind == "ht")
                        {
                            if (action.Hold != null && action.Hold.Kind == "mo") return false;
                            if (keyp.TapCount == 0) return false;
                        }
                        ProcessRecord(keyp);
                        return true;
                    }
                    else
                    {
                        if (keyp.Pressed)
                        {
                            tappingKey.Interrupted = true;
                            if (st.ChordalCompiled && IsMtOrLt(tappingKeycode) && !GetChordalHold(tappingKey, keyp))
                            {
                                tappingKey.Interrupted = false;
                                if (!IsTapRecord(keyp))
                                {
                                    tappingKey.TapCount = 1;
                                    RegisteredTapsAdd(tappingKey.Pos);
                                    Decided("chordal", keyp.Pos);
                                    ProcessRecord(tappingKey);
                                    tappingKey = new Rec();
                                }
                            }
                            else if (st.HoldOnOtherKeyPress)
                            {
                                Decided("other-press", keyp.Pos);
                                ProcessRecord(tappingKey);
                                if (st.ChordalCompiled && wbTail != wbHead && IsTapRecord(wb[wbTail]))
                                {
                                    tappingKey = wb[wbTail].Clone();
                                    wbTail = Next(wbTail);
                                }
                                else
                                {
                                    tappingKey = new Rec();
                                }
                                if (st.ChordalCompiled) WaitingBufferProcessRegular();
                            }
                        }
                        return false;
                    }
                }
                else
                {
                    // tap_count > 0
                    if (IsTappingRecord(keyp) && !keyp.Pressed)
                    {
                        keyp.TapCount = tappingKey.TapCount;
                        keyp.Interrupted = tappingKey.Interrupted;
                        ProcessRecord(keyp);
                        tappingKey = keyp.Clone();
                        return true;
                    }
                    else if (IsTapRecord(keyp) && keyp.Pressed)
                    {
                        if (tappingKey.TapCount > 1) UnregisterTappingKey(keyp.Time);
                        tappingKey = keyp.Clone();
                        WaitingBufferScanTap();
                        return true;
                    }
                    else
                    {
                        ProcessRecord(keyp);
                        return true;
                    }
                }
            }
            else
            {
                // after TAPPING_TERM
                if (tappingKey.TapCount == 0)
                {
                    Decided("timeout", -1);
                    ProcessRecord(tappingKey);
                    tappingKey = new Rec();
                    return false;
                }
                else
                {
                    if (keyp.Tick) return true;
                    if (IsTappingRecord(keyp) && !keyp.Pressed)
                    {
                        keyp.TapCount = tappingKey.TapCount;
                        keyp.Interrupted = tappingKey.Interrupted;
                        ProcessRecord(keyp);
                        tappingKey = new Rec();
                        return true;
                    }
                    else if (IsTapRecord(keyp) && keyp.Pressed)
                    {
                        if (tappingKey.TapCount > 1) UnregisterTappingKey(keyp.Time);
                        tappingKey = keyp.Clone();
                        WaitingBufferScanTap();
                        return true;
                    }
                    else
                    {
                        ProcessRecord(keyp);
                        return true;
                    }
                }
            }
        }
        else
        {
            // "released" tapping key state
            if (WithinTappingTerm(keyp))
            {
                if (keyp.Tick) return true;
                if (keyp.Pressed)
                {
                    if (IsTappingRecord(keyp))
                    {
                        if (WithinQuickTapTerm(keyp) && !tappingKey.Interrupted && tappingKey.TapCount > 0)
                        {
                            // sequential tap
                            keyp.TapCount = tappingKey.TapCount;
                            keyp.Interrupted = tappingKey.Interrupted;
                            if (keyp.TapCount < 15) keyp.TapCount += 1;
                            Decided("quick-tap", -1, keyp);
                            ProcessRecord(keyp);
                            tappingKey = keyp.Clone();
                            return true;
                        }
                        tappingKey = keyp.Clone();
                        return true;
                    }
                    else if (IsTapRecord(keyp))
                    {
                        if (st.FlowCompiled && FlowTapKeyIfWithinTerm(keyp, flowPrevTime))
                        {
                            tappingKey = new Rec();
                            return true;
                        }
                        tappingKey = keyp.Clone();
                        WaitingBufferScanTap();
                        return true;
                    }
                    else
                    {
                        tappingKey.Interrupted = true;
                        ProcessRecord(keyp);
                        return true;
                    }
                }
                else
                {
                    ProcessRecord(keyp);
                    return true;
                }
            }
            else
            {
                // timeout: reset the state machine
                tappingKey = new Rec();
                return false;
            }
        }
    }

    void UnregisterTappingKey(long time)
    {
        Rec r = new Rec();
        r.Pos = tappingKey.Pos;
        r.Time = time;
        r.Pressed = false;
        r.Tick = false;
        r.TapCount = tappingKey.TapCount;
        r.Interrupted = tappingKey.Interrupted;
        ProcessRecord(r);
    }

    void WaitingBufferScanTap()
    {
        if (tappingKey.TapCount > 0 || !tappingKey.Pressed) return;
        for (int i = wbTail; i != wbHead; i = Next(i))
        {
            Rec candidate = wb[i];
            if (!candidate.Tick && KeyEq(candidate.Pos, tappingKey.Pos) && !candidate.Pressed && WithinTappingTerm(candidate))
            {
                tappingKey.TapCount = 1;
                candidate.TapCount = 1;
                Decided("release", -1);
                ProcessRecord(tappingKey);
                return;
            }
        }
    }

    bool WaitingBufferTyped(Rec ev)
    {
        for (int i = wbTail; i != wbHead; i = Next(i))
        {
            if (KeyEq(ev.Pos, wb[i].Pos) && ev.Pressed != wb[i].Pressed) return true;
        }
        return false;
    }

    // ---- chordal hold

    bool GetChordalHold(Rec tapHold, Rec other)
    {
        if (!st.ChordalHold) return true;
        char tapHoldHand = keymap.Hand(tapHold.Pos);
        if (tapHoldHand == '*') return true;
        char otherHand = keymap.Hand(other.Pos);
        return otherHand == '*' || tapHoldHand != otherHand;
    }

    int WaitingBufferFindChordalHoldTap()
    {
        Rec prev = tappingKey;
        KcHtBinding prevKeycode = KeycodeOf(tappingKey);
        int firstTap = WbSize;
        for (int i = wbTail; i != wbHead; i = Next(i))
        {
            Rec cur = wb[i];
            KcHtBinding curKeycode = KeycodeOf(cur);
            if (!cur.Pressed || !IsMtOrLt(prevKeycode)) break;
            else if (GetChordalHold(prev, cur)) firstTap = i;
            prev = cur;
            prevKeycode = curKeycode;
        }
        return firstTap;
    }

    void WaitingBufferChordalHoldTapsUntil(int pos)
    {
        while (wbTail != wbHead)
        {
            Rec record = wb[wbTail];
            if (record.Pressed && IsTapRecord(record))
            {
                record.TapCount = 1;
                RegisteredTapsAdd(record.Pos);
                Decided("chordal", -1, record);
            }
            ProcessRecord(record);
            wbTail = Next(wbTail);
            if (KeyEq(pos, record.Pos) && record.Pressed) break;
        }
    }

    void WaitingBufferProcessRegular()
    {
        for (; wbTail != wbHead; wbTail = Next(wbTail))
        {
            if (IsTapRecord(wb[wbTail])) break;
            ProcessRecord(wb[wbTail]);
        }
    }

    void RegisteredTapsAdd(int pos)
    {
        if (numRegisteredTaps >= RegisteredTapsSize) numRegisteredTaps = 0;
        registeredTaps[numRegisteredTaps] = pos;
        numRegisteredTaps++;
    }

    int RegisteredTapFind(int pos)
    {
        for (int i = 0; i < numRegisteredTaps; i++)
        {
            if (KeyEq(registeredTaps[i], pos)) return i;
        }
        return -1;
    }

    void RegisteredTapsDelIndex(int i)
    {
        if (i < numRegisteredTaps)
        {
            numRegisteredTaps--;
            if (i < numRegisteredTaps) registeredTaps[i] = registeredTaps[numRegisteredTaps];
        }
    }

    // ---- flow tap

    static int TapKeycode(KcHtBinding b)
    {
        if (b == null) return -1;
        if (b.Kind == "ht") return (b.Tap != null && b.Tap.Kind == "kp" && b.Tap.Mods == 0) ? b.Tap.Usage : -1;
        if (b.Kind == "kp" && b.Mods == 0) return b.Usage;
        return -1;
    }

    bool IsFlowTapKey(KcHtBinding b)
    {
        // MOD_MASK_CG | MOD_BIT_LALT: hotkeys disable flow tap
        if ((realMods & (0x01 | 0x08 | 0x10 | 0x80 | 0x04)) != 0) return false;
        int k = TapKeycode(b);
        return k == 0x2C || (k >= 0x04 && k <= 0x1D) || k == 0x37 || k == 0x36 || k == 0x33 || k == 0x38;
    }

    void FlowTapUpdateLastEvent(Rec record)
    {
        KcHtBinding keycode = KeycodeOf(record);
        if (record.TapCount == 0 && (wbTail != wbHead || (tappingKey.Pressed && tappingKey.TapCount == 0))) return;
        if (!record.Pressed && keycode != null)
        {
            if (keycode.Kind == "kp" && keycode.Usage >= 0xE0 && keycode.Usage <= 0xE7 && keycode.Mods == 0) return;
            if (keycode.Kind == "mo") return;
            if (keycode.Kind == "ht" && record.TapCount == 0) return;
        }
        flowPrevKeycode = keycode;
        flowPrevTime = record.Time;
        flowExpired = false;
    }

    bool FlowTapKeyIfWithinTerm(Rec record, long prevTime)
    {
        long idle = record.Time - prevTime;
        if (flowExpired || idle >= 500) return false;
        KcHtBinding keycode = KeycodeOf(record);
        if (IsMtOrLt(keycode))
        {
            int term = (IsFlowTapKey(keycode) && IsFlowTapKey(flowPrevKeycode)) ? st.FlowTapTerm : 0;
            if (term > 500) term = 500;
            if (idle < term)
            {
                record.TapCount = 1;
                RegisteredTapsAdd(record.Pos);
                Decided("flow-tap", -1, record);
                ProcessRecord(record);
                return true;
            }
        }
        return false;
    }

    // ---- decisions

    // the next ProcessRecord of a tap-hold press settles it: remember why
    void Decided(string why, int other)
    {
        Decided(why, other, null);
    }

    Rec momentRec;

    void Decided(string why, int other, Rec rec)
    {
        moment = why;
        momentOther = other;
        momentRec = rec;
    }

    void RecordDecision(Rec record, KcHtBinding b)
    {
        KcHtDecision d = new KcHtDecision();
        d.Pos = record.Pos;
        d.Index = record.Index;
        d.PressT = record.Index >= 0 && record.Index < result.Inputs.Count ? result.Inputs[record.Index].At : record.Time;
        d.DecideT = clock;
        d.Status = record.TapCount > 0 ? "tap" : "hold";
        string m = moment;
        if (m == "" || (momentRec != null && !object.ReferenceEquals(momentRec, record)))
        {
            // settled without a remembered reason: a tap from the buffer scan, or a hold after the term
            m = record.TapCount > 0 ? "release" : "timeout";
        }
        d.Moment = m;
        d.Other = momentOther;
        d.Behavior = b.Behavior;
        d.Flavor = QmkFlavor(st);
        result.Decisions.Add(d);
        Line(string.Format("decide: {0} {1} ({2})", record.Pos, d.Status, m));
        moment = "";
        momentOther = -1;
        momentRec = null;
    }

    public static string QmkFlavor(KcHtQmkSettings s)
    {
        if (s.HoldOnOtherKeyPress) return "hold-on-other-key-press";
        if (s.PermissiveHold) return "permissive-hold";
        return "default";
    }

    // ---- process_record / process_action (quantum/action.c)

    void ProcessRecord(Rec record)
    {
        if (record.Tick) return;
        if (record.Index >= 0 && record.Index < result.Inputs.Count)
        {
            KcHtInput info = result.Inputs[record.Index];
            if (info.Captured && info.ReplayAt < 0) info.ReplayAt = clock;
        }
        if (st.FlowCompiled) FlowTapUpdateLastEvent(record);
        int layer;
        if (record.Pressed)
        {
            layer = CurrentLayer(record.Pos);
            sourceLayer[record.Pos] = layer;
        }
        else
        {
            layer = CachedLayer(record.Pos);
        }
        KcHtBinding b = keymap.At(record.Pos, layer);
        ProcessAction(record, b);
    }

    void ProcessAction(Rec record, KcHtBinding b)
    {
        int tapCount = record.TapCount;
        bool pressed = record.Pressed;
        switch (b.Kind)
        {
            case "kp":
                if (pressed)
                {
                    if (b.Mods != 0)
                    {
                        if (b.Usage >= 0xE0 && b.Usage <= 0xE7) realMods |= b.Mods; else weakMods |= b.Mods;
                        SendReport();
                    }
                    RegisterCode(b.Usage, b.Label);
                }
                else
                {
                    UnregisterCode(b.Usage);
                    if (b.Mods != 0)
                    {
                        if (b.Usage >= 0xE0 && b.Usage <= 0xE7) realMods &= ~b.Mods; else weakMods &= ~b.Mods;
                        SendReport();
                    }
                }
                break;
            case "mo":
                if (pressed) LayerOn(b.Layer, b.Label, record.Pos); else LayerOff(b.Layer, b.Label, record.Pos);
                break;
            case "ht":
                if (pressed) RecordDecision(record, b);
                if (b.Hold != null && b.Hold.Kind == "mo")
                {
                    KcHtBinding hold = b.Hold ?? new KcHtBinding();
                    if (pressed)
                    {
                        if (tapCount > 0) RegisterTap(b);
                        else LayerOn(hold.Layer, hold.Label, record.Pos);
                    }
                    else
                    {
                        if (tapCount > 0)
                        {
                            Wait(st.TapCodeDelay);
                            UnregisterTap(b);
                        }
                        else
                        {
                            LayerOff(hold.Layer, hold.Label, record.Pos);
                        }
                    }
                }
                else
                {
                    int mods = HoldMods(b.Hold);
                    if (pressed)
                    {
                        if (tapCount > 0) RegisterTap(b); else RegisterMods(mods);
                        Wait(st.TapCodeDelay);
                    }
                    else
                    {
                        if (tapCount > 0)
                        {
                            Wait(st.TapCodeDelay);
                            UnregisterTap(b);
                        }
                        else
                        {
                            UnregisterMods(mods);
                        }
                    }
                }
                break;
            case "other":
                AddOutput(pressed, "other", -1, 0, -1, b.Label, record.Pos);
                break;
        }
        // retro tapping (is_tap_action)
        if (b.Kind == "ht")
        {
            if (pressed)
            {
                if (tapCount > 0)
                {
                    retroPrimed = false;
                }
                else
                {
                    retroCurrMods = retroNextMods;
                    retroNextMods = realMods;
                }
            }
            else
            {
                KcHtBinding eventKeycode = keymap.At(record.Pos, CachedLayer(record.Pos));
                int currMods = realMods;
                if (tapCount > 0)
                {
                    retroPrimed = false;
                }
                else if (object.ReferenceEquals(retroCurrKey, eventKeycode))
                {
                    if (st.RetroTapping && retroPrimed)
                    {
                        KcHtDecision last = null;
                        for (int i = result.Decisions.Count - 1; i >= 0; i--)
                        {
                            if (result.Decisions[i].Pos == record.Pos)
                            {
                                last = result.Decisions[i];
                                break;
                            }
                        }
                        if (last != null)
                        {
                            last.Retro = true;
                            last.RetroT = clock;
                        }
                        Line(string.Format("retro tap: {0}", record.Pos));
                        RegisterMods(retroCurrMods);
                        Wait(st.TapCodeDelay);
                        RegisterTap(b);
                        Wait(st.TapCodeDelay);
                        UnregisterTap(b);
                        Wait(st.TapCodeDelay);
                        UnregisterMods(retroCurrMods);
                    }
                    retroPrimed = false;
                }
                retroNextMods = currMods;
            }
        }
    }

    // ---- HID

    // mod-tap: the mods of the hold ('mods', or a modifier key binding)
    static int HoldMods(KcHtBinding hold)
    {
        if (hold == null) return 0;
        if (hold.Kind == "kp" && hold.Usage >= 0xE0 && hold.Usage <= 0xE7) return (1 << (hold.Usage - 0xE0)) | hold.Mods;
        return hold.Mods;
    }

    void RegisterTap(KcHtBinding b)
    {
        KcHtBinding t = b.Tap ?? new KcHtBinding();
        if (t.Kind == "kp") RegisterCode(t.Usage, t.Label);
    }

    void UnregisterTap(KcHtBinding b)
    {
        KcHtBinding t = b.Tap ?? new KcHtBinding();
        if (t.Kind == "kp") UnregisterCode(t.Usage);
    }

    void RegisterCode(int usage, string label)
    {
        if (usage < 0) return;
        if (label != null && label.Length > 0) labels[usage] = label;
        if (usage >= 0xE0 && usage <= 0xE7) realMods |= 1 << (usage - 0xE0);
        else if (!keys.Contains(usage)) keys.Add(usage);
        SendReport();
    }

    void UnregisterCode(int usage)
    {
        if (usage < 0) return;
        if (usage >= 0xE0 && usage <= 0xE7) realMods &= ~(1 << (usage - 0xE0));
        else keys.Remove(usage);
        SendReport();
    }

    void RegisterMods(int mods)
    {
        if (mods == 0) return;
        realMods |= mods;
        SendReport();
    }

    void UnregisterMods(int mods)
    {
        if (mods == 0) return;
        realMods &= ~mods;
        SendReport();
    }

    void LayerOn(int layer, string label, int pos)
    {
        if (layer < 0) return;
        if (!layers.Contains(layer)) layers.Add(layer);
        AddOutput(true, "layer", -1, 0, layer, label, pos);
    }

    void LayerOff(int layer, string label, int pos)
    {
        if (layer <= 0) return;
        layers.Remove(layer);
        AddOutput(false, "layer", -1, 0, layer, label, pos);
    }

    static readonly string[] ModLabels = { "Ctrl", "Shift", "Alt", "Win", "RCtrl", "RShift", "RAlt", "RWin" };

    // send_keyboard_report: only when the report changed. Output = the differences.
    void SendReport()
    {
        int mods = realMods | weakMods;
        bool changed = mods != sentMods || keys.Count != sentKeys.Count;
        if (!changed)
        {
            foreach (int k in keys)
            {
                if (!sentKeys.Contains(k))
                {
                    changed = true;
                    break;
                }
            }
        }
        if (!changed) return;
        for (int bit = 0; bit < 8; bit++)
        {
            int m = 1 << bit;
            if ((sentMods & m) != 0 && (mods & m) == 0) AddOutput(false, "key", 0xE0 + bit, 0, -1, ModLabels[bit], -1);
        }
        foreach (int k in sentKeys)
        {
            if (!keys.Contains(k)) AddOutput(false, "key", k, 0, -1, LabelOf(k), -1);
        }
        for (int bit = 0; bit < 8; bit++)
        {
            int m = 1 << bit;
            if ((sentMods & m) == 0 && (mods & m) != 0) AddOutput(true, "key", 0xE0 + bit, 0, -1, ModLabels[bit], -1);
        }
        foreach (int k in keys)
        {
            if (!sentKeys.Contains(k)) AddOutput(true, "key", k, 0, -1, LabelOf(k), -1);
        }
        sentMods = mods;
        sentKeys.Clear();
        sentKeys.AddRange(keys);
        if (trace)
        {
            List<int> all = new List<int>();
            for (int bit = 0; bit < 8; bit++)
            {
                if ((mods & (1 << bit)) != 0) all.Add(0xE0 + bit);
            }
            all.AddRange(keys);
            all.Sort();
            if (all.Count == 0)
            {
                Line("report: (empty)");
            }
            else
            {
                string[] parts = new string[all.Count];
                for (int i = 0; i < all.Count; i++) parts[i] = all[i].ToString("X2");
                Line("report: " + string.Join(" ", parts));
            }
        }
    }

    string LabelOf(int usage)
    {
        string l;
        if (labels.TryGetValue(usage, out l)) return l;
        return "0x" + usage.ToString("X2");
    }

    void AddOutput(bool down, string kind, int usage, int mods, int layer, string label, int pos)
    {
        KcHtOutput o = new KcHtOutput();
        o.T = clock;
        o.Down = down;
        o.Kind = kind;
        o.Usage = usage;
        o.Mods = mods;
        o.Layer = layer;
        o.Label = label ?? "";
        o.Pos = pos;
        result.Hid.Add(o);
    }
}

// ---------------------------------------------------------------------------------------------------------
// Results as text, and sweeps (move one input, or the tapping term, by 1ms and group the same results)
// ---------------------------------------------------------------------------------------------------------
public sealed class KcHtSegment
{
    public long From;           // [From, To]
    public long To;
    public string Outcome = ""; // status of the target + strokes (same outcome = same segment)
    public string Status = "";  // decision of the target press
    public string Moment = "";
    public string Text = "";    // strokes
    public long DecideT = -1;   // decision time at From
}

public static class KcHtText
{
    static readonly string[] ModNames = { "Ctrl", "Shift", "Alt", "Win" };

    static int Fold(int mods)
    {
        return (mods | (mods >> 4)) & 0x0F;
    }

    static string ModsText(int folded)
    {
        List<string> n = new List<string>();
        for (int i = 0; i < 4; i++)
        {
            if ((folded & (1 << i)) != 0) n.Add(ModNames[i]);
        }
        return string.Join("+", n.ToArray());
    }

    // What the PC gets, as strokes: "Ctrl+J", "A J", a modifier or a layer held without other keys: "Ctrl" / "(VIM_BASE)"
    public static string Strokes(KcHtResult r)
    {
        List<string> parts = new List<string>();
        int[] modCount = new int[8];
        Dictionary<int, bool> usedLayer = new Dictionary<int, bool>();
        Dictionary<int, string> layerLabel = new Dictionary<int, string>();
        bool[] usedMod = new bool[8];
        foreach (KcHtOutput o in r.Hid)
        {
            if (o.Kind == "layer")
            {
                if (o.Down)
                {
                    usedLayer[o.Layer] = false;
                    layerLabel[o.Layer] = o.Label;
                }
                else if (usedLayer.ContainsKey(o.Layer))
                {
                    if (!usedLayer[o.Layer]) parts.Add("(" + o.Label + ")");
                    usedLayer.Remove(o.Layer);
                }
                continue;
            }
            bool isMod = o.Kind == "key" && o.Usage >= 0xE0 && o.Usage <= 0xE7;
            if (isMod)
            {
                int bit = o.Usage - 0xE0;
                if (o.Down)
                {
                    if (modCount[bit] == 0) usedMod[bit] = false;
                    modCount[bit]++;
                }
                else if (modCount[bit] > 0)
                {
                    modCount[bit]--;
                    if (modCount[bit] == 0 && !usedMod[bit]) parts.Add(ModsText(Fold(1 << bit)));
                }
                continue;
            }
            if (!o.Down) continue;
            int held = 0;
            for (int i = 0; i < 8; i++)
            {
                if (modCount[i] > 0)
                {
                    held |= 1 << i;
                    usedMod[i] = true;
                }
            }
            List<int> keys = new List<int>(usedLayer.Keys);
            foreach (int k in keys) usedLayer[k] = true;
            int folded = Fold(held | o.Mods);
            string label = o.Label;
            if (o.Mods != 0)
            {
                // the label of a key with implicit mods already has them ("Ctrl+Z")
                folded = Fold(held);
                if (folded != 0) label = ModsText(folded) + "+" + label;
            }
            else if (folded != 0)
            {
                label = ModsText(folded) + "+" + label;
            }
            parts.Add(label);
        }
        for (int i = 0; i < 8; i++)
        {
            if (modCount[i] > 0 && !usedMod[i]) parts.Add(ModsText(Fold(1 << i)));
        }
        foreach (KeyValuePair<int, bool> kv in usedLayer)
        {
            if (!kv.Value) parts.Add("(" + layerLabel[kv.Key] + ")");
        }
        return string.Join(" ", parts.ToArray());
    }

    public static KcHtDecision DecisionFor(KcHtResult r, int index)
    {
        foreach (KcHtDecision d in r.Decisions)
        {
            if (d.Index == index) return d;
        }
        return null;
    }

    public static string Outcome(KcHtResult r, int index)
    {
        KcHtDecision d = DecisionFor(r, index);
        string status = d == null ? "" : d.Status;
        return status + "|" + Strokes(r);
    }
}

public static class KcHtSweep
{
    public static KcHtResult Run(string engine, KcHtKeymap keymap, KcHtInput[] inputs)
    {
        if (engine == "qmk") return KcQmkTapHoldSim.Run(keymap, inputs, false);
        return KcZmkHoldTapSim.Run(keymap, inputs, 0, false);
    }

    static KcHtSegment Segment(KcHtResult r, long at, int target)
    {
        KcHtSegment s = new KcHtSegment();
        s.From = at;
        s.To = at;
        KcHtDecision d = KcHtText.DecisionFor(r, target);
        s.Status = d == null ? "" : d.Status;
        s.Moment = d == null ? "" : d.Moment;
        s.DecideT = d == null ? -1 : d.DecideT;
        s.Text = KcHtText.Strokes(r);
        s.Outcome = KcHtText.Outcome(r, target);
        return s;
    }

    static void Add(List<KcHtSegment> list, KcHtSegment s)
    {
        if (list.Count > 0 && list[list.Count - 1].Outcome == s.Outcome)
        {
            list[list.Count - 1].To = s.To;
            return;
        }
        list.Add(s);
    }

    // Move input #index to each time from..to (1ms steps). target = input index of the press whose decision is shown.
    public static KcHtSegment[] VaryInput(string engine, KcHtKeymap keymap, KcHtInput[] inputs, int index, long from, long to, int target)
    {
        List<KcHtSegment> list = new List<KcHtSegment>();
        if (index < 0 || index >= inputs.Length) return list.ToArray();
        KcHtInput[] copy = new KcHtInput[inputs.Length];
        for (int i = 0; i < inputs.Length; i++) copy[i] = inputs[i].Copy();
        for (long t = from; t <= to; t++)
        {
            copy[index].T = t;
            Add(list, Segment(Run(engine, keymap, copy), t, target));
        }
        return list.ToArray();
    }

    // Change the tapping term from..to. ZMK: the config of the behavior; QMK: the tapping term setting.
    public static KcHtSegment[] VaryTerm(string engine, KcHtKeymap keymap, string behavior, KcHtInput[] inputs, int from, int to, int target)
    {
        List<KcHtSegment> list = new List<KcHtSegment>();
        for (int term = from; term <= to; term++)
        {
            KcHtKeymap k;
            if (engine == "qmk")
            {
                KcHtQmkSettings q = keymap.Qmk.Clone();
                q.TappingTerm = term;
                k = keymap.WithQmk(q);
            }
            else
            {
                KcHtZmkConfig c;
                if (!keymap.Behaviors.TryGetValue(behavior, out c)) c = new KcHtZmkConfig();
                c = c.Clone();
                c.Term = term;
                k = keymap.WithBehavior(behavior, c);
            }
            Add(list, Segment(Run(engine, k, inputs), term, target));
        }
        return list.ToArray();
    }
}
