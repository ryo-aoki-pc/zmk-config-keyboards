// Keyboard-clock adapter for PointerSim.cs. ASCII only / C# 5.
using System;
using System.Collections.Generic;

public sealed class KcPointerPeripheral : IKcSimPeripheral
{
    readonly KcPointerConfig config;
    readonly int amlLayer, scrollLayer;
    readonly HashSet<int> excluded;
    readonly Dictionary<int, bool> mousePositions = new Dictionary<int, bool>();
    KcSimContext context;
    long scheduled = -1;
    int reportIndex, transitionIndex;
    bool draining;
    public KcPointerSim Simulator { get; private set; }

    public KcPointerPeripheral(KcPointerConfig configuration, int amlLayer, int scrollLayer)
    {
        config = configuration.Clone();
        this.amlLayer = amlLayer; this.scrollLayer = scrollLayer;
        if (amlLayer <= 0 || scrollLayer <= 0 || amlLayer == scrollLayer) throw new ArgumentException("Invalid pointer layers");
        excluded = new HashSet<int>(config.ExcludedPositions);
        Simulator = new KcPointerSim(config);
    }

    public void AddSide(string side, KcPointerConfig configuration) { Simulator.AddSide(side, configuration); }

    public void Attach(KcSimContext ctx)
    {
        context = ctx;
        ArmTimer();
    }

    bool IsScroll()
    {
        foreach (int layer in context.Layers) if (layer == scrollLayer) return true;
        return false;
    }

    void ArmTimer()
    {
        long due = Simulator.NextDeadline;
        if (due < 0 || due == scheduled) return;
        scheduled = due;
        context.Schedule(due, delegate {
            if (scheduled != due) return;
            scheduled = -1;
            Simulator.SetScroll(context.Now, IsScroll());
            Flush();
        });
    }

    void Flush()
    {
        if (draining) return;
        draining = true;
        try
        {
            while (transitionIndex < Simulator.Transitions.Count)
            {
                KcPointerLayerTransition t = Simulator.Transitions[transitionIndex++];
                context.SetLayer(amlLayer, t.Active, t.Reason);
            }
            while (reportIndex < Simulator.Reports.Count)
            {
                KcMouseReport r = Simulator.Reports[reportIndex++];
                context.Mouse(r.X, r.Y, r.Wheel, r.HWheel, r.Buttons, r.Reason);
            }
        }
        finally { draining = false; }
        ArmTimer();
    }

    public void Key(int pos, bool down, KcHtBinding binding)
    {
        bool related = excluded.Contains(pos);
        bool modifier = binding.Kind == "mods" || (binding.Kind == "kp" && binding.Usage >= 224 && binding.Usage <= 231);
        if (config.Engine == "keyball")
        {
            related = (related && Simulator.AmlActive) || binding.Kind == "button" ||
                ((binding.Kind == "mo" || binding.Kind == "to" || binding.Kind == "tog") &&
                 (binding.Layer == amlLayer || binding.Layer == scrollLayer));
            if (down) mousePositions[pos] = related;
            else if (mousePositions.ContainsKey(pos)) { related = mousePositions[pos]; mousePositions.Remove(pos); }
        }
        Simulator.Key(context.Now, down, modifier, related);
        // Keep the pressed binding resolved on the layer which received the key.
        // Button/keycode callbacks can flush sooner, once that binding is selected.
        context.Schedule(context.Now, delegate { Simulator.SetScroll(context.Now, IsScroll()); Flush(); });
    }

    public void Event(KcSimEvent ev)
    {
        if (ev.Kind != "pointer" && ev.Kind != "move") throw new NotSupportedException("Unsupported pointer event: " + ev.Kind);
        Simulator.MoveSide(context.Now, ev.Side, ev.X, ev.Y, IsScroll());
        Flush();
    }

    public void Button(int button, bool down)
    {
        Simulator.Button(context.Now, button, down);
        Flush();
    }

    public void Output(KcHtOutput output)
    {
        if (draining) return;
        if (output.Kind == "key" && output.Down) Simulator.Keycode(context.Now, output.T);
        if (output.Kind == "layer" && output.Layer == amlLayer)
            Simulator.ObserveLayer(context.Now, output.Down);
        Simulator.SetScroll(context.Now, IsScroll());
        Flush();
    }
}
