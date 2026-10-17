import AppKit
import SwiftUI
import ServiceManagement
import ApplicationServices

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection = .capture
    @Published var toast: String?
    @Published var error: String?
    @Published var status = "准备好捕捉灵感"
    @Published var screenPermission = false
    @Published var accessibilityPermission = false
    @Published var search = ""
    @Published var captureInProgress = false
    @Published var shortcutIssues: [String] = []
    @Published var autoCopy = UserDefaults.standard.bool(forKey: "autoCopy") {
        didSet { UserDefaults.standard.set(autoCopy, forKey: "autoCopy") }
    }
    @Published var playSound = UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(playSound, forKey: "playSound") }
    }
    @Published var captureDelay = UserDefaults.standard.integer(forKey: "captureDelay") {
        didSet { UserDefaults.standard.set(captureDelay, forKey: "captureDelay") }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    let store = CaptureStore()
    let captureService = CaptureService()
    var mainWindow: NSWindow?
    private var editors: [EditorWindowController] = []
    private var hotkeys: GlobalHotKeyManager?
    private var toastTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var statusTimer: Timer?
    private var hiddenForCapture: [NSWindow] = []

    func start() {
        refreshPermissions()
        captureService.onCapture = { [weak self] image, mode in
            guard let self else { return }
            self.captureInProgress = false
            self.restoreCaptureWindows()
            self.status = "截图完成 · \(image.pixelSizeDescription)"
            if self.store.add(image: image, mode: mode) == nil {
                self.showToast("截图已打开，但历史记录保存失败，请检查磁盘空间")
            }
            if self.playSound { NSSound(named: "Tink")?.play() }
            if self.autoCopy { _ = ExportService.copy(image) }
            self.openEditor(image)
        }
        captureService.onStatus = { [weak self] message in
            self?.status = message
            if !((self?.captureService.isBusy) ?? true) {
                self?.captureInProgress = false
                self?.restoreCaptureWindows()
                if !(self?.mainWindow?.isVisible ?? true) { self?.showMainWindow() }
            }
        }
        captureService.onError = { [weak self] message in
            self?.captureInProgress = false
            self?.restoreCaptureWindows()
            self?.showMainWindow()
            self?.refreshPermissions()
            self?.error = message
        }
        hotkeys = GlobalHotKeyManager { [weak self] mode in self?.capture(mode) }
        shortcutIssues = hotkeys?.registerDefaults() ?? []
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func capture(_ mode: CaptureMode) {
        guard !captureInProgress, !captureService.isBusy else { return }
        captureInProgress = true
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.status = mode == .scroll ? "准备选择滚动区域" : "准备\(mode.title)"
            self.hiddenForCapture = ([self.mainWindow] + self.editors.map(\.window)).compactMap { $0 }.filter(\.isVisible)
            self.hiddenForCapture.forEach { $0.orderOut(nil) }
            let delay = UInt64(max(0, self.captureDelay)) * 1_000_000_000 + 250_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { self.captureInProgress = false; return }
            self.captureService.capture(mode)
        }
    }

    func cancelCapture() {
        captureTask?.cancel()
        captureService.cancel()
        captureInProgress = false
        restoreCaptureWindows()
        showMainWindow()
    }

    private func restoreCaptureWindows() {
        hiddenForCapture.forEach { $0.orderFront(nil) }
        hiddenForCapture.removeAll()
    }

    func openEditor(_ image: NSImage) {
        editors.removeAll { $0.window?.isVisible == false && $0.window?.isMiniaturized == false }
        let controller = EditorWindowController(image: image, onCopy: { [weak self] image in
            if ExportService.copy(image) { self?.showToast("已复制到剪贴板，随处粘贴吧") }
            else { self?.error = "复制失败，请重试。" }
        }, onSave: { [weak self] image in
            if let url = ExportService.save(image) { self?.showToast("已保存到 \(url.lastPathComponent)") }
        })
        editors.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func showMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func importImage() {
        let panel = NSOpenPanel()
        panel.title = "打开图片并标注"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        openEditor(image)
    }

    func refreshPermissions() {
        screenPermission = CaptureService.hasScreenPermission
        accessibilityPermission = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestScreenPermission() {
        if !captureService.requestScreenPermission() { openPrivacy("Privacy_ScreenCapture") }
        refreshPermissions()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openPrivacy("Privacy_Accessibility") }
        refreshPermissions()
    }

    func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshPermissions()
        } catch { self.error = "无法更新登录启动设置：\(error.localizedDescription)"; refreshPermissions() }
    }

    func revealHistory() { NSWorkspace.shared.open(store.directory) }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
