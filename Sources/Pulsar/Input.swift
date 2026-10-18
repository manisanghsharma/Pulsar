import AppKit

/// A global shortcut: a key combo or a mouse button (with optional modifiers).
struct Trigger: Codable, Equatable {
    enum Kind: String, Codable { case key, mouse }
    var kind: Kind
    var code: Int64
    var mods: UInt64
    var name: String

    static let modMask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue

    var label: String {
        let f = CGEventFlags(rawValue: mods)
        var s = ""
        if f.contains(.maskControl) { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift) { s += "⇧" }
        if f.contains(.maskCommand) { s += "⌘" }
        return s + name
    }

    /// Down-event identity, used to pair a swallowed down with its up.
    var id: String { (kind == .key ? "k" : "m") + "\(code)" }

    static func key(_ code: Int64, _ name: String) -> Trigger { Trigger(kind: .key, code: code, mods: 0, name: name) }

    /// Builds a trigger from a down event while the user is assigning a shortcut.
    init?(capturing e: CGEvent) {
        let mods = e.flags.rawValue & Self.modMask
        switch e.type {
        case .keyDown:
            guard e.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
            let code = e.getIntegerValueField(.keyboardEventKeycode)
            self.init(kind: .key, code: code, mods: mods, name: Self.keyName(code, e))
        case .otherMouseDown:
            let b = e.getIntegerValueField(.mouseEventButtonNumber)
            self.init(kind: .mouse, code: b, mods: mods, name: Self.mouseName(b))
        case .leftMouseDown, .rightMouseDown:
            // Plain left/right click would hijack normal use, so require a modifier.
            guard mods != 0 else { return nil }
            let b: Int64 = e.type == .leftMouseDown ? 0 : 1
            self.init(kind: .mouse, code: b, mods: mods, name: Self.mouseName(b))
        default:
            return nil
        }
    }

    init(kind: Kind, code: Int64, mods: UInt64, name: String) {
        self.kind = kind; self.code = code; self.mods = mods; self.name = name
    }

    func matches(_ e: CGEvent) -> Bool {
        guard e.flags.rawValue & Self.modMask == mods, let id = Self.downID(e) else { return false }
        return id == self.id
    }

    static func downID(_ e: CGEvent) -> String? {
        switch e.type {
        case .keyDown: return "k\(e.getIntegerValueField(.keyboardEventKeycode))"
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return "m\(e.getIntegerValueField(.mouseEventButtonNumber))"
        default: return nil
        }
    }

    static func upID(_ e: CGEvent) -> String? {
        switch e.type {
        case .keyUp: return "k\(e.getIntegerValueField(.keyboardEventKeycode))"
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: return "m\(e.getIntegerValueField(.mouseEventButtonNumber))"
        default: return nil
        }
    }

    static func mouseName(_ b: Int64) -> String {
        switch b {
        case 0: return "Left Click"
        case 1: return "Right Click"
        case 2: return "Middle Click"
        case 3: return "Mouse 4 (Back)"
        case 4: return "Mouse 5 (Forward)"
        default: return "Mouse \(b + 1)"
        }
    }

    private static let special: [Int64: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20", 49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete",
        117: "⌦", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End",
        116: "Page Up", 121: "Page Down",
    ]

    static func keyName(_ code: Int64, _ e: CGEvent) -> String {
        if let s = special[code] { return s }
        let c = NSEvent(cgEvent: e)?.charactersIgnoringModifiers?.uppercased() ?? ""
        return c.isEmpty || c.unicodeScalars.contains(where: { $0.value < 32 }) ? "Key \(code)" : c
    }
}

/// Posts synthetic events. Every event is tagged so our own tap ignores it.
enum Input {
    static let tag: Int64 = 0x50554C53 // "PULS"

    static func post(_ e: CGEvent?) {
        guard let e else { return }
        e.setIntegerValueField(.eventSourceUserData, value: tag)
        e.post(tap: .cghidEventTap)
    }

    static func mouse(_ type: CGEventType, _ p: CGPoint, button: Int64, clickState: Int64 = 1, flags: UInt64 = 0) {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p,
                        mouseButton: CGMouseButton(rawValue: UInt32(min(button, 2)))!)
        e?.setIntegerValueField(.mouseEventButtonNumber, value: button)
        e?.setIntegerValueField(.mouseEventClickState, value: clickState)
        e?.flags = CGEventFlags(rawValue: flags) // never inherit held modifiers (⌃+click = right click)
        post(e)
    }

    static func click(button: Int, at p: CGPoint, double: Bool) {
        let (down, up): (CGEventType, CGEventType) = switch button {
        case 0: (.leftMouseDown, .leftMouseUp)
        case 1: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        for i in 1...(double ? 2 : 1) {
            mouse(down, p, button: Int64(button), clickState: Int64(i))
            mouse(up, p, button: Int64(button), clickState: Int64(i))
        }
    }

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

/// One recorded input event, replayable via `post()`.
struct MacroEvent: Codable {
    var t: Double
    var type: UInt32
    var x: Double
    var y: Double
    var code: Int64 = 0
    var flags: UInt64 = 0
    var clicks: Int64 = 0
    var dx: Int32 = 0
    var dy: Int32 = 0

    static let recorded: Set<CGEventType> = [
        .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
        .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
    ]

    init(_ e: CGEvent, t: Double) {
        self.t = t
        type = e.type.rawValue
        x = e.location.x
        y = e.location.y
        flags = e.flags.rawValue & Trigger.modMask
        switch e.type {
        case .keyDown, .keyUp:
            code = e.getIntegerValueField(.keyboardEventKeycode)
        case .scrollWheel:
            dy = Int32(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            dx = Int32(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        default:
            code = e.getIntegerValueField(.mouseEventButtonNumber)
            clicks = e.getIntegerValueField(.mouseEventClickState)
        }
    }

    var cgType: CGEventType { CGEventType(rawValue: type) ?? .null }
    var isDown: Bool { [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(cgType) }
    var isUp: Bool { [.keyUp, .leftMouseUp, .rightMouseUp, .otherMouseUp].contains(cgType) }
    var isKey: Bool { cgType == .keyDown || cgType == .keyUp }

    func post() {
        let p = CGPoint(x: x, y: y)
        switch cgType {
        case .keyDown, .keyUp:
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: cgType == .keyDown)
            e?.flags = CGEventFlags(rawValue: flags)
            Input.post(e)
        case .scrollWheel:
            Input.post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
        default:
            Input.mouse(cgType, p, button: code, clickState: max(clicks, 1), flags: flags)
        }
    }

    /// Releases a key/button left held when playback is interrupted.
    static func release(_ down: MacroEvent) {
        if down.isKey {
            Input.post(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(down.code), keyDown: false))
        } else {
            let up: CGEventType = down.code == 0 ? .leftMouseUp : down.code == 1 ? .rightMouseUp : .otherMouseUp
            Input.mouse(up, Input.cursor, button: down.code)
        }
    }
}

/// Thread-safe stop flag + counter shared between the UI and a worker thread.
final class Runner: @unchecked Sendable {
    private let lock = NSLock()
    private var _stopped = false
    private var _count = 0
    private var _avoid: [CGRect] = []

    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return _stopped }
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    var avoid: [CGRect] {
        get { lock.lock(); defer { lock.unlock() }; return _avoid }
        set { lock.lock(); _avoid = newValue; lock.unlock() }
    }
    func stop() { lock.lock(); _stopped = true; lock.unlock() }
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; _count += 1; return _count }

    /// Sleeps until `deadline` in short slices so a stop takes effect within ~10 ms. Returns false if stopped.
    func sleep(until deadline: CFAbsoluteTime) -> Bool {
        while !stopped {
            let left = deadline - CFAbsoluteTimeGetCurrent()
            if left <= 0 { return true }
            Thread.sleep(forTimeInterval: min(left, 0.01))
        }
        return false
    }
}
