import SwiftUI

enum Theme {
    static let accent = Color(red: 0.49, green: 0.36, blue: 1.0)     // primary action, selection
    static let record = Color(red: 0.90, green: 0.28, blue: 0.30)    // recording / stop
    static let play = Color(red: 0.07, green: 0.60, blue: 0.53)      // macro playback
    static let bg = Color(red: 0.071, green: 0.067, blue: 0.086)
    static let card = Color(red: 0.106, green: 0.102, blue: 0.129)
    static let field = Color(red: 0.149, green: 0.141, blue: 0.180)
    static let stroke = Color(red: 0.180, green: 0.173, blue: 0.216)
}

enum Tab: String, CaseIterable { case clicker = "Clicker", macro = "Macro", hotkeys = "Hotkeys" }

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var tab = Tab.clicker
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 14) {
            header
            if !m.trusted { permissionBanner }
            tabBar
            ScrollView {
                Group {
                    switch tab {
                    case .clicker: ClickerTab()
                    case .macro: MacroTab()
                    case .hotkeys: HotkeysTab()
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(width: 440, height: 720)
        .background(
            Theme.bg.ignoresSafeArea()
        )
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pulsar")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Text("Auto Clicker & Macro Studio")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill()
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access needed").font(.system(size: 13, weight: .semibold))
                Text("Pulsar needs it to click and to hear your shortcuts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { m.openAccessibilitySettings() }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.35)))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = t } } label: {
                    Text(t.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if tab == t {
                                Capsule().fill(Theme.field).matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke))
    }
}

struct StatusPill: View {
    @EnvironmentObject var m: AppModel
    @State private var pulse = false

    var body: some View {
        let (text, color): (String, Color) =
            m.recording ? ("Recording", Theme.record) : m.playing ? ("Playing", Theme.play) : m.clicking ? ("Clicking", Theme.accent) : ("Idle", .gray)
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
                .opacity(text != "Idle" && pulse ? 0.35 : 1)
            Text(text).font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke))
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
    }
}

// MARK: Building blocks

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke))
    }
}

struct Row<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            content
        }
    }
}

struct GlowButton: View {
    let title: String
    let icon: String
    let active: Bool
    var hint: String?
    var color: Color = Theme.accent
    var activeColor: Color = Theme.record
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill((active ? activeColor : color).opacity(hover ? 0.88 : 1))
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

// MARK: Clicker

struct ClickerTab: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 12) {
            speedCard
            GlowButton(title: m.clicking ? "Stop Clicking" : "Start Clicking",
                       icon: m.clicking ? "stop.fill" : "play.fill",
                       active: m.clicking, hint: m.settings.toggleKey?.label) { m.toggleClicking() }
            if m.clicking, let r = m.clickRunner {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    Text("\(r.count) clicks")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Card(title: "Mouse", icon: "computermouse.fill") {
                Picker("", selection: $m.settings.button) {
                    Text("Left").tag(0); Text("Right").tag(1); Text("Middle").tag(2)
                }.pickerStyle(.segmented).labelsHidden()
                Picker("", selection: $m.settings.doubleClick) {
                    Text("Single click").tag(false); Text("Double click").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }

            Card(title: "Position", icon: "scope") {
                Picker("", selection: $m.settings.useFixedPoint) {
                    Text("Follow cursor").tag(false); Text("Fixed point").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                if m.settings.useFixedPoint || m.picking {
                    HStack {
                        Text(m.picking ? "Click anywhere on screen…" : "x \(Int(m.settings.fixedX))   y \(Int(m.settings.fixedY))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(m.picking ? Theme.accent : .secondary)
                        Spacer()
                        Button(m.picking ? "Cancel" : "Pick Location") { m.picking.toggle() }
                            .controlSize(.small)
                    }
                }
            }

            Card(title: "Stop After", icon: "timer") {
                Picker("", selection: $m.settings.stopMode) {
                    Text("Never").tag(0); Text("Clicks").tag(1); Text("Time").tag(2)
                }.pickerStyle(.segmented).labelsHidden()
                if m.settings.stopMode == 1 {
                    Row(label: "Number of clicks") {
                        NumberField(value: $m.settings.stopClicks, range: 1...10_000_000)
                    }
                } else if m.settings.stopMode == 2 {
                    Row(label: "Seconds") {
                        NumberField(value: $m.settings.stopSeconds, range: 0.1...86_400)
                    }
                }
            }

            Card(title: "Humanize", icon: "waveform.path") {
                Row(label: "Randomize interval") {
                    Text("±\(Int(m.settings.jitter))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Slider(value: $m.settings.jitter, in: 0...50, step: 1)
            }
        }
    }

    private var speedCard: some View {
        Card(title: "Speed", icon: "bolt.fill") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(m.settings.cps, format: .number.precision(.fractionLength(m.settings.cps < 10 ? 1 : 0)))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("clicks / sec").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    NumberField(value: $m.settings.cps, range: 0.1...500)
                    Text("\(1000 / m.settings.cps, specifier: "%.1f") ms")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Slider(value: Binding(get: { min(m.settings.cps, 100) }, set: { m.settings.cps = $0.rounded() }), in: 1...100)
            HStack {
                ForEach([1.0, 5, 10, 20, 50, 100], id: \.self) { v in
                    Button("\(Int(v))") { withAnimation { m.settings.cps = v } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background((m.settings.cps == v ? Theme.accent : Theme.field), in: Capsule())
                }
            }
        }
    }
}

struct NumberField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                  format: .number)
            .textFieldStyle(.roundedBorder).frame(width: 90).multilineTextAlignment(.trailing)
    }
}

extension NumberField {
    init(value: Binding<Int>, range: ClosedRange<Int>) {
        _value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
        self.range = Double(range.lowerBound)...Double(range.upperBound)
    }
}

// MARK: Macro

struct MacroTab: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Recorder", icon: "record.circle") {
                Label(m.macroName ?? (m.macro.isEmpty ? "No macro" : "Unsaved macro"),
                      systemImage: m.macroName == nil ? "doc" : "doc.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(m.macroName == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 0) {
                    stat("\(m.macro.count)", "events")
                    stat(String(format: "%.1fs", m.macroDuration), "length")
                    stat("\(m.macro.filter { $0.isDown && !$0.isKey }.count)", "clicks")
                    stat("\(m.macro.filter { $0.cgType == .keyDown }.count)", "keys")
                }
                GlowButton(title: m.recording ? "Stop Recording" : "Record Macro",
                           icon: m.recording ? "stop.fill" : "record.circle.fill",
                           active: m.recording, hint: m.settings.recordKey?.label, color: Theme.record) { m.toggleRecording() }
                GlowButton(title: m.playing ? "Stop Macro" : "Play Macro",
                           icon: m.playing ? "stop.fill" : "play.fill",
                           active: m.playing, hint: m.settings.macroKey?.label, color: Theme.play) { m.togglePlaying() }
                    .disabled(m.macro.isEmpty || m.recording)
                    .opacity(m.macro.isEmpty || m.recording ? 0.45 : 1)
                if m.playing, let r = m.playRunner {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text("Loops completed: \(r.count)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
            }

            Card(title: "Playback", icon: "slider.horizontal.3") {
                Row(label: "Repeat") {
                    Text(m.settings.macroRepeat == 0 ? "Forever" : "\(m.settings.macroRepeat)×")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Stepper("", value: $m.settings.macroRepeat, in: 0...100_000).labelsHidden()
                }
                Row(label: "Speed") {
                    Text("\(m.settings.macroSpeed, specifier: "%.2g")×")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Slider(value: $m.settings.macroSpeed, in: 0.25...4, step: 0.25)
                Toggle("Record mouse movement", isOn: $m.settings.recordMoves).toggleStyle(.switch)
            }

            Card(title: "Library", icon: "folder") {
                HStack {
                    Button { m.saveMacroToFile() } label: { Label("Save Macro…", systemImage: "square.and.arrow.down") }
                        .disabled(m.macro.isEmpty || m.recording)
                    Button { m.openMacroFile() } label: { Label("Open Macro…", systemImage: "folder") }
                        .disabled(m.recording || m.playing)
                    Spacer()
                    Button(role: .destructive) { m.clearMacro() } label: { Label("Clear", systemImage: "trash") }
                        .disabled(m.macro.isEmpty || m.recording)
                }
            }

            Text("Records clicks, drags, scrolls and keystrokes anywhere on screen. Clicks on Pulsar's own window are ignored — use the shortcut to stop recording from any app.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 20, weight: .heavy, design: .rounded))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Hotkeys

struct HotkeysTab: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Global Shortcuts", icon: "keyboard") {
                ForEach(Slot.allCases) { slot in
                    Row(label: slot.title) { HotkeyRecorder(slot: slot) }
                }
            }
            Card(title: "Behavior", icon: "hand.tap.fill") {
                Toggle(isOn: $m.settings.holdMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hold to click")
                        Text("Clicks only while the start shortcut is held down.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch)
            }
            Text("Click a shortcut, then press any key combo (e.g. ⌃S, F6) or a mouse button — side buttons work too. Left/right click need a modifier. Esc cancels.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

struct HotkeyRecorder: View {
    @EnvironmentObject var m: AppModel
    let slot: Slot

    var body: some View {
        let active = m.capturing == slot
        HStack(spacing: 4) {
            Button { m.capturing = active ? nil : slot } label: {
                Text(active ? "Press shortcut…" : m.settings[keyPath: slot.path]?.label ?? "None")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? Theme.accent : .primary)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.accent : Theme.stroke))
            }
            .buttonStyle(.plain)
            .disabled(!m.trusted)
            Button { m.settings[keyPath: slot.path] = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(m.settings[keyPath: slot.path] == nil ? 0 : 1)
        }
    }
}

// MARK: Menu bar

struct MenuContent: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(m.clicking ? "Stop Clicking" : "Start Clicking") { m.toggleClicking() }
        Button(m.playing ? "Stop Macro" : "Play Macro") { m.togglePlaying() }.disabled(m.macro.isEmpty)
        Divider()
        Button("Show Pulsar") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Pulsar") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
