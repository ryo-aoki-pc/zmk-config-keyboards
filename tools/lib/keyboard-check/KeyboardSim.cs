// Deterministic headless behavior runtime. ASCII and C# 5 for Windows PowerShell 5.1.
// Hold-tap decisions and event capture remain in the reference-tested firmware ports.
using System;
using System.Collections.Generic;

public sealed class KcSimEvent
{
    public long T;
    public string Kind = "pointer";
    public string Side = "right";
    public int Layer;
    public bool Down;
    public int X;
    public int Y;
    public int Wheel;
    public int HWheel;
    public int Buttons;
    public string Label = "";
}

public interface IKcSimPeripheral
{
    void Attach(KcSimContext context);
    void Key(int pos, bool down, KcHtBinding binding);
    void Event(KcSimEvent ev);
    void Button(int button, bool down);
    void Output(KcHtOutput output);
}

public sealed class KcSimContext
{
    readonly IKcHtHost host;
    readonly KcHtKeymap map;
    internal KcSimContext(IKcHtHost host, KcHtKeymap map) { this.host = host; this.map = map; }
    public long Now { get { return host.Now; } }
    public int[] Layers { get { return host.ActiveLayers; } }
    public KcHtBinding Resolve(int pos) { return map.Resolve(pos, Layers); }
    public void Schedule(long at, Action action) { host.Schedule(at, action); }
    public void SetLayer(int layer, bool active, string reason) { host.SetLayer(layer, active, reason, -1); }
    public void Mouse(int x, int y, int wheel, int hWheel, int buttons, string reason)
    {
        KcHtOutput o = new KcHtOutput(); o.Kind = "mouse";
        o.X = x; o.Y = y; o.Wheel = wheel; o.HWheel = hWheel; o.Buttons = buttons; o.Label = reason;
        host.Emit(o);
    }
}

public static class KcKeyboardSim
{
    public static KcHtResult Run(string engine, KcHtKeymap map, KcHtInput[] keys,
                                KcSimEvent[] auxiliary, long endMs, bool trace)
    {
        return Run(engine, map, keys, auxiliary, endMs, trace, null);
    }
    public static KcHtResult Run(string engine, KcHtKeymap map, KcHtInput[] keys,
                                KcSimEvent[] auxiliary, long endMs, bool trace, IKcSimPeripheral peripheral)
    {
        if (engine != "zmk" && engine != "qmk") throw new ArgumentException("Unknown simulator engine: " + engine);
        if (map == null) throw new ArgumentNullException("map");
        if (endMs < 0 || endMs == long.MaxValue) throw new ArgumentOutOfRangeException("endMs");
        keys = keys ?? new KcHtInput[0]; auxiliary = auxiliary ?? new KcSimEvent[0];
        long last = -1;
        HashSet<int> down = new HashSet<int>();
        foreach (KcHtInput key in keys)
        {
            if (key == null || key.T < 0 || key.T < last || key.T > endMs)
                throw new ArgumentException("Key times must be nonnegative, ordered, and at or before endMs.");
            if (!map.Keys.ContainsKey(key.Pos)) throw new ArgumentException("Unknown key position: " + key.Pos);
            if (key.Down ? !down.Add(key.Pos) : !down.Remove(key.Pos))
                throw new ArgumentException("Duplicate press or unmatched release at position " + key.Pos);
            last = key.T;
        }
        last = -1;
        foreach (KcSimEvent ev in auxiliary)
        {
            if (ev == null || ev.T < 0 || ev.T < last || ev.T > endMs)
                throw new ArgumentException("Auxiliary times must be nonnegative, ordered, and at or before endMs.");
            last = ev.T;
        }
        KcSimRuntime ext = new KcSimRuntime(engine, map, auxiliary, peripheral);
        KcHtResult raw = engine == "zmk"
            ? KcZmkHoldTapSim.Run(map, keys, 0, trace, endMs, ext)
            : KcQmkTapHoldSim.Run(map, keys, trace, endMs, ext);
        KcHtResult result = ext.Result;
        result.Decisions = raw.Decisions; result.Inputs = raw.Inputs; result.Lines = raw.Lines;
        result.EndT = endMs; result.Approx = raw.Approx;
        result.Hid.RemoveAll(delegate(KcHtOutput o) { return o.T > endMs; });
        result.Decisions.RemoveAll(delegate(KcHtDecision d) { return d.DecideT > endMs; });
        if (result.Approx) throw new NotSupportedException("Simulation used an approximate binding.");
        return result;
    }
}

internal sealed class KcSimRuntime : IKcHtExtension, IKcQmkOverrideHost
{
    sealed class Morph
    {
        public KcHtBinding Binding;
        public bool Masked;
    }
    sealed class Dance
    {
        public KcHtBinding Binding;
        public KcHtBinding Selected;
        public int Pos;
        public int Count;
        public int Generation;
        public int CapturedMods;
        public bool Down;
        public bool Finished;
        public bool Interrupted;
        public long Timestamp;
        public int Index;
    }
    sealed class MacroAction
    {
        public KcHtBinding Binding;
        public bool Down;
        public int Pos;
        public int Delay;
    }
    readonly string engine;
    readonly KcHtKeymap map;
    readonly KcSimEvent[] auxiliary;
    readonly IKcSimPeripheral peripheral;
    IKcHtHost host;
    KcSimContext context;
    readonly Dictionary<string, Morph> morphs = new Dictionary<string, Morph>();
    readonly Dictionary<int, Dance> dances = new Dictionary<int, Dance>();
    readonly Dictionary<string, List<MacroAction>> macroReleases = new Dictionary<string, List<MacroAction>>();
    readonly Queue<MacroAction> macroQueue = new Queue<MacroAction>();
    bool macroRunning;
    readonly HashSet<int> reportedLayers = new HashSet<int>(new int[] { 0 });
    readonly int[] explicitMods = new int[8];
    readonly Dictionary<int, int> implicitMods = new Dictionary<int, int>();
    KcQmkOverrideSim overrides;
    bool overrideBypass;
    int overrideWeakMods;
    int zmkImplicit;
    int maskedMods;
    int reportedMods;
    int recursion;
    int buttons;
    public readonly KcHtResult Result = new KcHtResult();

    public KcSimRuntime(string engine, KcHtKeymap map, KcSimEvent[] auxiliary, IKcSimPeripheral peripheral)
    { this.engine = engine; this.map = map; this.auxiliary = auxiliary; this.peripheral = peripheral; }

    public void Attach(IKcHtHost host)
    {
        this.host = host; context = new KcSimContext(host, map);
        if (engine == "qmk") overrides = new KcQmkOverrideSim(map.Overrides, this);
        if (peripheral != null) peripheral.Attach(context);
        foreach (KcSimEvent item in auxiliary)
        {
            KcSimEvent ev = item;
            host.Schedule(ev.T, delegate {
                if (ev.Kind == "layer") host.SetLayer(ev.Layer, ev.Down, ev.Label, -1);
                else if (peripheral != null) peripheral.Event(ev);
                else throw new NotSupportedException("Pointer events require a configured pointer peripheral.");
            });
        }
    }

    public void BeforePosition(int pos, bool down, long timestamp)
    {
        if (peripheral != null) peripheral.Key(pos, down, map.Resolve(pos, host.ActiveLayers));
    }

    public void BeforeKeymap(int pos, bool down, long timestamp)
    {
        if (!down) return;
        List<Dance> waiting = new List<Dance>(dances.Values);
        foreach (Dance dance in waiting)
        {
            if (dance.Pos != pos && !dance.Finished)
            {
                dance.Interrupted = true; dance.Timestamp = timestamp; FinishDance(dance);
                if (engine == "qmk") ((KcQmkTapHoldSim)host).RemoveWeakModifiers(255);
            }
        }
    }

    static string Identity(KcHtBinding b, int pos)
    {
        return pos.ToString() + ":" + (b.Behavior.Length == 0 ? b.GetHashCode().ToString() : b.Behavior);
    }
    void Child(KcHtBinding b, int pos, bool down, long timestamp, int index)
    {
        if (b == null) throw new ArgumentException("Missing nested behavior binding.");
        if (++recursion > 64) throw new InvalidOperationException("Recursive behavior binding.");
        try { host.InvokeBinding(b, pos, down, timestamp, index); }
        finally { recursion--; }
    }
    int ExplicitMods()
    {
        int mods = 0;
        for (int i = 0; i < 8; i++) if (explicitMods[i] > 0) mods |= 1 << i;
        return mods;
    }
    int EffectiveMods()
    {
        int mods = ExplicitMods() & ~maskedMods;
        if (engine == "zmk") mods |= zmkImplicit;
        else foreach (int implicitMask in implicitMods.Values) mods |= implicitMask;
        return (mods | overrideWeakMods) & 255;
    }
    void Add(KcHtOutput o)
    {
        Result.Hid.Add(o);
        if (peripheral != null && o.Kind != "key") peripheral.Output(o);
    }
    void ReportModifiers(KcHtOutput source)
    {
        int mods = EffectiveMods();
        for (int bit = 0; bit < 8; bit++)
        {
            int flag = 1 << bit;
            if (((reportedMods ^ mods) & flag) == 0) continue;
            bool down = (mods & flag) != 0;
            if (down) reportedMods |= flag; else reportedMods &= ~flag;
            KcHtOutput o = new KcHtOutput(); o.T = source.T; o.Kind = "key";
            o.Usage = 224 + bit; o.Down = down; o.Mods = reportedMods; o.Pos = source.Pos;
            o.Label = "modifier"; o.ActiveLayers = source.ActiveLayers;
            Add(o);
        }
    }
    public void Output(KcHtOutput raw)
    {
        if (peripheral != null && raw.Kind == "key") peripheral.Output(raw);
        bool repeat = raw.Kind == "repeat-release";
        if (raw.Kind == "layer")
        {
            if (raw.Down ? reportedLayers.Add(raw.Layer) : reportedLayers.Remove(raw.Layer)) Add(raw);
            return;
        }
        if (raw.Kind != "key" && !repeat) { Add(raw); return; }
        if (raw.Usage >= 224 && raw.Usage <= 231)
        {
            int bit = raw.Usage - 224;
            if (!raw.Down && explicitMods[bit] == 0) return;
            if (raw.Down) explicitMods[bit]++; else explicitMods[bit]--;
            if (engine == "zmk")
            {
                for (int i = 0; i < 8; i++) if ((raw.Mods & (1 << i)) != 0)
                { if (raw.Down) explicitMods[i]++; else if (explicitMods[i] > 0) explicitMods[i]--; }
                zmkImplicit = 0;
            }
            ReportModifiers(raw);
            return;
        }
        bool wasDown = implicitMods.ContainsKey(raw.Usage);
        if (raw.Down)
        {
            implicitMods[raw.Usage] = raw.Mods;
            if (engine == "zmk") zmkImplicit = raw.Mods;
        }
        else if (engine == "zmk" && !repeat && !map.SeparateModRelease) zmkImplicit = 0;
        ReportModifiers(raw);
        if (raw.Down || wasDown)
        {
            KcHtOutput o = new KcHtOutput(); o.T = raw.T; o.Kind = "key"; o.Usage = raw.Usage;
            o.Down = raw.Down; o.Mods = EffectiveMods(); o.Label = raw.Label; o.Pos = raw.Pos;
            o.ActiveLayers = raw.ActiveLayers; Add(o);
        }
        if (!raw.Down)
        {
            implicitMods.Remove(raw.Usage);
            if (engine == "zmk" && !repeat) zmkImplicit = 0;
            ReportModifiers(raw);
        }
    }

    public bool Invoke(KcHtBinding b, int pos, bool down, long timestamp, int index)
    {
        if (b == null) throw new ArgumentException("Missing behavior binding.");
        if (overrides != null && !overrideBypass && (recursion == 0 || (b.Kind != "kp" && b.Kind != "mods"))
            && overrides.Process(b, pos, down)) return true;
        switch (b.Kind)
        {
            case "kp":
                if (b.Usage < 0 || b.Usage > 255) throw new NotSupportedException("Only keyboard HID page 0x07 usages are supported.");
                return false;
            case "ht":
                if (engine == "zmk" && !map.Behaviors.ContainsKey(b.Behavior))
                    throw new ArgumentException("Missing hold-tap configuration: " + b.Behavior);
                return false;
            case "mo": return false;
            case "mods":
                for (int bit = 0; bit < 8; bit++) if ((b.Mods & (1 << bit)) != 0)
                { KcHtBinding mod = new KcHtBinding(); mod.Kind = "kp"; mod.Usage = 224 + bit; Child(mod, pos, down, timestamp, index); }
                return true;
            case "none": case "trans": return true;
            case "to":
                if (down)
                {
                    foreach (int layer in host.ActiveLayers) if (layer != 0 && layer != b.Layer)
                        host.SetLayer(layer, false, b.Label, pos);
                    host.SetLayer(b.Layer, true, b.Label, pos);
                }
                return true;
            case "tog":
                if (down) host.SetLayer(b.Layer, Array.IndexOf(host.ActiveLayers, b.Layer) < 0, b.Label, pos);
                return true;
            case "button":
                if (b.Usage < 1 || b.Usage > 8) throw new ArgumentException("Mouse buttons must be numbered 1 through 8.");
                if (peripheral != null) peripheral.Button(b.Usage, down);
                else
                {
                    if (down) buttons |= 1 << (b.Usage - 1); else buttons &= ~(1 << (b.Usage - 1));
                    context.Mouse(0, 0, 0, 0, buttons, b.Label);
                }
                return true;
            case "morph":
                RequireEngine("zmk", b);
                MorphBinding(b, pos, down, timestamp, index); return true;
            case "dance": RequireEngine("zmk", b); DanceBinding(b, pos, down, timestamp, index); return true;
            case "qdance": RequireEngine("qmk", b); DanceBinding(b, pos, down, timestamp, index); return true;
            case "macro": RequireEngine("zmk", b); MacroBinding(b, pos, down); return true;
            case "qmacro": RequireEngine("qmk", b); if (down) QmkMacro(b, pos); return true;
            default: throw new NotSupportedException("Unsupported " + engine + " behavior at position " + pos + ": " + b.Kind + " " + b.Src + " " + b.Label);
        }
    }
    public long Now { get { return host.Now; } }
    public int RawModifiers { get { return ((KcQmkTapHoldSim)host).RealModifiers; } }
    public int HighestLayer { get { return host.ActiveLayers[0]; } }
    public int TapCodeDelay { get { return map.Qmk.TapCodeDelay; } }
    public void Schedule(long at, Action action) { host.Schedule(at, action); }
    public void Delay(int ms) { ((KcQmkTapHoldSim)host).Delay(ms); }
    public void OverrideModifiers(int suppressed, int weak) { maskedMods = suppressed; overrideWeakMods = weak; }
    public void ReportOverrideModifiers()
    {
        KcHtOutput report = new KcHtOutput(); report.T = host.Now; report.ActiveLayers = host.ActiveLayers;
        ReportModifiers(report);
    }
    public void ClearRealModifiers(int mask) { ((KcQmkTapHoldSim)host).ClearModifiers(mask); }
    public void OverrideKey(KcHtBinding b, int pos, bool down)
    {
        bool saved = overrideBypass; overrideBypass = true;
        try { Child(b, pos, down, host.Now, -1); } finally { overrideBypass = saved; }
    }
    public void OverrideMacro(KcHtBinding b, int pos) { QmkMacro(b, pos); }

    void RequireEngine(string expected, KcHtBinding b)
    {
        if (engine != expected) throw new NotSupportedException(b.Kind + " is a " + expected + " behavior, not a " + engine + " behavior.");
    }
    void MorphBinding(KcHtBinding b, int pos, bool down, long timestamp, int index)
    {
        string identity = b.Behavior.Length == 0 ? b.GetHashCode().ToString() : b.Behavior;
        Morph state;
        if (down)
        {
            if (b.Bindings.Length != 2) throw new ArgumentException("Mod-morph needs exactly two bindings.");
            if (morphs.ContainsKey(identity)) throw new InvalidOperationException("Mod-morph is already pressed.");
            state = new Morph(); state.Masked = (ExplicitMods() & b.MaskMods) != 0;
            state.Binding = b.Bindings[state.Masked ? 1 : 0]; morphs[identity] = state;
            if (state.Masked)
            {
                // ZMK has one global mask; a nested morph replaces it.
                maskedMods = b.MaskMods & ~b.KeepMods;
            }
            Child(state.Binding, pos, true, timestamp, index);
        }
        else
        {
            if (!morphs.TryGetValue(identity, out state)) throw new InvalidOperationException("Mod-morph released without press.");
            Child(state.Binding, pos, false, timestamp, index);
            maskedMods = 0;
            morphs.Remove(identity);
        }
    }

    void DanceBinding(KcHtBinding b, int pos, bool down, long timestamp, int index)
    {
        if (b.Bindings.Length == 0 || b.Term < 0) throw new ArgumentException("Invalid tap-dance bindings or term.");
        if (b.Kind == "qdance" && b.Bindings.Length != 4) throw new ArgumentException("Vial tap-dance needs four bindings.");
        Dance dance;
        if (!dances.TryGetValue(pos, out dance))
        {
            if (!down) throw new InvalidOperationException("Tap-dance released without press.");
            dance = new Dance(); dance.Binding = b; dance.Pos = pos; dance.Timestamp = timestamp; dance.Index = index;
            dances[pos] = dance;
        }
        dance.Down = down;
        if (down)
        {
            dance.Count++; dance.Generation++; dance.Timestamp = timestamp;
            if (b.Kind == "qdance") dance.CapturedMods = ((KcQmkTapHoldSim)host).AllModifiers;
            if (b.Kind == "dance" && dance.Count >= b.Bindings.Length) { FinishDance(dance); return; }
            if (b.Kind == "qdance" && dance.Count >= 3)
            {
                int taps = dance.Count == 3 ? 3 : 1;
                for (int n = 0; n < taps; n++) Tap(b.Bindings[0], pos, timestamp, index);
            }
            int generation = dance.Generation;
            long due = b.Kind == "qdance" ? host.Now + b.Term + 1 : timestamp + b.Term;
            if (due <= host.Now && b.Kind == "dance") return;
            host.Schedule(due, delegate {
                Dance current;
                if (dances.TryGetValue(pos, out current) && object.ReferenceEquals(current, dance)
                    && !dance.Finished && dance.Generation == generation) { dance.Timestamp = due; FinishDance(dance); }
            });
        }
        else if (dance.Finished) ReleaseDance(dance);
    }
    void Tap(KcHtBinding b, int pos, long timestamp, int index)
    {
        Child(b, pos, true, timestamp, index);
        if (engine == "qmk") ((KcQmkTapHoldSim)host).Delay(map.Qmk.TapCodeDelay);
        Child(b, pos, false, host.Now, index);
    }
    bool Empty(KcHtBinding b) { return b == null || b.Kind == "none" || b.Kind == "trans"; }
    void FinishDance(Dance dance)
    {
        if (dance.Finished) return;
        dance.Finished = true;
        KcHtBinding b = dance.Binding;
        if (b.Kind == "qdance") ((KcQmkTapHoldSim)host).AddWeakModifiers(dance.CapturedMods);
        if (b.Kind == "dance") dance.Selected = b.Bindings[Math.Min(dance.Count, b.Bindings.Length) - 1];
        else if (dance.Count == 1)
            dance.Selected = dance.Interrupted || !dance.Down || Empty(b.Bindings[1]) ? b.Bindings[0] : b.Bindings[1];
        else if (dance.Count == 2)
        {
            int choice = dance.Interrupted ? -1 : (dance.Down ? 3 : 2);
            if (choice >= 0 && !Empty(b.Bindings[choice])) dance.Selected = b.Bindings[choice];
            else
            {
                Tap(b.Bindings[0], dance.Pos, dance.Timestamp, dance.Index);
                dance.Selected = !dance.Interrupted && dance.Down && !Empty(b.Bindings[1]) ? b.Bindings[1] : b.Bindings[0];
            }
        }
        if (dance.Selected != null) Child(dance.Selected, dance.Pos, true, dance.Timestamp, dance.Index);
        if (!dance.Down) ReleaseDance(dance);
    }
    void ReleaseDance(Dance dance)
    {
        if (dance.Binding.Kind == "qdance") ((KcQmkTapHoldSim)host).Delay(map.Qmk.TapCodeDelay);
        if (dance.Selected != null) Child(dance.Selected, dance.Pos, false, host.Now, dance.Index);
        if (dance.Binding.Kind == "qdance") ((KcQmkTapHoldSim)host).RemoveWeakModifiers(dance.CapturedMods);
        dances.Remove(dance.Pos);
    }

    // Dynamic Vial macros wait on the keyboard task itself, unlike ZMK's workqueue macros.
    void QmkMacro(KcHtBinding b, int pos)
    {
        foreach (KcSimMacroStep step in b.Steps)
        {
            if (step.Ms < 0) throw new ArgumentException("Macro times must be nonnegative.");
            if (step.Kind == "wait") ((KcQmkTapHoldSim)host).Delay(step.Ms);
            else if (step.Kind == "tap") Tap(step.Binding, pos, host.Now, -1);
            else if (step.Kind == "press" || step.Kind == "release") Child(step.Binding, pos, step.Kind == "press", host.Now, -1);
            else throw new NotSupportedException("Unsupported Vial macro step: " + step.Kind);
        }
    }

    void MacroBinding(KcHtBinding b, int pos, bool down)
    {
        string identity = Identity(b, pos);
        if (!down)
        {
            List<MacroAction> release;
            if (macroReleases.TryGetValue(identity, out release))
            { macroReleases.Remove(identity); Enqueue(release); }
            return;
        }
        int wait = b.WaitMs; int tap = b.TapMs; int releaseWait = 0; int releaseTap = 0;
        if (wait < 0 || tap < 0) throw new ArgumentException("Macro times must be nonnegative.");
        List<MacroAction> press = new List<MacroAction>();
        List<MacroAction> releaseActions = new List<MacroAction>();
        List<MacroAction> actions = press;
        foreach (KcSimMacroStep step in b.Steps)
        {
            if (step.Ms < 0) throw new ArgumentException("Macro times must be nonnegative.");
            if (step.Kind == "pause") { actions = releaseActions; wait = releaseWait; tap = releaseTap; continue; }
            if (step.Kind == "wait_time") { wait = step.Ms; releaseWait = wait; continue; }
            if (step.Kind == "tap_time") { tap = step.Ms; releaseTap = tap; continue; }
            if (step.Kind == "wait") { AddMacroAction(actions, null, false, pos, step.Ms); continue; }
            if (step.Kind == "tap")
            {
                AddMacroAction(actions, step.Binding, true, pos, tap);
                AddMacroAction(actions, step.Binding, false, pos, wait);
            }
            else if (step.Kind == "press" || step.Kind == "release")
                AddMacroAction(actions, step.Binding, step.Kind == "press", pos, wait);
            else throw new NotSupportedException("Unsupported macro step: " + step.Kind);
        }
        if (releaseActions.Count != 0) macroReleases[identity] = releaseActions;
        Enqueue(press);
    }
    static void AddMacroAction(List<MacroAction> actions, KcHtBinding b, bool down, int pos, int delay)
    {
        MacroAction action = new MacroAction(); action.Binding = b; action.Down = down; action.Pos = pos; action.Delay = delay;
        actions.Add(action);
    }
    void Enqueue(List<MacroAction> actions)
    {
        foreach (MacroAction action in actions) macroQueue.Enqueue(action);
        if (macroRunning || macroQueue.Count == 0) return;
        macroRunning = true; RunMacro();
    }
    void RunMacro()
    {
        int guard = 0;
        while (macroQueue.Count != 0)
        {
            if (++guard > 1000000) throw new InvalidOperationException("Macro queue does not end.");
            MacroAction action = macroQueue.Dequeue();
            if (action.Binding != null) Child(action.Binding, action.Pos, action.Down, host.Now, -1);
            if (action.Delay > 0) { host.Schedule(host.Now + action.Delay, RunMacro); return; }
        }
        macroRunning = false;
    }
}
