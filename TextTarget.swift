import AppKit
import ApplicationServices
import Carbon

func insertionPrefix(before: String, text: String) -> String {
    guard let previous = before.last else { return "" }
    let isList = text.range(of: #"^(?:\d+[.)]|[-*•])\s"#, options: .regularExpression) != nil
    if isList { return previous == "\n" ? "" : "\n" }
    guard !previous.isWhitespace, let first = text.first, !first.isWhitespace,
          ![".", ",", ";", ":", "!", "?", ")", "]"].contains(String(first)),
          !["(", "[", "\"", "@", "/"].contains(String(previous)) else { return "" }
    return " "
}

struct TextTarget {
    private static var pendingClipboardRestore: (() -> Void)?
    let pid: pid_t
    let element: AXUIElement?
    let expectedSelection: CFRange?
    let windowID: CGWindowID?
    var requiresInputGuard: Bool { expectedSelection == nil }

    static func prepareAccessibility(for app: NSRunningApplication) {
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        // Electron/Chromium may not publish their editor tree until assistive technology requests it.
        AXUIElementSetAttributeValue(owner, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(owner, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    static func frontWindowID(for pid: pid_t) -> CGWindowID? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.first {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }.flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    static func focusedElement() -> AXUIElement? {
        func focused(in owner: AXUIElement) -> (AXUIElement?, AXError) {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(owner, kAXFocusedUIElementAttribute as CFString, &value)
            guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, result) }
            return ((value as! AXUIElement), result)
        }
        let system = focused(in: AXUIElementCreateSystemWide())
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if let element = system.0 {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier { return element }
        }
        let application = focused(in: AXUIElementCreateApplication(app.processIdentifier))
        // Some hosted web editors expose focus on the app but not the system-wide AX element.
        UserDefaults.standard.set([
            "application": app.bundleIdentifier ?? "unknown",
            "systemFocusError": system.1.rawValue,
            "applicationFocusError": application.1.rawValue,
            "applicationFocusRole": application.0.flatMap { string($0, kAXRoleAttribute) } ?? "missing"
        ], forKey: "lastFocusDiagnostic")
        return application.0
    }
    static func string(_ element: AXUIElement, _ key: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? String
    }
    static func selection(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
    static func capture() throws -> TextTarget {
        guard !IsSecureEventInputEnabled() else { throw error("Murmur cannot dictate while secure keyboard input is active.") }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw error("Click a text field, then hold Fn or press Fn + Space.")
        }
        prepareAccessibility(for: app)
        let element = focusedElement()
        if let element {
            let subrole = string(element, kAXSubroleAttribute) ?? ""
            guard subrole != kAXSecureTextFieldSubrole else { throw error("Murmur cannot paste into password fields.") }
            var enabled: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
            guard enabled as? Bool != false else { throw error("This field is disabled.") }
        }
        let selection = element.flatMap { Self.selection($0) }
        let textElement = element.flatMap {
            selection != nil || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(string($0, kAXRoleAttribute) ?? "") ? $0 : nil
        }
        let windowID = frontWindowID(for: app.processIdentifier)
        guard selection != nil || windowID != nil else { throw error("Click inside the destination window, then try again.") }
        return TextTarget(pid: app.processIdentifier, element: textElement, expectedSelection: selection, windowID: windowID)
    }
    func isStillFocused() -> Bool {
        guard !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let focused = Self.focusedElement()
        if let focused, Self.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return false }
        if let element {
            guard let focused, CFEqual(focused, element) else { return false }
        }
        if let expectedSelection, let element {
            guard let now = Self.selection(element) else { return false }
            return expectedSelection.location == now.location && expectedSelection.length == now.length
        }
        // shortcut: opaque editors expose no caret; require unchanged input and window instead.
        return windowID != nil && Self.frontWindowID(for: pid) == windowID
    }
    func paste(_ text: String) throws {
        guard isStillFocused() else { throw Self.error("The field or cursor changed. Nothing was pasted. Click Copy to paste the text yourself.") }
        var prefix = ""
        if let element, let caret = expectedSelection, caret.location >= 0, caret.length == 0,
           let value = Self.string(element, kAXValueAttribute), caret.location <= (value as NSString).length {
            prefix = insertionPrefix(before: (value as NSString).substring(to: caret.location), text: text)
        }
        let board = NSPasteboard.general
        Self.pendingClipboardRestore?()
        Self.pendingClipboardRestore = nil
        let original: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        func restore() {
            board.clearContents()
            let items = original.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            board.writeObjects(items)
        }
        board.clearContents()
        guard board.setString(prefix + text, forType: .string) else {
            restore(); throw Self.error("The clipboard could not be prepared. Click Copy to recover your text.")
        }
        let revision = board.changeCount
        guard isStillFocused(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            restore(); throw Self.error("The text field changed before pasting. Click Copy to paste the text yourself.")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: 0x4c574850)
        up.setIntegerValueField(.eventSourceUserData, value: 0x4c574850)
        down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
        // shortcut: apps provide no universal paste acknowledgement; allow five seconds before restoring.
        Self.pendingClipboardRestore = { if board.changeCount == revision { restore() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if board.changeCount == revision {
                restore()
                Self.pendingClipboardRestore = nil
            }
        }
    }
    static func error(_ text: String) -> NSError {
        NSError(domain: "CodexLuna", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
