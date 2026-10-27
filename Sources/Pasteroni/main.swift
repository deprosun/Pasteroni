import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Model

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
    var pinned = false
    var name: String?
    var sourceApp: String?

    var kind: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.contains(where: \.isWhitespace), let u = URL(string: t), u.scheme?.hasPrefix("http") == true { return "URL" }
        let codeHints = ["{", "}", ";", "func ", "def ", "=>", "</", "import ", "#include"]
        if t.contains("\n"), codeHints.filter({ t.contains($0) }).count >= 2 { return "Code" }
        return "Text"
    }
    var title: String {
        if let n = name, !n.isEmpty { return n }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    }
}

final class Store: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var query = ""
    @Published var selection: UUID?

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pasteroni")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    var limit: Int { get { let v = UserDefaults.standard.integer(forKey: "limit"); return v == 0 ? 100 : v }
                     set { UserDefaults.standard.set(newValue, forKey: "limit"); trim() } }
    var privateMode: Bool { get { UserDefaults.standard.bool(forKey: "private") }
                            set { UserDefaults.standard.set(newValue, forKey: "private") } }
    var excluded: [String] { get { UserDefaults.standard.stringArray(forKey: "excluded") ?? ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess"] }
                             set { UserDefaults.standard.set(newValue, forKey: "excluded") } }

    init() {
        if let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([Clip].self, from: d) { clips = c }
    }
    func save() { try? JSONEncoder().encode(clips).write(to: file) }

    var visible: [Clip] {
        let f = query.isEmpty ? clips : clips.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) }
        return f.filter(\.pinned) + f.filter { !$0.pinned }
    }

    func add(_ text: String, source: String?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var pinned = false, name: String?
        if let i = clips.firstIndex(where: { $0.text == text }) { pinned = clips[i].pinned; name = clips[i].name; clips.remove(at: i) }
        clips.insert(Clip(text: text, pinned: pinned, name: name, sourceApp: source), at: 0)
        trim(); save()
    }
    func trim() {
        var unpinned = 0
        clips = clips.filter { $0.pinned || { unpinned += 1; return unpinned <= limit }() }
        save()
    }
    func update(_ c: Clip) { if let i = clips.firstIndex(where: { $0.id == c.id }) { clips[i] = c; save() } }
    func delete(_ c: Clip) { clips.removeAll { $0.id == c.id }; save() }
    func clearUnpinned() { clips.removeAll { !$0.pinned }; save() }

    func move(_ d: Int) {
        let v = visible; guard !v.isEmpty else { return }
        let i = v.firstIndex { $0.id == selection } ?? (d > 0 ? -1 : v.count)
        selection = v[max(0, min(v.count - 1, i + d))].id
    }
}

// MARK: - UI

func ago(_ d: Date) -> String {
    let s = Int(-d.timeIntervalSinceNow)
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

struct RowView: View {
    let clip: Clip; let index: Int; let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(index < 10 ? "⌘\((index + 1) % 10)" : "").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if clip.pinned { Image(systemName: "pin.fill").font(.caption2) }
                    Text(clip.title).lineLimit(1)
                }
                Text("\(clip.kind) · \(ago(clip.date))" + (clip.sourceApp.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

struct PanelView: View {
    @ObservedObject var store: Store
    var paste: (Clip) -> Void
    var edit: (Clip, Bool) -> Void
    @FocusState private var focus: Bool

    var body: some View {
        let v = store.visible
        VStack(spacing: 0) {
            TextField("Search clips", text: $store.query).textFieldStyle(.roundedBorder).padding(8).focused($focus)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(v.enumerated()), id: \.element.id) { i, c in
                            RowView(clip: c, index: i, selected: c.id == store.selection)
                                .id(c.id)
                                .onTapGesture { paste(c) }
                                .contextMenu {
                                    Button(c.pinned ? "Unpin" : "Pin") { var n = c; n.pinned.toggle(); store.update(n) }
                                    Button("Rename…") { edit(c, true) }
                                    Button("Edit…") { edit(c, false) }
                                    Button("Delete") { store.delete(c) }
                                }
                        }
                    }.padding(4)
                }
                .onChange(of: store.selection) { s in if let s { proxy.scrollTo(s) } }
            }
            if v.isEmpty { Text("No clips").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
            if let s = v.first(where: { $0.id == store.selection }) {
                Divider()
                Text(s.text).font(.caption).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
        .frame(width: 380, height: 460)
        .background(.regularMaterial)
        .onAppear { focus = true }
    }
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var item: NSStatusItem!
    var panel: Panel!
    var lastCount = NSPasteboard.general.changeCount
    var previousApp: NSRunningApplication?
    var monitor: Any?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png"), let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18); img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pasteroni")
        }
        item.button?.target = self
        item.button?.action = #selector(statusClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let view = PanelView(store: store, paste: { [weak self] in self?.paste($0) }, edit: { [weak self] c, rename in self?.edit(c, rename) })
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        registerHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) ?? e }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in self?.panel.orderOut(nil) }
    }

    // Clipboard capture
    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard !store.privateMode else { return }
        let types = Set((pb.types ?? []).map(\.rawValue))
        if !types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]) { return }
        let app = NSWorkspace.shared.frontmostApplication
        if let b = app?.bundleIdentifier, store.excluded.contains(b) { return }
        if let s = pb.string(forType: .string) { DispatchQueue.main.async { self.store.add(s, source: app?.localizedName) } }
    }

    // Panel
    func togglePanel() { panel.isVisible ? panel.orderOut(nil) : showPanel(at: nil) }

    func showPanel(at point: NSPoint?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        store.query = ""; store.selection = store.visible.first?.id
        let loc = point ?? NSEvent.mouseLocation
        var o = NSPoint(x: loc.x - 190, y: loc.y - 460)
        if let f = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.visibleFrame {
            o.x = max(f.minX, min(f.maxX - 380, o.x)); o.y = max(f.minY, min(f.maxY - 460, o.y))
        }
        panel.setFrameOrigin(o)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func key(_ e: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return e }
        switch Int(e.keyCode) {
        case kVK_DownArrow: store.move(1); return nil
        case kVK_UpArrow: store.move(-1); return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let c = store.visible.first(where: { $0.id == store.selection }) { delayed(c) }; return nil
        case kVK_Escape: panel.orderOut(nil); return nil
        default: break
        }
        if e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers, let d = Int(ch) {
            let i = d == 0 ? 9 : d - 1
            if i < store.visible.count { delayed(store.visible[i]) }
            return nil
        }
        return e
    }

    // Wait for the key to be released so the key-up isn't delivered to an app that never saw the key-down (which beeps).
    func delayed(_ c: Clip) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.paste(c) } }

    func paste(_ c: Clip) {
        panel.orderOut(nil)
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(c.text, forType: .string)
        lastCount = pb.changeCount
        var n = c; n.date = Date(); store.update(n)
        previousApp?.activate()
    }

    func edit(_ c: Clip, _ rename: Bool) {
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = rename ? "Rename clip" : "Edit clip"
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: rename ? 24 : 120))
        f.stringValue = rename ? (c.name ?? "") : c.text
        a.accessoryView = f
        if a.runModal() == .alertFirstButtonReturn {
            var n = c
            if rename { n.name = f.stringValue } else { n.text = f.stringValue }
            store.update(n)
        }
    }

    // Status menu
    @objc func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else if let b = item.button, let w = b.window {
            let r = w.frame; showPanel(at: NSPoint(x: r.midX, y: r.minY - 4))
        }
    }

    func showMenu() {
        let m = NSMenu()
        let p = NSMenuItem(title: "Private Mode", action: #selector(togglePrivate), keyEquivalent: ""); p.target = self
        p.state = store.privateMode ? .on : .off; m.addItem(p)
        let lim = NSMenu()
        for n in [25, 50, 100, 200, 500] {
            let i = NSMenuItem(title: "\(n)", action: #selector(setLimit(_:)), keyEquivalent: ""); i.target = self; i.tag = n
            i.state = store.limit == n ? .on : .off; lim.addItem(i)
        }
        let l = NSMenuItem(title: "History Limit", action: nil, keyEquivalent: ""); l.submenu = lim; m.addItem(l)
        if let app = previousApp ?? NSWorkspace.shared.frontmostApplication, let b = app.bundleIdentifier {
            let ex = NSMenuItem(title: "Exclude \(app.localizedName ?? b)", action: #selector(excludeApp(_:)), keyEquivalent: "")
            ex.target = self; ex.representedObject = b; m.addItem(ex)
        }
        let ems = NSMenu()
        for b in store.excluded {
            let i = NSMenuItem(title: b, action: #selector(unexclude(_:)), keyEquivalent: ""); i.target = self; ems.addItem(i)
        }
        let e = NSMenuItem(title: "Excluded Apps (click to remove)", action: nil, keyEquivalent: ""); e.submenu = ems; m.addItem(e)
        m.addItem(.separator())
        let c = NSMenuItem(title: "Clear History (keeps pinned)", action: #selector(clear), keyEquivalent: ""); c.target = self; m.addItem(c)
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m; item.button?.performClick(nil); item.menu = nil
    }
    @objc func togglePrivate() { store.privateMode.toggle() }
    @objc func setLimit(_ s: NSMenuItem) { store.limit = s.tag }
    @objc func excludeApp(_ s: NSMenuItem) { if let b = s.representedObject as? String { store.excluded.append(b) } }
    @objc func unexclude(_ s: NSMenuItem) { store.excluded.removeAll { $0 == s.title } }
    @objc func clear() { store.clearUnpinned() }

    // Global hotkey: Control+Space
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ud in
            Unmanaged<AppDelegate>.fromOpaque(ud!).takeUnretainedValue().togglePanel()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey), EventHotKeyID(signature: OSType(0x434C4950), id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
