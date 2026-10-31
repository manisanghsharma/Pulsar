using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Pulsar;

/// Win32 calls for global hooks and synthetic input.
public static class Native
{
    public const int WH_KEYBOARD_LL = 13, WH_MOUSE_LL = 14;
    public const int WM_KEYDOWN = 0x100, WM_KEYUP = 0x101, WM_SYSKEYDOWN = 0x104, WM_SYSKEYUP = 0x105;
    public const int WM_MOUSEMOVE = 0x200, WM_LBUTTONDOWN = 0x201, WM_LBUTTONUP = 0x202, WM_RBUTTONDOWN = 0x204,
        WM_RBUTTONUP = 0x205, WM_MBUTTONDOWN = 0x207, WM_MBUTTONUP = 0x208, WM_MOUSEWHEEL = 0x20A,
        WM_XBUTTONDOWN = 0x20B, WM_XBUTTONUP = 0x20C, WM_MOUSEHWHEEL = 0x20E;
    public const uint LLKHF_EXTENDED = 0x01;

    const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    const uint MOUSEEVENTF_MOVE = 0x1, MOUSEEVENTF_WHEEL = 0x800, MOUSEEVENTF_HWHEEL = 0x1000,
        MOUSEEVENTF_VIRTUALDESK = 0x4000, MOUSEEVENTF_ABSOLUTE = 0x8000;
    const uint KEYEVENTF_EXTENDEDKEY = 0x1, KEYEVENTF_KEYUP = 0x2;

    /// Marks our own synthetic events so the hooks let them through untouched.
    public static readonly IntPtr Tag = (IntPtr)0x50554C53; // "PULS"

    public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData, flags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion u; }

    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWindowsHookEx(int idHook, HookProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetKeyNameText(int lParam, StringBuilder buf, int size);
    [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint ms);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    public static POINT Cursor { get { GetCursorPos(out var p); return p; } }

    /// Held modifiers as Pulsar's bitmask: 1 Ctrl, 2 Alt, 4 Shift, 8 Win.
    public static int Mods =>
        (Down(0x11) ? 1 : 0) | (Down(0x12) ? 2 : 0) | (Down(0x10) ? 4 : 0) | (Down(0x5B) || Down(0x5C) ? 8 : 0);
    static bool Down(int vk) => GetAsyncKeyState(vk) < 0;

    public static bool IsModifier(uint vk) => vk is 0x10 or 0x11 or 0x12 or (>= 0xA0 and <= 0xA5) or 0x5B or 0x5C;

    public static string KeyName(uint vk, uint scan, bool extended)
    {
        if (vk >= 0x70 && vk <= 0x87) return "F" + (vk - 0x6F);
        var sb = new StringBuilder(64);
        int lp = (int)(scan << 16) | (extended ? 1 << 24 : 0);
        return GetKeyNameText(lp, sb, sb.Capacity) > 0 ? sb.ToString() : $"Key {vk}";
    }

    // Button numbers match the macOS app: 0 left, 1 right, 2 middle, 3 back (X1), 4 forward (X2).
    static readonly uint[] DownFlag = { 0x2, 0x8, 0x20, 0x80, 0x80 };
    static readonly uint[] UpFlag = { 0x4, 0x10, 0x40, 0x100, 0x100 };

    /// Presses or releases a mouse button at a screen point (physical pixels).
    public static void MouseButton(int button, bool down, int x, int y)
    {
        var (ax, ay) = Absolute(x, y);
        uint data = button == 3 ? 1u : button == 4 ? 2u : 0u;
        Send(Mouse(ax, ay, data, (down ? DownFlag[button] : UpFlag[button]) | MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK));
    }

    public static void MouseMove(int x, int y)
    {
        var (ax, ay) = Absolute(x, y);
        Send(Mouse(ax, ay, 0, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK));
    }

    public static void Wheel(int delta, bool horizontal) =>
        Send(Mouse(0, 0, unchecked((uint)delta), horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL));

    public static void Key(int vk, int scan, bool extended, bool down)
    {
        var i = new INPUT { type = INPUT_KEYBOARD };
        i.u.ki = new KEYBDINPUT
        {
            wVk = (ushort)vk, wScan = (ushort)scan, dwExtraInfo = Tag,
            dwFlags = (extended ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP),
        };
        Send(i);
    }

    static INPUT Mouse(int dx, int dy, uint data, uint flags)
    {
        var i = new INPUT { type = INPUT_MOUSE };
        i.u.mi = new MOUSEINPUT { dx = dx, dy = dy, mouseData = data, dwFlags = flags, dwExtraInfo = Tag };
        return i;
    }

    static void Send(INPUT i) => SendInput(1, new[] { i }, Marshal.SizeOf<INPUT>());

    /// Maps a physical pixel to SendInput's 0–65535 virtual-desktop space.
    static (int, int) Absolute(int x, int y)
    {
        int l = GetSystemMetrics(76), t = GetSystemMetrics(77), w = GetSystemMetrics(78), h = GetSystemMetrics(79);
        return ((int)Math.Round((x - l) * 65535.0 / Math.Max(w - 1, 1)), (int)Math.Round((y - t) * 65535.0 / Math.Max(h - 1, 1)));
    }
}
