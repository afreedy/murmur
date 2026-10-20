import AppKit
import ApplicationServices

final class Hotkey {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false
    private var spaceConsumed = false
    var enabled = true
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onHandsFree: (() -> Void)?
    var onEscape: (() -> Void)?
    var shouldCancel: (() -> Bool)?
    var onTargetInput: ((CGPoint?) -> Void)?

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: mask,
                                            callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            return Unmanaged<Hotkey>.fromOpaque(pointer).takeUnretainedValue().handle(type, event)
        }, userInfo: pointer) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            onTargetInput?(nil)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if held { held = false; DispatchQueue.main.async { self.onRelease?() } }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == 0x4c574850 { return Unmanaged.passUnretained(event) }
        guard enabled else { return Unmanaged.passUnretained(event) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown && key == 49 && (held || event.flags.contains(.maskSecondaryFn)) {
            if !spaceConsumed {
                spaceConsumed = true
                DispatchQueue.main.async { self.onHandsFree?() }
            }
            return nil
        }
        if type == .keyUp && key == 49 && spaceConsumed { spaceConsumed = false; return nil }
        if type == .flagsChanged && key == 63 {
            let down = event.flags.contains(.maskSecondaryFn)
            if down != held {
                held = down
                if down { DispatchQueue.main.async { self.onPress?() } }
                else { DispatchQueue.main.async { self.onRelease?() } }
            }
            return nil
        }
        if (held || shouldCancel?() == true) && type == .keyDown && key == 53 {
            DispatchQueue.main.async { self.onEscape?() }
            return nil
        }
        if type == .keyDown { onTargetInput?(nil) }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type) {
            onTargetInput?(event.location)
        }
        return Unmanaged.passUnretained(event)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; held = false; spaceConsumed = false
    }
}
