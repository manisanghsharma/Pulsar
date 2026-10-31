using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Windows;
using System.Windows.Media;

namespace Pulsar;

/// A global shortcut: a key or a mouse button, with optional modifiers (1 Ctrl, 2 Alt, 4 Shift, 8 Win).
public sealed record Trigger(string Kind, int Code, int Mods, string Name)
{
    [JsonIgnore] public string Id => (Kind == "key" ? "k" : "m") + Code;

    [JsonIgnore]
    public string Label =>
        ((Mods & 1) != 0 ? "Ctrl+" : "") + ((Mods & 2) != 0 ? "Alt+" : "") +
        ((Mods & 4) != 0 ? "Shift+" : "") + ((Mods & 8) != 0 ? "Win+" : "") + Name;

    public static Trigger Key(int vk) => new("key", vk, 0, Native.KeyName((uint)vk, 0, false));

    public static string MouseName(int b) => b switch
    {
        0 => "Left Click", 1 => "Right Click", 2 => "Middle Click",
        3 => "Mouse 4 (Back)", 4 => "Mouse 5 (Forward)", _ => $"Mouse {b + 1}",
    };
}

/// One recorded input event. Kind: 0 key down, 1 key up, 2 button down, 3 button up, 4 move, 5 wheel, 6 h-wheel.
public sealed class MacroEvent
{
    public double T { get; set; }
    public int Kind { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    public int Code { get; set; }
    public int Scan { get; set; }
    public bool Ext { get; set; }
    public int Delta { get; set; }

    [JsonIgnore] public bool IsKey => Kind <= 1;
    [JsonIgnore] public bool IsDown => Kind is 0 or 2;
    [JsonIgnore] public bool IsUp => Kind is 1 or 3;
    [JsonIgnore] public string Id => (IsKey ? "k" : "m") + Code;

    public void Post()
    {
        switch (Kind)
        {
            case 0 or 1: Native.Key(Code, Scan, Ext, Kind == 0); break;
            case 2 or 3: Native.MouseButton(Code, Kind == 2, X, Y); break;
            case 4: Native.MouseMove(X, Y); break;
            default: Native.Wheel(Delta, Kind == 6); break;
        }
    }

    /// Releases a key/button left held when playback is interrupted.
    public static void Release(MacroEvent down)
    {
        if (down.IsKey) Native.Key(down.Code, down.Scan, down.Ext, false);
        else { var p = Native.Cursor; Native.MouseButton(down.Code, false, p.X, p.Y); }
    }
}

/// Saved macro file. The platform field keeps macOS and Windows macro files from being mixed up.
public sealed class MacroFile
{
    public string Platform { get; set; } = "windows";
    public List<MacroEvent> Events { get; set; } = new();
}

/// Stop flag + counter shared between the UI and a worker thread.
public sealed class Runner
{
    volatile bool stopped;
    int count;
    Native.RECT? avoid;
    readonly object gate = new();

    public bool Stopped => stopped;
    public int Count => Volatile.Read(ref count);
    public Native.RECT? Avoid { get { lock (gate) return avoid; } set { lock (gate) avoid = value; } }
    public void Stop() => stopped = true;
    public int Increment() => Interlocked.Increment(ref count);

    /// Sleeps until `deadline` (Stopwatch ticks), checking the stop flag often. Returns false if stopped.
    public bool SleepUntil(long deadline)
    {
        while (!stopped)
        {
            double ms = (deadline - Stopwatch.GetTimestamp()) * 1000.0 / Stopwatch.Frequency;
            if (ms <= 0) return true;
            if (ms > 2) Thread.Sleep(1); else Thread.Yield(); // spin the last ~2 ms for accurate high-speed clicking
        }
        return false;
    }
}

public sealed class Settings : Observable
{
    double cps = 10; int button, stopMode, stopClicks = 100, macroRepeat = 1;
    bool doubleClick, useFixedPoint, holdMode, recordMoves = true;
    int fixedX, fixedY;
    double stopSeconds = 10, jitter, macroSpeed = 1;
    Trigger? toggleKey = Trigger.Key(0x75), macroKey = Trigger.Key(0x76), recordKey = Trigger.Key(0x77); // F6 F7 F8

    public double Cps { get => cps; set => Set(ref cps, Math.Clamp(value, 0.1, 500)); }
    public int Button { get => button; set => Set(ref button, value); }
    public bool DoubleClick { get => doubleClick; set => Set(ref doubleClick, value); }
    public bool UseFixedPoint { get => useFixedPoint; set => Set(ref useFixedPoint, value); }
    public int FixedX { get => fixedX; set => Set(ref fixedX, value); }
    public int FixedY { get => fixedY; set => Set(ref fixedY, value); }
    public int StopMode { get => stopMode; set => Set(ref stopMode, value); } // 0 never, 1 clicks, 2 seconds
    public int StopClicks { get => stopClicks; set => Set(ref stopClicks, Math.Clamp(value, 1, 10_000_000)); }
    public double StopSeconds { get => stopSeconds; set => Set(ref stopSeconds, Math.Clamp(value, 0.1, 86_400)); }
    public double Jitter { get => jitter; set => Set(ref jitter, Math.Clamp(value, 0, 50)); }
    public bool HoldMode { get => holdMode; set => Set(ref holdMode, value); }
    public Trigger? ToggleKey { get => toggleKey; set => Set(ref toggleKey, value); }
    public Trigger? MacroKey { get => macroKey; set => Set(ref macroKey, value); }
    public Trigger? RecordKey { get => recordKey; set => Set(ref recordKey, value); }
    public bool RecordMoves { get => recordMoves; set => Set(ref recordMoves, value); }
    public int MacroRepeat { get => macroRepeat; set => Set(ref macroRepeat, Math.Clamp(value, 0, 100_000)); } // 0 = forever
    public double MacroSpeed { get => macroSpeed; set => Set(ref macroSpeed, Math.Clamp(value, 0.25, 4)); }
}

public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    protected void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        Raise(name);
    }
}

public sealed class Model : Observable
{
    public static readonly string[] Slots = { "toggle", "macro", "record" };
    static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Pulsar");
    static readonly JsonSerializerOptions Json = new() { WriteIndented = false };

    public Settings S { get; }
    List<MacroEvent> macro;
    string? macroName;
    bool clicking, playing, recording, picking;
    string? capturing;

    Runner? clickRunner, playRunner;
    IntPtr kbHook, mouseHook;
    readonly Native.HookProc kbProc, mouseProc; // kept alive so the GC doesn't collect the delegates
    readonly HashSet<string> swallowedUps = new();
    string? holdId;
    long recordStart;

    /// Our window's screen rectangle in physical pixels, or null while hidden.
    public Func<Native.RECT?> OwnRect { get; set; } = () => null;
    public Action? ActivateWindow { get; set; }

    public Model()
    {
        S = Load<Settings>("settings.json") ?? new Settings();
        macro = Load<List<MacroEvent>>("macro.json") ?? new();
        macroName = Load<string>("macroName.json");
        S.PropertyChanged += (_, e) =>
        {
            Save("settings.json", S);
            if (e.PropertyName is nameof(Settings.ToggleKey) or nameof(Settings.MacroKey) or nameof(Settings.RecordKey))
                RaiseSlots();
            RaiseSettingsDerived();
        };
        kbProc = KeyboardHook;
        mouseProc = MouseHook;
    }

    // MARK: Bindable state

    public bool Clicking { get => clicking; private set { Set(ref clicking, value); RaiseStatus(); } }
    public bool Playing { get => playing; private set { Set(ref playing, value); RaiseStatus(); } }
    public bool Recording { get => recording; private set { Set(ref recording, value); RaiseStatus(); RaiseMacro(); } }
    public bool Picking { get => picking; set { Set(ref picking, value); Raise(nameof(FixedPointText)); } }
    public string? Capturing { get => capturing; set { Set(ref capturing, value); RaiseSlots(); } }

    public string Status => Recording ? "Recording" : Playing ? "Playing" : Clicking ? "Clicking" : "Idle";
    public Brush StatusBrush => (Brush)Application.Current.Resources[
        Recording ? "RecordBrush" : Playing ? "PlayBrush" : Clicking ? "AccentBrush" : "SubBrush"];
    public string ClickButtonText => Clicking ? "Stop Clicking" : "Start Clicking";
    public string ClickButtonIcon => Clicking ? "" : "";
    public string RecordButtonText => Recording ? "Stop Recording" : "Record Macro";
    public string PlayButtonText => Playing ? "Stop Macro" : "Play Macro";
    public string PlayButtonIcon => Playing ? "" : "";
    public string ToggleHint => S.ToggleKey?.Label ?? "";
    public string RecordHint => S.RecordKey?.Label ?? "";
    public string MacroHint => S.MacroKey?.Label ?? "";

    public int ClickCount => clickRunner?.Count ?? 0;
    public int LoopCount => playRunner?.Count ?? 0;
    public string FixedPointText => Picking ? "Click anywhere on screen…" : $"x {S.FixedX}   y {S.FixedY}";

    public string MacroTitle => macroName ?? (macro.Count == 0 ? "No macro" : "Unsaved macro");
    public bool HasMacroName => macroName != null;
    public int MacroEvents => macro.Count;
    public string MacroLength => $"{(macro.Count > 0 ? macro[^1].T : 0):0.0}s";
    public int MacroClicks => macro.Count(e => e.Kind == 2);
    public int MacroKeys => macro.Count(e => e.Kind == 0);
    public bool CanPlay => macro.Count > 0 && !Recording;
    public bool CanSave => macro.Count > 0 && !Recording;
    public bool CanOpen => !Recording && !Playing;
    public string RepeatText => S.MacroRepeat == 0 ? "Forever" : $"{S.MacroRepeat}×";

    public string SlotText(string slot) =>
        Capturing == slot ? "Press shortcut…" : GetSlot(slot)?.Label ?? "None";
    public string ToggleSlotText => SlotText("toggle");
    public string MacroSlotText => SlotText("macro");
    public string RecordSlotText => SlotText("record");

    /// Called ~10×/s by the window to refresh live counters.
    public void Tick()
    {
        if (clickRunner != null) clickRunner.Avoid = OwnRect();
        Raise(nameof(ClickCount));
        Raise(nameof(LoopCount));
    }

    void RaiseStatus()
    {
        foreach (var n in new[] { nameof(Status), nameof(StatusBrush), nameof(ClickButtonText), nameof(ClickButtonIcon),
                     nameof(RecordButtonText), nameof(PlayButtonText), nameof(PlayButtonIcon), nameof(CanPlay), nameof(CanSave), nameof(CanOpen) })
            Raise(n);
    }

    void RaiseMacro()
    {
        foreach (var n in new[] { nameof(MacroTitle), nameof(HasMacroName), nameof(MacroEvents), nameof(MacroLength),
                     nameof(MacroClicks), nameof(MacroKeys), nameof(CanPlay), nameof(CanSave) })
            Raise(n);
    }

    void RaiseSlots()
    {
        foreach (var n in new[] { nameof(ToggleSlotText), nameof(MacroSlotText), nameof(RecordSlotText),
                     nameof(ToggleHint), nameof(RecordHint), nameof(MacroHint) })
            Raise(n);
    }

    public void RaiseSettingsDerived()
    {
        Raise(nameof(FixedPointText));
        Raise(nameof(RepeatText));
    }

    Trigger? GetSlot(string slot) => slot switch { "toggle" => S.ToggleKey, "macro" => S.MacroKey, _ => S.RecordKey };

    public void SetSlot(string slot, Trigger? t)
    {
        switch (slot)
        {
            case "toggle": S.ToggleKey = t; break;
            case "macro": S.MacroKey = t; break;
            default: S.RecordKey = t; break;
        }
    }

    // MARK: Persistence

    static T? Load<T>(string file)
    {
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(Path.Combine(Dir, file)), Json); }
        catch { return default; }
    }

    static void Save<T>(string file, T value)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(Path.Combine(Dir, file), JsonSerializer.Serialize(value, Json));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { } // a failed settings write must never crash input handling
    }

    void SaveMacro()
    {
        Save("macro.json", macro);
        Save("macroName.json", macroName);
    }

    // MARK: Hooks

    public void InstallHooks()
    {
        var mod = Native.GetModuleHandle(null);
        kbHook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, kbProc, mod, 0);
        mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, mouseProc, mod, 0);
    }

    public void Shutdown()
    {
        StopClicking();
        StopPlaying();
        StopRecording();
        if (kbHook != IntPtr.Zero) Native.UnhookWindowsHookEx(kbHook);
        if (mouseHook != IntPtr.Zero) Native.UnhookWindowsHookEx(mouseHook);
        SaveMacro();
    }

    IntPtr KeyboardHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var k = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            int msg = (int)wParam;
            bool down = msg is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN;
            if (k.dwExtraInfo != Native.Tag && Handle(down ? "kd" : "ku", (int)k.vkCode, () => new MacroEvent
                {
                    Kind = down ? 0 : 1, Code = (int)k.vkCode, Scan = (int)k.scanCode, Ext = (k.flags & Native.LLKHF_EXTENDED) != 0,
                }, k.scanCode, (k.flags & Native.LLKHF_EXTENDED) != 0, 0, 0))
                return (IntPtr)1;
        }
        return Native.CallNextHookEx(kbHook, nCode, wParam, lParam);
    }

    IntPtr MouseHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var m = Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam);
            int msg = (int)wParam;
            int xb = (int)(m.mouseData >> 16) == 1 ? 3 : 4;
            (string kind, int button) = msg switch
            {
                Native.WM_LBUTTONDOWN => ("md", 0), Native.WM_LBUTTONUP => ("mu", 0),
                Native.WM_RBUTTONDOWN => ("md", 1), Native.WM_RBUTTONUP => ("mu", 1),
                Native.WM_MBUTTONDOWN => ("md", 2), Native.WM_MBUTTONUP => ("mu", 2),
                Native.WM_XBUTTONDOWN => ("md", xb), Native.WM_XBUTTONUP => ("mu", xb),
                Native.WM_MOUSEMOVE => ("mv", 0),
                Native.WM_MOUSEWHEEL => ("wh", 0), Native.WM_MOUSEHWHEEL => ("hw", 0),
                _ => ("", 0),
            };
            if (kind != "" && m.dwExtraInfo != Native.Tag && Handle(kind, button, () => new MacroEvent
                {
                    Kind = kind switch { "md" => 2, "mu" => 3, "mv" => 4, "wh" => 5, _ => 6 },
                    X = m.pt.X, Y = m.pt.Y, Code = button, Delta = (short)(m.mouseData >> 16),
                }, 0, false, m.pt.X, m.pt.Y))
                return (IntPtr)1;
        }
        return Native.CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }

    /// Runs on the UI thread for every physical input event. Returns true to swallow it.
    /// kind: kd/ku key down/up, md/mu button down/up, mv move, wh/hw wheel.
    bool Handle(string kind, int code, Func<MacroEvent> record, uint scan, bool ext, int x, int y)
    {
        bool isKey = kind[0] == 'k';
        string id = (isKey ? "k" : "m") + code;

        // Swallow the release of any press we swallowed (and end hold-to-click).
        if (kind is "ku" or "mu" && swallowedUps.Remove(id))
        {
            if (id == holdId) { holdId = null; StopClicking(); }
            return true;
        }
        bool isDown = kind is "kd" or "md";

        if (Capturing is string capSlot && isDown)
        {
            int mods = Native.Mods;
            if (kind == "kd" && code == 0x1B && mods == 0) // Esc cancels
            {
                Capturing = null;
                swallowedUps.Add(id);
                return true;
            }
            Trigger? t = null;
            if (kind == "kd" && !Native.IsModifier((uint)code)) t = new Trigger("key", code, mods, Native.KeyName((uint)code, scan, ext));
            // Plain left/right click would hijack normal use, so require a modifier.
            else if (kind == "md" && (code >= 2 || mods != 0)) t = new Trigger("mouse", code, mods, Trigger.MouseName(code));
            if (t == null) return false;
            foreach (var other in Slots)
                if (other != capSlot && GetSlot(other) == t) SetSlot(other, null); // one action per shortcut
            SetSlot(capSlot, t);
            Capturing = null;
            swallowedUps.Add(id);
            return true;
        }

        if (Picking && kind == "md" && code == 0)
        {
            S.FixedX = x;
            S.FixedY = y;
            S.UseFixedPoint = true;
            Picking = false;
            swallowedUps.Add(id);
            ActivateWindow?.Invoke();
            return true;
        }

        if (isDown)
        {
            int mods = Native.Mods;
            foreach (var slot in Slots)
            {
                var t = GetSlot(slot);
                if (t == null || t.Id != id || t.Mods != mods) continue;
                // A held key auto-repeats its down event; only the first press fires.
                if (swallowedUps.Add(id)) Fire(slot, id);
                return true;
            }
        }

        if (Recording && !(kind == "mv" && !S.RecordMoves))
        {
            bool onOwnWindow = !isKey && OwnRect() is Native.RECT r && x >= r.Left && x < r.Right && y >= r.Top && y < r.Bottom;
            if (!onOwnWindow)
            {
                var e = record();
                e.T = (Stopwatch.GetTimestamp() - recordStart) / (double)Stopwatch.Frequency;
                macro.Add(e);
                if (e.Kind != 4) RaiseMacro(); // skip per-move refreshes to keep the hook fast
            }
        }
        return false;
    }

    void Fire(string slot, string id)
    {
        switch (slot)
        {
            case "toggle":
                if (S.HoldMode) { holdId = id; StartClicking(); }
                else ToggleClicking();
                break;
            case "macro": TogglePlaying(); break;
            default: ToggleRecording(); break;
        }
    }

    // MARK: Clicker

    public void ToggleClicking() { if (Clicking) StopClicking(); else StartClicking(); }

    public void StartClicking()
    {
        if (Clicking) return;
        StopPlaying();
        var s = (Cps: S.Cps, Button: S.Button, Double: S.DoubleClick, Fixed: S.UseFixedPoint, X: S.FixedX, Y: S.FixedY,
            StopMode: S.StopMode, StopClicks: S.StopClicks, StopSeconds: S.StopSeconds, Jitter: S.Jitter);
        var runner = new Runner { Avoid = OwnRect() };
        clickRunner = runner;
        Clicking = true;
        var ui = Application.Current.Dispatcher;
        new Thread(() =>
        {
            Native.timeBeginPeriod(1);
            var rng = new Random();
            double interval = Stopwatch.Frequency / Math.Max(s.Cps, 0.1);
            long start = Stopwatch.GetTimestamp();
            double next = start;
            while (!runner.Stopped)
            {
                var p = s.Fixed ? new Native.POINT { X = s.X, Y = s.Y } : Native.Cursor;
                // Never click our own window, so the Stop button stays usable.
                if (!(runner.Avoid is Native.RECT r && p.X >= r.Left && p.X < r.Right && p.Y >= r.Top && p.Y < r.Bottom))
                {
                    for (int i = 0; i < (s.Double ? 2 : 1); i++)
                    {
                        Native.MouseButton(s.Button, true, p.X, p.Y);
                        Native.MouseButton(s.Button, false, p.X, p.Y);
                    }
                    if (runner.Increment() >= s.StopClicks && s.StopMode == 1) break;
                }
                if (s.StopMode == 2 && (Stopwatch.GetTimestamp() - start) >= s.StopSeconds * Stopwatch.Frequency) break;
                double j = s.Jitter / 100;
                next += interval * (1 + (rng.NextDouble() * 2 - 1) * j);
                long now = Stopwatch.GetTimestamp();
                if (next < now - Stopwatch.Frequency / 4) next = now; // fell behind (e.g. system stall): don't burst to catch up
                if (!runner.SleepUntil((long)next)) break;
            }
            Native.timeEndPeriod(1);
            ui.InvokeAsync(() => { if (clickRunner == runner) Clicking = false; });
        }) { IsBackground = true, Priority = ThreadPriority.AboveNormal }.Start();
    }

    public void StopClicking()
    {
        clickRunner?.Stop();
        Clicking = false;
    }

    // MARK: Macro

    public void ToggleRecording() { if (Recording) StopRecording(); else StartRecording(); }

    public void StartRecording()
    {
        StopClicking();
        StopPlaying();
        macro = new();
        macroName = null;
        recordStart = Stopwatch.GetTimestamp();
        Recording = true;
    }

    public void StopRecording()
    {
        if (!Recording) return;
        Recording = false;
        // Drop presses whose release never got recorded (e.g. the shortcut fired mid-press).
        var open = new Dictionary<string, int>();
        for (int i = 0; i < macro.Count; i++)
        {
            if (macro[i].IsDown) open[macro[i].Id] = i;
            else if (macro[i].IsUp) open.Remove(macro[i].Id);
        }
        if (open.Count > 0)
        {
            var drop = open.Values.ToHashSet();
            macro = macro.Where((_, i) => !drop.Contains(i)).ToList();
        }
        SaveMacro();
        RaiseMacro();
    }

    public void ClearMacro()
    {
        macro = new();
        macroName = null;
        SaveMacro();
        RaiseMacro();
    }

    public void SaveMacroToFile()
    {
        var dlg = new Microsoft.Win32.SaveFileDialog { Filter = "Pulsar macro (*.json)|*.json", FileName = "Pulsar Macro.json" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            File.WriteAllText(dlg.FileName, JsonSerializer.Serialize(new MacroFile { Events = macro }, Json));
            macroName = Path.GetFileNameWithoutExtension(dlg.FileName);
            SaveMacro();
            RaiseMacro();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            MessageBox.Show(e.Message, "Couldn't save macro", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    public void OpenMacroFile()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog { Filter = "Pulsar macro (*.json)|*.json" };
        if (dlg.ShowDialog() != true) return;
        MacroFile? file = null;
        try { file = JsonSerializer.Deserialize<MacroFile>(File.ReadAllText(dlg.FileName), Json); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { }
        if (file?.Platform != "windows" || file.Events == null)
        {
            MessageBox.Show($"{Path.GetFileName(dlg.FileName)} isn't a Pulsar for Windows macro file.",
                "Couldn't open macro", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        macro = file.Events;
        macroName = Path.GetFileNameWithoutExtension(dlg.FileName);
        SaveMacro();
        RaiseMacro();
    }

    public void TogglePlaying() { if (Playing) StopPlaying(); else StartPlaying(); }

    public void StartPlaying()
    {
        if (Playing || macro.Count == 0) return;
        StopRecording();
        StopClicking();
        var events = macro;
        int loops = S.MacroRepeat;
        double speed = Math.Max(S.MacroSpeed, 0.05);
        var runner = new Runner();
        playRunner = runner;
        Playing = true;
        var ui = Application.Current.Dispatcher;
        new Thread(() =>
        {
            Native.timeBeginPeriod(1);
            var held = new Dictionary<string, MacroEvent>();
            for (int loop = 0; loops == 0 || loop < loops; loop++)
            {
                long start = Stopwatch.GetTimestamp();
                bool stopped = false;
                foreach (var ev in events)
                {
                    if (!runner.SleepUntil(start + (long)(ev.T / speed * Stopwatch.Frequency))) { stopped = true; break; }
                    ev.Post();
                    if (ev.IsDown) held[ev.Id] = ev; else if (ev.IsUp) held.Remove(ev.Id);
                }
                if (stopped) break;
                runner.Increment();
                // Short gap between loops; also prevents a zero-length macro from spinning.
                if (!runner.SleepUntil(Stopwatch.GetTimestamp() + Stopwatch.Frequency / 20)) break;
            }
            foreach (var ev in held.Values) MacroEvent.Release(ev);
            Native.timeEndPeriod(1);
            ui.InvokeAsync(() => { if (playRunner == runner) Playing = false; });
        }) { IsBackground = true }.Start();
    }

    public void StopPlaying()
    {
        playRunner?.Stop();
        Playing = false;
    }
}
