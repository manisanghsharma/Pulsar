import AppKit
import Combine
import UniformTypeIdentifiers

struct Settings: Codable, Equatable {
    var cps: Double = 10
    var button = 0 // 0 left, 1 right, 2 middle
    var doubleClick = false
    var useFixedPoint = false
    var fixedX: Double = 0
    var fixedY: Double = 0
    var stopMode = 0 // 0 never, 1 after clicks, 2 after seconds
    var stopClicks = 100
    var stopSeconds: Double = 10
    var jitter: Double = 0 // ± percent of interval
    var holdMode = false
    var toggleKey: Trigger? = .key(97, "F6")
    var macroKey: Trigger? = .key(98, "F7")
    var recordKey: Trigger? = .key(100, "F8")
    var recordMoves = true
    var macroRepeat = 1 // 0 = forever
    var macroSpeed: Double = 1
}

enum Slot: String, CaseIterable, Identifiable {
    case toggle, macro, record
    var id: String { rawValue }
    var path: WritableKeyPath<Settings, Trigger?> {
        switch self {
        case .toggle: \.toggleKey
        case .macro: \.macroKey
        case .record: \.recordKey
        }
    }
    var title: String {
        switch self {
        case .toggle: "Start / Stop Clicking"
        case .macro: "Play / Stop Macro"
        case .record: "Start / Stop Recording"
        }
    }
}

final class AppModel: ObservableObject {
    @Published var settings: Settings { didSet { save(settings, "settings") } }
    @Published var macro: [MacroEvent] { didSet { save(macro, "macro") } }
    /// File name of the saved macro currently loaded; nil once it's re-recorded or cleared.
    @Published private(set) var macroName: String? { didSet { UserDefaults.standard.set(macroName, forKey: "macroName") } }
    @Published private(set) var clicking = false
    @Published private(set) var playing = false
    @Published private(set) var recording = false
    @Published var capturing: Slot?
    @Published var picking = false
    @Published private(set) var trusted = AXIsProcessTrusted()

    private(set) var clickRunner: Runner?
    private(set) var playRunner: Runner?
    private var tap: CFMachPort?
    private var swallowedUps = Set<String>()
    private var holdID: String?
    private var recordStart: CFAbsoluteTime = 0
    private var timer: Timer?

    init() {
        settings = Self.load("settings") ?? Settings()
        macro = Self.load("macro") ?? []
        macroName = UserDefaults.standard.string(forKey: "macroName")
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ v: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: Permission + event tap

    private func tick() {
        let t = AXIsProcessTrusted()
        if t != trusted { trusted = t }
        if t && tap == nil { installTap() }
        clickRunner?.avoid = ownWindowRects()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func installTap() {
        let types: [CGEventType] = Array(MacroEvent.recorded)
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            let model = Unmanaged<AppModel>.fromOpaque(info!).takeUnretainedValue()
            return model.handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Runs on the main run loop for every input event. Returning nil swallows the event.
    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if e.getIntegerValueField(.eventSourceUserData) == Input.tag { return pass }

        // Swallow the release of any press we swallowed (and end hold-to-click).
        if let up = Trigger.upID(e), swallowedUps.remove(up) != nil {
            if up == holdID { holdID = nil; stopClicking() }
            return nil
        }

        if let slot = capturing {
            if type == .keyDown, e.getIntegerValueField(.keyboardEventKeycode) == 53,
               e.flags.rawValue & Trigger.modMask == 0 { // Esc cancels
                capturing = nil
                swallowedUps.insert("k53")
                return nil
            }
            guard let t = Trigger(capturing: e) else { return pass }
            for other in Slot.allCases where other != slot && settings[keyPath: other.path] == t {
                settings[keyPath: other.path] = nil // one action per shortcut
            }
            settings[keyPath: slot.path] = t
            capturing = nil
            swallowedUps.insert(t.id)
            return nil
        }

        if picking, type == .leftMouseDown {
            settings.fixedX = e.location.x.rounded()
            settings.fixedY = e.location.y.rounded()
            settings.useFixedPoint = true
            picking = false
            swallowedUps.insert("m0")
            NSApp.activate(ignoringOtherApps: true)
            return nil
        }

        for slot in Slot.allCases {
            guard let t = settings[keyPath: slot.path], t.matches(e) else { continue }
            swallowedUps.insert(t.id)
            let repeatKey = type == .keyDown && e.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeatKey { fire(slot, id: t.id) }
            return nil
        }

        if recording, MacroEvent.recorded.contains(type) {
            let skipMove = type == .mouseMoved && !settings.recordMoves
            let onOwnWindow = !Trigger.isKey(type) && ownWindowRects().contains { $0.contains(e.location) }
            if !skipMove && !onOwnWindow {
                macro.append(MacroEvent(e, t: CFAbsoluteTimeGetCurrent() - recordStart))
            }
        }
        return pass
    }

    private func fire(_ slot: Slot, id: String) {
        switch slot {
        case .toggle:
            if settings.holdMode {
                holdID = id
                startClicking()
            } else {
                toggleClicking()
            }
        case .macro: togglePlaying()
        case .record: toggleRecording()
        }
    }

    /// Our visible windows in CG (top-left origin) coordinates.
    private func ownWindowRects() -> [CGRect] {
        guard let h = NSScreen.screens.first?.frame.height else { return [] }
        return NSApp.windows.filter { $0.isVisible && $0.isOnActiveSpace }.map {
            CGRect(x: $0.frame.minX, y: h - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }

    // MARK: Clicker

    func toggleClicking() { clicking ? stopClicking() : startClicking() }

    func startClicking() {
        guard !clicking else { return }
        guard trusted else { return openAccessibilitySettings() }
        stopPlaying()
        let s = settings
        let runner = Runner()
        runner.avoid = ownWindowRects()
        clickRunner = runner
        clicking = true
        Thread.detachNewThread { [weak self] in
            let interval = 1 / max(s.cps, 0.1)
            let start = CFAbsoluteTimeGetCurrent()
            var next = start
            while !runner.stopped {
                let p = s.useFixedPoint ? CGPoint(x: s.fixedX, y: s.fixedY) : Input.cursor
                // Never click our own window, so the Stop button stays usable.
                if !runner.avoid.contains(where: { $0.contains(p) }) {
                    Input.click(button: s.button, at: p, double: s.doubleClick)
                    let n = runner.increment()
                    if s.stopMode == 1 && n >= s.stopClicks { break }
                }
                if s.stopMode == 2 && CFAbsoluteTimeGetCurrent() - start >= s.stopSeconds { break }
                let j = s.jitter / 100
                next += interval * (1 + Double.random(in: -j...j))
                let now = CFAbsoluteTimeGetCurrent()
                if next < now - 0.25 { next = now } // fell behind (e.g. system stall): don't burst to catch up
                guard runner.sleep(until: next) else { break }
            }
            DispatchQueue.main.async {
                guard let self, self.clickRunner === runner else { return }
                self.clicking = false
            }
        }
    }

    func stopClicking() {
        clickRunner?.stop()
        clicking = false
    }

    // MARK: Macro

    var macroDuration: Double { macro.last?.t ?? 0 }

    func saveMacroToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Pulsar Macro.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONEncoder().encode(macro).write(to: url, options: .atomic)
            macroName = url.deletingPathExtension().lastPathComponent
        } catch { NSAlert(error: error).runModal() }
    }

    func clearMacro() {
        macro = []
        macroName = nil
    }

    func openMacroFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            macro = try JSONDecoder().decode([MacroEvent].self, from: Data(contentsOf: url))
            macroName = url.deletingPathExtension().lastPathComponent
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't open macro"
            alert.informativeText = "\(url.lastPathComponent) isn't a Pulsar macro file."
            alert.runModal()
        }
    }

    func toggleRecording() { recording ? stopRecording() : startRecording() }

    func startRecording() {
        guard trusted else { return openAccessibilitySettings() }
        stopClicking()
        stopPlaying()
        macro = []
        macroName = nil
        recordStart = CFAbsoluteTimeGetCurrent()
        recording = true
    }

    func stopRecording() {
        guard recording else { return }
        recording = false
        // Drop presses whose release never got recorded (e.g. the shortcut fired mid-press).
        var open = [String: Int]()
        for (i, ev) in macro.enumerated() {
            let id = (ev.isKey ? "k" : "m") + "\(ev.code)"
            if ev.isDown { open[id] = i } else if ev.isUp { open[id] = nil }
        }
        if !open.isEmpty { macro = macro.enumerated().filter { !open.values.contains($0.offset) }.map(\.element) }
    }

    func togglePlaying() { playing ? stopPlaying() : startPlaying() }

    func startPlaying() {
        guard !playing, !macro.isEmpty else { return }
        guard trusted else { return openAccessibilitySettings() }
        stopRecording()
        stopClicking()
        let events = macro
        let loops = settings.macroRepeat
        let speed = max(settings.macroSpeed, 0.05)
        let runner = Runner()
        playRunner = runner
        playing = true
        Thread.detachNewThread { [weak self] in
            var held = [String: MacroEvent]()
            var loop = 0
            outer: while loops == 0 || loop < loops {
                let start = CFAbsoluteTimeGetCurrent()
                for ev in events {
                    guard runner.sleep(until: start + ev.t / speed) else { break outer }
                    ev.post()
                    let id = (ev.isKey ? "k" : "m") + "\(ev.code)"
                    if ev.isDown { held[id] = ev } else if ev.isUp { held[id] = nil }
                }
                loop += 1
                _ = runner.increment()
                // Short gap between loops; also prevents a zero-length macro from spinning.
                guard runner.sleep(until: CFAbsoluteTimeGetCurrent() + 0.05) else { break }
            }
            held.values.forEach(MacroEvent.release)
            DispatchQueue.main.async {
                guard let self, self.playRunner === runner else { return }
                self.playing = false
            }
        }
    }

    func stopPlaying() {
        playRunner?.stop()
        playing = false
    }
}

extension Trigger {
    static func isKey(_ t: CGEventType) -> Bool { t == .keyDown || t == .keyUp }
}
