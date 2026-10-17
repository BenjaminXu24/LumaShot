import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit

@MainActor
final class CaptureService: ObservableObject {
    @Published private(set) var isBusy = false
    var onCapture: ((NSImage, CaptureMode) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?

    static var hasScreenPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    func requestScreenPermission() -> Bool { CGRequestScreenCaptureAccess() }

    private var sessionID: UUID?
    private var operation: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var selectionOverlay: SelectionOverlay?
    private var controls: ScrollCaptureControls?
    private var hiddenWindows: [NSWindow] = []
    private var scrollSelection: SelectionOverlay.Selection?
    private var scrollContent: SCShareableContent?
    private var scrollTargetPID: pid_t?
    private var stitcher: ImageStitcher?
    private var originalMousePosition: CGPoint?
    private var escapeMonitor: Any?
    private var localKeyMonitor: Any?
    private var frameCaptureInProgress = false

    func capture(_ mode: CaptureMode) {
        guard !isBusy else { return }
        guard Self.hasScreenPermission || requestScreenPermission() else {
            onError?("请在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」允许 LumaShot 录制屏幕。授权后请重新打开应用再截图。")
            return
        }
        isBusy = true
        let id = UUID()
        sessionID = id
        hiddenWindows = NSApp.windows.filter { $0.isVisible && $0.level < .statusBar }
        hiddenWindows.forEach { $0.orderOut(nil) }
        onStatus?(mode == .scroll ? "框选需要滚动截图的内容区域" : "正在准备截图…")
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                // Allow AppKit's window removal to reach WindowServer first.
                try await Task.sleep(for: .milliseconds(150))
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.sessionID == id, !Task.isCancelled else { return }
                if mode == .fullscreen {
                    let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
                    guard let screen else { throw CaptureFailure.message("没有找到可用的显示器。") }
                    let image = try await self.captureImage(content: content, screen: screen, rect: screen.frame)
                    guard self.sessionID == id else { return }
                    self.finish(image: image, mode: mode)
                    return
                }
                let windows = self.orderedWindows(content.windows)
                let selection = await withCheckedContinuation { continuation in
                    let overlay = SelectionOverlay(mode: mode, windows: windows) { selection in
                        continuation.resume(returning: selection)
                    }
                    self.selectionOverlay = overlay
                    overlay.show()
                }
                self.selectionOverlay = nil
                guard self.sessionID == id, !Task.isCancelled else { return }
                guard let selection else { self.cancel(); return }
                try await Task.sleep(for: .milliseconds(100))
                if mode == .scroll {
                    try await self.beginScrolling(selection: selection, content: content, id: id)
                } else {
                    let image = try await self.captureImage(content: content, screen: selection.screen,
                                                           rect: selection.rect, window: selection.window)
                    guard self.sessionID == id else { return }
                    self.finish(image: image, mode: mode)
                }
            } catch is CancellationError {
                // cancel() has already removed the overlays and restored the UI.
            } catch {
                guard self.sessionID == id else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard isBusy else { return }
        cleanUp()
        onStatus?("已取消截图")
    }

    private func captureImage(content: SCShareableContent, screen: NSScreen, rect: CGRect,
                              window: SCWindow? = nil) async throws -> CGImage {
        // Scroll controls are created after the initial shareable-content query.
        // Refresh the application list so their process is always excluded.
        let content = controls == nil ? content : try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        if let window {
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.ignoreShadowsSingleWindow = true
        } else {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                throw CaptureFailure.message("所选显示器已断开，请重新选择截图区域。")
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let quartzRect = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
            config.sourceRect = quartzRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = max(1, Int(rect.width * scale))
            config.height = max(1, Int(rect.height * scale))
        }
        config.showsCursor = false
        config.scalesToFit = false
        config.shouldBeOpaque = true
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func orderedWindows(_ windows: [SCWindow]) -> [SCWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var order: [CGWindowID: Int] = [:]
        for (index, item) in list.enumerated() {
            if let number = item[kCGWindowNumber as String] as? NSNumber { order[number.uint32Value] = index }
        }
        return windows.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
            $0.windowLayer == 0 && $0.frame.width >= 40 && $0.frame.height >= 40 && $0.isOnScreen
        }.sorted { order[$0.windowID, default: .max] < order[$1.windowID, default: .max] }
    }

    private func beginScrolling(selection: SelectionOverlay.Selection, content: SCShareableContent, id: UUID) async throws {
        scrollSelection = selection
        scrollContent = content
        let primaryHeight = NSScreen.screens.first?.frame.height ?? selection.screen.frame.height
        let center = CGPoint(x: selection.rect.midX, y: primaryHeight - selection.rect.midY)
        if let target = orderedWindows(content.windows).first(where: { $0.frame.contains(center) }),
           let pid = target.owningApplication?.processID,
           let app = NSRunningApplication(processIdentifier: pid) {
            scrollTargetPID = pid
            app.activate(options: [])
            try await Task.sleep(for: .milliseconds(180))
        }
        let first = try await captureImage(content: content, screen: selection.screen, rect: selection.rect)
        guard sessionID == id else { return }
        guard let stitcher = ImageStitcher(firstImage: first) else { throw CaptureFailure.message("无法创建滚动截图，请缩小选择区域后重试。") }
        self.stitcher = stitcher
        let controls = ScrollCaptureControls()
        controls.state.height = first.height
        controls.state.accessibilityGranted = AXIsProcessTrusted()
        controls.state.onFinish = { [weak self] in self?.finishScrolling() }
        controls.state.onCancel = { [weak self] in self?.cancel() }
        controls.state.onAdd = { [weak self] in
            guard let self, !self.frameCaptureInProgress else { return }
            Task { await self.addScrollFrame(automatic: false) }
        }
        controls.state.onToggleAutomatic = { [weak self] in self?.toggleAutomatic() }
        controls.show(rect: selection.rect, screen: selection.screen)
        self.controls = controls
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.cancel() }
                return nil
            }
            return event
        }
        if AXIsProcessTrusted() {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
            }
            startAutomatic()
        } else {
            controls.state.status = "手动向下滚动约半屏，再点击「添加当前屏」；可随时完成"
            onStatus?("滚动截图已开始：手动滚动并添加画面，或开启辅助功能使用自动滚动。")
        }
    }

    private func toggleAutomatic() {
        guard let controls else { return }
        if controls.state.automatic {
            stopAutomatic(status: "已暂停。可手动滚动约半屏，然后添加当前屏")
        } else if AXIsProcessTrusted() {
            controls.state.accessibilityGranted = true
            startAutomatic()
        } else {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            if AXIsProcessTrustedWithOptions(options) {
                controls.state.accessibilityGranted = true
                startAutomatic()
            } else {
                controls.state.status = "在系统设置中允许辅助功能，回来点击自动滚动；也可继续手动添加"
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func startAutomatic() {
        guard let controls, let selection = scrollSelection, !controls.state.automatic else { return }
        controls.state.automatic = true
        controls.state.status = "正在自动向下滚动… 到底部后会自动暂停"
        // Returning from the Accessibility settings pane must bring the original
        // scroll surface back before synthetic wheel events are sent.
        if let pid = scrollTargetPID {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        }
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
            }
        }
        if originalMousePosition == nil { originalMousePosition = CGEvent(source: nil)?.location }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? selection.screen.frame.height
        let point = CGPoint(x: selection.rect.midX, y: primaryHeight - selection.rect.midY)
        CGWarpMouseCursorPosition(point)
        let id = sessionID
        automaticTask = Task { [weak self] in
            var unchangedCount = 0
            do {
                try await Task.sleep(for: .milliseconds(500))
                while let self, self.sessionID == id, self.controls?.state.automatic == true, !Task.isCancelled {
                    let amount = Int32(max(40, min(selection.rect.height * 0.48, 700)))
                    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -amount, wheel2: 0, wheel3: 0)
                    event?.location = point
                    event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    event?.post(tap: .cghidEventTap)
                    try await Task.sleep(for: .milliseconds(680))
                    guard self.sessionID == id, !Task.isCancelled else { return }
                    let result = await self.addScrollFrame(automatic: true)
                    if result == .unchanged { unchangedCount += 1 } else { unchangedCount = 0 }
                    if unchangedCount >= 2 {
                        self.stopAutomatic(status: "页面已停止滚动。点击「完成」进入标注")
                        return
                    }
                    try await Task.sleep(for: .milliseconds(220))
                }
            } catch { /* Intentional pause/cancellation. */ }
        }
    }

    @discardableResult
    private func addScrollFrame(automatic: Bool) async -> ImageStitcher.AppendResult? {
        guard let selection = scrollSelection, let content = scrollContent,
              let stitcher, let controls, !frameCaptureInProgress else { return nil }
        frameCaptureInProgress = true
        controls.state.capturing = true
        let id = sessionID
        defer {
            frameCaptureInProgress = false
            controls.state.capturing = false
        }
        do {
            let image = try await captureImage(content: content, screen: selection.screen, rect: selection.rect)
            guard sessionID == id else { return nil }
            let result = stitcher.append(image)
            switch result {
            case .appended(_, let height):
                controls.state.frames = stitcher.frameCount
                controls.state.height = height
                controls.state.status = automatic ? "已拼接 \(stitcher.frameCount) 屏，正在继续滚动…" : "已添加。继续向下滚动约半屏，或点击完成"
            case .unchanged:
                controls.state.status = automatic ? "正在确认页面是否已到底…" : "画面未变化，请先向下滚动约半屏再添加"
            case .noOverlap:
                stopAutomatic(status: "未找到重叠区域：请向上回滚一点，再点击「添加当前屏」")
            case .heightLimit:
                stopAutomatic(status: "已达到 \(stitcher.maximumHeight) 像素上限，点击「完成」保存当前长图")
            }
            return result
        } catch {
            guard sessionID == id else { return nil }
            stopAutomatic(status: "捕获失败，请重试添加；已拼接的画面仍保留")
            return nil
        }
    }

    private func stopAutomatic(status: String) {
        automaticTask?.cancel()
        automaticTask = nil
        controls?.state.automatic = false
        controls?.state.status = status
    }

    private func finishScrolling() {
        guard !frameCaptureInProgress else { return }
        guard let image = stitcher?.makeImage() else {
            stopAutomatic(status: "系统内存不足，无法合成长图。请取消并缩小截图区域后重试")
            return
        }
        finish(image: image, mode: .scroll)
    }

    private func finish(image: CGImage, mode: CaptureMode) {
        cleanUp()
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        onCapture?(result, mode)
    }

    private func fail(_ message: String) {
        cleanUp()
        onError?(message)
    }

    private func cleanUp() {
        sessionID = nil
        operation?.cancel()
        operation = nil
        automaticTask?.cancel()
        automaticTask = nil
        selectionOverlay?.cancel()
        selectionOverlay = nil
        controls?.close()
        controls = nil
        scrollSelection = nil
        scrollContent = nil
        scrollTargetPID = nil
        stitcher = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        escapeMonitor = nil
        localKeyMonitor = nil
        if let originalMousePosition { CGWarpMouseCursorPosition(originalMousePosition) }
        originalMousePosition = nil
        hiddenWindows.forEach { $0.orderFront(nil) }
        hiddenWindows.removeAll()
        isBusy = false
    }
}

private enum CaptureFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
