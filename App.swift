import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices

final class Controller: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var history: [TranscriptEntry] = []
    @Published var historyError = ""
    private var archivedSession = ""
    private var historyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Murmur/transcriptions.json")
    }
    @Published var status = "Loading Whisper…"
    @Published var lastWarning = UserDefaults.standard.string(forKey: "lastDictationWarning") ?? ""
    @Published var notice = "" {
        didSet {
            if !notice.isEmpty {
                lastWarning = notice
                UserDefaults.standard.set(notice, forKey: "lastDictationWarning")
            }
        }
    }
    @Published var localReady = false
    @Published var lunaReady = false
    @Published var microphoneAllowed = false
    @Published var accessibilityAllowed = false
    @Published var flowRunning = false
    @Published var enabled = UserDefaults.standard.bool(forKey: "dictationEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "dictationEnabled") }
    }
    @Published var listening = false
    @Published var finishing = false
    @Published var handsFree = false
    @Published var pillHovered = false
    @Published var pillExpanded = false
    @Published var noteSaveError = ""
    @Published var note = "" { didSet { scheduleNoteSave() } }
    private var scratchWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var noteSave: DispatchWorkItem?
    private var hoverExit: DispatchWorkItem?
    private var hoverCollapse: DispatchWorkItem?
    private var noteURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Murmur/scratchpad.txt")
    }
    @Published var level: Float = 0
    @Published var raw = ""
    @Published var refined = ""
    @Published var showRaw = false
    @Published var timing = ""
    @Published private(set) var vocabulary = UserDefaults.standard.string(forKey: "dictationVocabulary") ?? "" {
        didSet {
            UserDefaults.standard.set(vocabulary, forKey: "dictationVocabulary")
        }
    }
    func setVocabulary(_ text: String) {
        vocabulary = String(String.UnicodeScalarView(text.unicodeScalars.prefix(500)))
    }
    @Published var refineWithLuna = UserDefaults.standard.object(forKey: "refineWithLuna") as? Bool ?? true {
        didSet { UserDefaults.standard.set(refineWithLuna, forKey: "refineWithLuna") }
    }
    private let mic = Microphone()
    private let hotkey = Hotkey()
    private let whisper = PipeWorker()
    private let luna = PipeWorker()
    private var target: TextTarget?
    private var canInsert = false
    private var session = UUID().uuidString
    private var hotkeyReady = false
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var window: NSWindow?
    private var pill: NSPanel?
    private var poll: Timer?
    private var recordingLimit: Timer?
    private var lastWhisperSeconds: Double = 0
    private var accessibilityAppPID: pid_t?
    private var activationObserver: NSObjectProtocol?

    var canEnable: Bool {
        localReady && microphoneAllowed && accessibilityAllowed && hotkeyReady && !flowRunning && (!refineWithLuna || lunaReady)
    }
    var active: Bool { listening || finishing }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        loadNote(); loadHistory()
        let menu = NSMenu()
        let appMenuItem = NSMenuItem(); menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Murmur", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Open Murmur", action: #selector(openWindow), keyEquivalent: ",").target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        let editMenuItem = NSMenuItem(); menu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu; NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 20, height: 20); image.isTemplate = true
            statusItem?.button?.image = image
        }
        statusItem?.button?.toolTip = "Murmur — dictation and scratch pad"
        statusItem?.button?.target = self; statusItem?.button?.action = #selector(showPopover)
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(controller: self)); self.popover = popover
        mic.onLevel = { [weak self] level in DispatchQueue.main.async { self?.level = level } }
        mic.onError = { [weak self] message in DispatchQueue.main.async { self?.notice = message; self?.cancelRecording() } }
        whisper.onMessage = { [weak self] value in self?.whisperMessage(value) }
        luna.onMessage = { [weak self] value in self?.lunaMessage(value) }
        hotkey.onPress = { [weak self] in self?.fnPressed() }
        hotkey.onRelease = { [weak self] in self?.fnReleased() }
        hotkey.onHandsFree = { [weak self] in
            guard let self else { return }
            if self.listening {
                self.handsFree = true; self.status = "Recording hands-free. Press Fn to stop."
            } else if !self.active { self.toggleHandsFree() }
        }
        hotkey.onEscape = { [weak self] in self?.cancelRecording() }
        hotkey.shouldCancel = { [weak self] in self?.active ?? false }
        hotkey.onTargetInput = { [weak self] point in
            guard let self, self.active, self.target?.requiresInputGuard == true else { return }
            if let point, let screen = NSScreen.screens.first,
               self.pill?.frame.contains(NSPoint(x: point.x, y: screen.frame.maxY - point.y)) == true { return }
            self.invalidateOpaqueTarget()
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.active, self.target?.requiresInputGuard == true { self.invalidateOpaqueTarget() }
            self.prepareFrontmostAccessibility()
        }
        refreshPermissions()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPermissions() }
        do { try whisper.start(script: "worker") }
        catch { notice = error.localizedDescription; status = "Whisper unavailable" }
        do { try luna.start(script: "luna") }
        catch { notice = error.localizedDescription }
        showWindow(); showPill()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return false
    }
    @objc func openWindow() { showWindow() }

    func refreshPermissions() {
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAllowed = AXIsProcessTrusted()
        prepareFrontmostAccessibility()
        flowRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.wispr-flow").isEmpty
        hotkeyReady = accessibilityAllowed && hotkey.start()
        hotkey.enabled = enabled && canEnable
        if !active { showPill() }
        if (!accessibilityAllowed || !microphoneAllowed || flowRunning) && listening { canInsert = false; stopRecording() }
    }
    private func prepareFrontmostAccessibility() {
        guard accessibilityAllowed, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != accessibilityAppPID else { return }
        accessibilityAppPID = app.processIdentifier
        TextTarget.prepareAccessibility(for: app)
    }
    private func invalidateOpaqueTarget() {
        canInsert = false
        notice = "Input or window changed in an editor that hides its cursor. Click Copy to paste the completed text yourself."
    }
    func allowMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.refreshPermissions() } }
        } else { privacySettings("Microphone") }
    }
    func privacySettings(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)") { NSWorkspace.shared.open(url) }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options); privacySettings("Accessibility")
    }
    func quitFlow() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.wispr-flow") { app.terminate() }
    }
    func toggleEnabled() {
        if enabled { enabled = false; cancelRecording(); status = "Dictation paused" }
        else if canEnable { enabled = true; notice = ""; status = "Ready. Hold Fn or press Fn + Space."; window?.orderOut(nil); popover?.close() }
        hotkey.enabled = enabled && canEnable
    }
    func fnPressed() {
        if listening && handsFree { stopRecording(); return }
        guard !active else { return }
        handsFree = false; beginRecording()
    }
    func fnReleased() {
        if listening && !handsFree { stopRecording() }
    }
    func toggleHandsFree() {
        if listening { stopRecording(); return }
        guard !active, canEnable else { return }
        enabled = true; hotkey.enabled = true; handsFree = true
        beginRecording()
        if !listening { handsFree = false }
    }
    func beginRecording() {
        guard enabled, canEnable, !active else { return }
        do {
            target = try TextTarget.capture()
            session = UUID().uuidString
            let recordingSession = session
            mic.onLevel = { [weak self] value in DispatchQueue.main.async {
                guard let self, self.session == recordingSession else { return }; self.level = value
            } }
            raw = ""; refined = ""; notice = ""; timing = ""; canInsert = true
            popover?.close()
            if refineWithLuna && lunaReady { luna.send(["type": "prepare", "id": session]) }
            try mic.start()
            listening = true; status = handsFree ? "Recording hands-free. Press Fn to stop." : "Recording. Release Fn to stop."
            showPill()
            recordingLimit = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                self?.notice = "Reached the three-minute limit. Start another recording to continue."; self?.stopRecording()
            }
        } catch { notice = error.localizedDescription; showPill() }
    }
    func stopRecording() {
        guard listening else { return }
        handsFree = false
        listening = false; finishing = true; status = "Transcribing…"
        showPill()
        recordingLimit?.invalidate(); recordingLimit = nil
        let samples = mic.stop(); level = 0
        guard samples.count >= 1600 else { notice = "The recording was too short. Try again."; finish(); return }
        let bytes = samples.withUnsafeBytes { Data($0) }
        whisper.send(["id": session, "sequence": 1, "audio": bytes.base64EncodedString(), "language": "en", "vocabulary": vocabulary])
    }
    func cancelRecording() {
        guard active else { return }
        whisper.send(["type": "cancel", "id": session])
        luna.send(["type": "cancel", "id": session])
        handsFree = false
        canInsert = false; recordingLimit?.invalidate(); recordingLimit = nil
        mic.stop(discard: true); session = UUID().uuidString
        listening = false; finishing = false; level = 0
        status = "Cancelled. Nothing pasted."; showPill()
    }
    func whisperMessage(_ value: [String: Any]) {
        let type = value["type"] as? String ?? ""
        if type == "ready" { localReady = true; status = "Whisper ready on \((value["device"] as? String) == "mps" ? "Apple GPU" : "CPU")"; return }
        if type == "fatal" { localReady = false; notice = value["message"] as? String ?? "Whisper stopped"; canInsert = false; finish(); return }
        guard value["id"] as? String == session, finishing else { return }
        if type == "error" { notice = value["message"] as? String ?? "Transcription failed"; finish(); return }
        guard type == "result" else { return }
        raw = (value["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lastWhisperSeconds = value["seconds"] as? Double ?? 0
        guard !raw.isEmpty else { notice = "No speech detected. Check your microphone and try again."; finish(); return }
        if refineWithLuna {
            guard lunaReady else { notice = "Luna is unavailable. Select Raw and copy your transcript."; finish(); return }
            status = "Formatting with Luna…"
            luna.send(["id": session, "sequence": 1, "text": raw, "kind": "format", "context": ""])
        } else { refined = raw; pasteFinal(); finish() }
    }
    func lunaMessage(_ value: [String: Any]) {
        let type = value["type"] as? String ?? ""
        if type == "ready" { lunaReady = true; return }
        if type == "fatal" {
            lunaReady = false; notice = value["message"] as? String ?? "Luna is unavailable. The raw transcript is still available."; canInsert = false
            if listening { stopRecording() } else { finish() }; return
        }
        guard value["id"] as? String == session, finishing else { return }
        if type == "delta" { refined += value["text"] as? String ?? "" }
        else if type == "result" {
            refined = (value["text"] as? String ?? refined).trimmingCharacters(in: .whitespacesAndNewlines)
            timing = String(format: "Transcribed %.2fs · Formatted %.2fs", lastWhisperSeconds, value["seconds"] as? Double ?? 0)
            if value["cached"] as? Bool == true { timing += " · Luna cache" }
            if !refined.isEmpty { pasteFinal() }
            finish()
        } else if type == "error" {
            notice = "Formatting failed. Select Raw and copy your transcript."; finish()
        }
    }
    private func pasteFinal() {
        guard canInsert else { return }
        do { try target?.paste(refined) }
        catch { canInsert = false; notice = error.localizedDescription }
    }
    private func finish() {
        archiveTranscript()
        handsFree = false
        mic.stop(discard: true); recordingLimit?.invalidate(); recordingLimit = nil
        listening = false; finishing = false; level = 0
        status = enabled ? "Ready. Hold Fn or press Fn + Space." : "Ready. Enable dictation to start."
        showPill()
    }
    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        do { history = try JSONDecoder().decode([TranscriptEntry].self, from: Data(contentsOf: historyURL)) }
        catch { historyError = "History could not be opened. The saved file has not been changed." }
    }
    private func archiveTranscript() {
        guard !raw.isEmpty, archivedSession != session else { return }
        archivedSession = session
        history.append(TranscriptEntry(id: session, date: Date(), raw: raw, formatted: refined, warning: notice))
        guard historyError.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch { historyError = "History could not be saved. Copy any text you need before quitting." }
    }
    func copyTranscript() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(showRaw ? raw : refined, forType: .string)
    }
    @objc func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown { popover.close() }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func showWindow() {
        popover?.close()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Murmur"; w.minSize = NSSize(width: 760, height: 660)
            w.titlebarAppearsTransparent = true; w.backgroundColor = NSColor(Theme.green); w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(controller: self)); w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func setPillHovered(_ hovered: Bool) {
        hoverExit?.cancel(); hoverCollapse?.cancel()
        if hovered {
            if !pillExpanded {
                pillExpanded = true; showPill()
                DispatchQueue.main.async { [weak self] in self?.pillHovered = true }
            } else { pillHovered = true }
        } else {
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pillHovered = false
                let collapse = DispatchWorkItem { [weak self] in
                    guard let self, !self.pillHovered else { return }
                    self.pillExpanded = false; self.showPill()
                }
                self.hoverCollapse = collapse
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: collapse)
            }
            hoverExit = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
        }
    }
    @objc func showAbout() {
        if aboutWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "About Murmur"; w.titlebarAppearsTransparent = true; w.backgroundColor = NSColor(Theme.green)
            w.isReleasedWhenClosed = false; w.contentView = NSHostingView(rootView: AboutView()); w.center(); aboutWindow = w
        }
        popover?.close(); NSApp.activate(ignoringOtherApps: true); aboutWindow?.makeKeyAndOrderFront(nil)
    }
    func showScratchpad() {
        if scratchWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Murmur — Scratch pad"; w.minSize = NSSize(width: 360, height: 300)
            w.isReleasedWhenClosed = false; w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(Theme.green)
            w.contentView = NSHostingView(rootView: ScratchpadView(controller: self)); w.center(); scratchWindow = w
        }
        popover?.close(); NSApp.activate(ignoringOtherApps: true); scratchWindow?.makeKeyAndOrderFront(nil)
    }
    private func loadNote() {
        do { note = try String(contentsOf: noteURL, encoding: .utf8) }
        catch { if FileManager.default.fileExists(atPath: noteURL.path) { noteSaveError = "Notes could not be opened. Reopen Murmur to try again." } }
    }
    private func scheduleNoteSave() {
        guard noteSaveError.isEmpty else { return }
        noteSave?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveNote() }
        noteSave = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }
    private func saveNote() {
        do {
            try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try note.write(to: noteURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: noteURL.path)
            noteSaveError = ""
        } catch { noteSaveError = "Notes could not be saved. Copy them before quitting." }
    }
    func copyNote() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note, forType: .string)
    }
    private func showPill() {
        if pill == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 68), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating; p.ignoresMouseEvents = false
            p.becomesKeyOnlyIfNeeded = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: DictationPill(controller: self)); pill = p
        }
        let width: CGFloat = active ? (pillExpanded ? 600 : 360) : (pillExpanded ? 320 : 84)
        let height: CGFloat = active ? 68 : 44
        let size = NSSize(width: width, height: height)
        if let screen = NSScreen.main?.visibleFrame {
            let frame = NSRect(x: screen.midX - size.width / 2, y: screen.minY + 14, width: size.width, height: size.height)
            if pill?.frame != frame { pill?.setFrame(frame, display: true) }
        }
        pill?.orderFrontRegardless()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        hoverExit?.cancel(); hoverCollapse?.cancel(); noteSave?.cancel()
        if noteSaveError.isEmpty { saveNote() }
        recordingLimit?.invalidate(); poll?.invalidate(); mic.stop(discard: true); hotkey.stop(); whisper.stop(); luna.stop()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        return .terminateNow
    }
}

@main struct CodexLuna {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-check") { checkCoreLogic(); return }
        if CommandLine.arguments.contains("--diagnose") {
            let result: [String: Any] = ["microphone": AVCaptureDevice.authorizationStatus(for: .audio).rawValue, "accessibility": AXIsProcessTrusted(), "inputMonitoring": CGPreflightListenEventAccess(), "modelCached": FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/whisper/large-v3-turbo.pt").path), "python": (try? PipeWorker.pythonPath()) ?? "missing"]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        let app = NSApplication.shared; let delegate = Controller(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
