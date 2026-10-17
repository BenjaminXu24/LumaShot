import AppKit
import Carbon

/// Registers application-wide shortcuts without taking over macOS screenshot shortcuts.
@MainActor
final class GlobalHotKeyManager {
    private let onCapture: (CaptureMode) -> Void
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x4C554D41 // LUMA

    init(onCapture: @escaping (CaptureMode) -> Void) {
        self.onCapture = onCapture
    }

    @discardableResult
    func registerDefaults() -> [String] {
        unregisterAll()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            lumaShotHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            return ["无法启用全局快捷键（错误 \(handlerStatus)），仍可使用菜单栏截图。"]
        }

        let bindings: [(UInt32, CaptureMode)] = [
            (UInt32(kVK_ANSI_1), .region),
            (UInt32(kVK_ANSI_2), .window),
            (UInt32(kVK_ANSI_3), .fullscreen),
            (UInt32(kVK_ANSI_4), .scroll)
        ]
        var errors: [String] = []
        for (offset, binding) in bindings.enumerated() {
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: signature, id: UInt32(offset + 1))
            let status = RegisterEventHotKey(
                binding.0,
                UInt32(controlKey | shiftKey),
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            if status == noErr, let hotKey {
                hotKeys.append(hotKey)
            } else {
                errors.append("快捷键 ⌃⇧\(offset + 1) 被占用或无法注册（错误 \(status)）。")
            }
        }
        return errors
    }

    func unregisterAll() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handle(identifier: EventHotKeyID) {
        guard identifier.signature == signature else { return }
        switch identifier.id {
        case 1: onCapture(.region)
        case 2: onCapture(.window)
        case 3: onCapture(.fullscreen)
        case 4: onCapture(.scroll)
        default: break
        }
    }

    deinit {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

private let lumaShotHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.handle(identifier: identifier)
    }
    return noErr
}
