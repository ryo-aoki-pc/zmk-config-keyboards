// QMK key override state machine, derived from the pinned KQ-mini sources:
// quantum/process_keycode/process_key_override.c and quantum/vial.c.
// ASCII, C# 5. This models HID transitions, not host OS character repeat.
using System;
using System.Collections.Generic;

public interface IKcQmkOverrideHost
{
    long Now { get; }
    int RawModifiers { get; }
    int HighestLayer { get; }
    int TapCodeDelay { get; }
    void Delay(int ms);
    void Schedule(long at, Action action);
    void OverrideModifiers(int suppressed, int weak);
    void ReportOverrideModifiers();
    void ClearRealModifiers(int mask);
    void OverrideKey(KcHtBinding binding, int pos, bool down);
    void OverrideMacro(KcHtBinding binding, int pos);
}

public sealed class KcQmkOverrideSim
{
    readonly KcSimOverrideRule[] rules;
    readonly IKcQmkOverrideHost host;
    KcSimOverrideRule active;
    int activePos;
    bool activeTriggerDown;
    int lastKey;
    int lastPos;
    long lastKeyTime;
    int deferredGeneration;
    int recursion;
    readonly Dictionary<int, int> intercepted = new Dictionary<int, int>();

    public KcQmkOverrideSim(KcSimOverrideRule[] rules, IKcQmkOverrideHost host)
    {
        this.rules = rules ?? new KcSimOverrideRule[0];
        this.host = host;
        if (host == null) throw new ArgumentNullException("host");
        foreach (KcSimOverrideRule rule in this.rules)
        {
            if (rule == null || rule.Replacement == null)
                throw new ArgumentException("An override needs a trigger and replacement.");
            ParseCode(rule.Trigger);
            if ((rule.Options & ~255) != 0 || (rule.Options & 64) != 0)
                throw new NotSupportedException("Unknown Vial key override option bits.");
            if ((rule.TriggerMods & ~255) != 0 || (rule.NegativeModMask & ~255) != 0 || (rule.SuppressedMods & ~255) != 0)
                throw new ArgumentException("Override modifier masks must fit in eight bits.");
        }
    }

    public static bool MatchesModifiers(KcSimOverrideRule rule, int mods)
    {
        if ((rule.NegativeModMask & mods) != 0) return false;
        if (rule.TriggerMods == 0) return true;
        if ((rule.Options & 8) != 0) return (rule.TriggerMods & mods) != 0;
        int required = (rule.TriggerMods & 15) | (rule.TriggerMods >> 4);
        int found = rule.TriggerMods & mods;
        return ((found & 15) | (found >> 4)) == required;
    }

    static int ParseCode(string text)
    {
        if (text == null || !text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Override keycodes must be canonical hexadecimal values: " + text);
        int code;
        if (!int.TryParse(text.Substring(2), System.Globalization.NumberStyles.HexNumber,
            System.Globalization.CultureInfo.InvariantCulture, out code) || code < 0 || code > 65535)
            throw new ArgumentException("Invalid override keycode: " + text);
        return code;
    }

    static int Code(KcHtBinding binding)
    {
        if (binding.Src != null && binding.Src.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) return ParseCode(binding.Src);
        if (binding.Kind == "kp" && binding.Mods == 0) return binding.Usage;
        return -1;
    }

    static bool Allows(KcSimOverrideRule rule, bool down, bool modifier)
    {
        int options = rule.Options;
        if ((options & 7) == 0) options = 7;
        return modifier ? (options & (down ? 2 : 4)) != 0 : down && (options & 1) != 0;
    }

    static KcHtBinding Bare(KcHtBinding binding)
    {
        if (binding.Kind != "kp") return binding;
        KcHtBinding result = new KcHtBinding();
        result.Kind = "kp"; result.Usage = binding.Usage; result.Label = binding.Label;
        return result;
    }

    static KcHtBinding RegisteredCode(int code, bool withMods)
    {
        // register_code/unregister_code take uint8_t, including when QMK passes
        // a TD or custom trigger. Preserve that narrowing; do not invoke its behavior.
        int usage = code & 255;
        KcHtBinding binding = new KcHtBinding();
        if (usage < 4) return binding;
        if (usage > 0xa4 && (usage < 0xe0 || usage > 0xe7))
            throw new NotSupportedException("Override trigger restoration uses an unsupported HID page.");
        binding.Kind = "kp"; binding.Usage = usage;
        if (withMods && code >= 0x100 && code <= 0x1fff)
        {
            int packed = (code >> 8) & 31;
            binding.Mods = (packed & 16) != 0 ? (packed & 15) << 4 : packed;
        }
        return binding;
    }

    void Defer(KcHtBinding binding, int pos)
    {
        int generation = ++deferredGeneration;
        long due = host.Now - lastKeyTime < 500 ? lastKeyTime + 500 : host.Now + 50;
        host.Schedule(due, delegate {
            if (generation != deferredGeneration) return;
            deferredGeneration++;
            if (binding.Mods != 0 && host.TapCodeDelay != 0)
                throw new NotSupportedException("Deferred modded trigger restoration with nonzero tap delay is unsupported.");
            host.Delay(host.TapCodeDelay);
            if (binding.Kind == "kp") host.OverrideKey(binding, pos, true);
        });
    }

    void Clear(bool allowReregister)
    {
        if (active == null) return;
        KcSimOverrideRule old = active;
        int triggerPos = activePos;
        bool wasDown = activeTriggerDown;
        deferredGeneration++;
        host.OverrideModifiers(0, 0);
        if (old.Replacement.Kind == "kp" && old.Replacement.Usage != 0)
            host.OverrideKey(Bare(old.Replacement), activePos, false);
        int trigger = ParseCode(old.Trigger);
        if (allowReregister && (old.Options & 16) == 0 && wasDown && trigger != 0 && trigger < 0x7e40)
        {
            Defer(RegisteredCode(trigger, true), triggerPos);
        }
        host.ReportOverrideModifiers();
        active = null; activeTriggerDown = false;
    }

    // True suppresses the original action. Synthetic basic Vial macro/dance
    // actions bypass this method, as vial_keycode_down uses register_code16.
    public bool Process(KcHtBinding binding, int pos, bool down)
    {
        if (++recursion > 64) throw new InvalidOperationException("Recursive QMK key overrides.");
        try { return ProcessInternal(binding, pos, down); }
        finally { recursion--; }
    }

    bool ProcessInternal(KcHtBinding binding, int pos, bool down)
    {
        int code = Code(binding);
        if (code < 0 || rules.Length == 0) return false;
        bool modifier = code >= 0xe0 && code <= 0xe7;
        int mods = host.RawModifiers;
        bool suppressRelease = false;
        int interceptedCode;
        if (!down && intercepted.TryGetValue(pos, out interceptedCode) && interceptedCode == code)
        {
            intercepted.Remove(pos);
            // A basic trigger may have been re-registered after modifier release.
            // Its normal key-up must reach the backend to remove that held key.
            suppressRelease = binding.Kind != "kp";
        }
        if (modifier)
        {
            int flag = 1 << (code - 0xe0);
            mods = down ? mods | flag : mods & ~flag;
        }
        else
        {
            if (down)
            {
                lastKey = code; lastPos = pos; lastKeyTime = host.Now;
                deferredGeneration++;
            }
            else if (code == lastKey)
            { lastKey = 0; lastKeyTime = 0; deferredGeneration++; }
        }

        if (modifier || down)
        {
            foreach (KcSimOverrideRule rule in rules)
            {
                if ((rule.Options & 128) == 0 || object.ReferenceEquals(active, rule)) continue;
                if (host.HighestLayer < 0 || host.HighestLayer > 31 || (rule.Layers & (1 << host.HighestLayer)) == 0) continue;
                if (!Allows(rule, down, modifier) || !MatchesModifiers(rule, mods)) continue;
                int trigger = ParseCode(rule.Trigger);
                bool isTrigger = trigger == code;
                if (isTrigger && !down) continue;
                bool triggerDown = isTrigger && down;
                if (trigger != 0 && !triggerDown && lastKey != trigger) continue;
                KcHtBinding replacement = rule.Replacement;
                if (replacement.Kind != "kp" && replacement.Kind != "none" && replacement.Kind != "qmacro")
                    throw new NotSupportedException("Unsupported QMK override replacement: " + replacement.Kind);
                Clear(false);
                active = rule;
                activePos = triggerDown ? pos : lastPos; activeTriggerDown = true;
                if (triggerDown) intercepted[pos] = code;
                host.OverrideModifiers(rule.SuppressedMods, replacement.Kind == "kp" ? replacement.Mods : 0);
                if (!triggerDown && trigger != 0)
                {
                    KcHtBinding removed = RegisteredCode(trigger, false);
                    if (removed.Kind == "kp") host.OverrideKey(removed, activePos, false);
                }
                if (replacement.Kind == "qmacro")
                {
                    host.ClearRealModifiers(rule.SuppressedMods);
                    host.OverrideModifiers(0, 0);
                    host.ReportOverrideModifiers();
                    host.Delay(host.TapCodeDelay);
                    // The magic-position macro key traverses process_key_override
                    // again and, being another non-modifier key, clears this override.
                    if (!Process(replacement, int.MinValue, true)) host.OverrideMacro(replacement, pos);
                }
                else if (replacement.Kind == "kp" && replacement.Usage != 0)
                {
                    if (modifier) Defer(Bare(replacement), activePos);
                    else
                    {
                        host.ReportOverrideModifiers();
                        host.Delay(host.TapCodeDelay);
                        host.OverrideKey(Bare(replacement), activePos, true);
                    }
                    host.ReportOverrideModifiers();
                }
                else host.ReportOverrideModifiers();
                return triggerDown || suppressRelease;
            }
        }

        if (active != null)
        {
            if (modifier)
            {
                if (!MatchesModifiers(active, mods)) Clear(true);
            }
            else
            {
                bool released = ParseCode(active.Trigger) == code && !down;
                if (released) activeTriggerDown = false;
                if (released || (down && (active.Options & 32) == 0)) Clear(false);
            }
        }
        return suppressRelease;
    }
}
