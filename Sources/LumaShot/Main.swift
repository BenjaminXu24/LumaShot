import AppKit
import SwiftUI

@main
struct LumaShotMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var previewEditor: EditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let content = DashboardView(model: model, store: model.store)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1170, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "拾光截图 · LumaShot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(red: 0.969, green: 0.973, blue: 0.985, alpha: 1)
        window.minSize = NSSize(width: 1060, height: 760)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("LumaShotMainWindow")
        self.window = window
        model.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > previewIndex + 1 {
            Task { await renderPreviews(to: CommandLine.arguments[previewIndex + 1]) }
        } else {
            model.start()
            installStatusItem()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.handleReopen(hasVisibleWindows: flag)
        // Our window routing handles this event; AppKit must not also reopen
        // the dashboard when only a capture panel or editor is present.
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let image = NSImage(contentsOf: url) { model.openEditor(image) }
        }
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(title: "拾光截图", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(item("关于拾光截图", action: #selector(about)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("偏好设置…", action: #selector(settings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("隐藏拾光截图", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        appMenu.addItem(item("退出拾光截图", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        appItem.submenu = appMenu; main.addItem(appItem)

        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); let file = NSMenu(title: "文件")
        file.addItem(item("打开图片…", action: #selector(openImage), key: "o"))
        file.addItem(item("保存标注图片…", action: #selector(AnnotationCanvasView.saveDocument(_:)), key: "s", target: nil))
        file.addItem(.separator())
        file.addItem(item("区域截图", action: #selector(region)))
        file.addItem(item("窗口截图", action: #selector(captureWindow)))
        file.addItem(item("全屏截图", action: #selector(fullscreen)))
        file.addItem(item("滚动长截图", action: #selector(scroll)))
        file.addItem(.separator())
        file.addItem(item("关闭窗口", action: #selector(NSWindow.performClose(_:)), key: "w", target: nil))
        fileItem.submenu = file; main.addItem(fileItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); let edit = NSMenu(title: "编辑")
        edit.addItem(item("撤销", action: #selector(AnnotationCanvasView.undo(_:)), key: "z", target: nil))
        let redo = item("重做", action: #selector(AnnotationCanvasView.redo(_:)), key: "z", target: nil); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("剪切", action: #selector(NSText.cut(_:)), key: "x", target: nil))
        edit.addItem(item("复制", action: #selector(NSText.copy(_:)), key: "c", target: nil))
        edit.addItem(item("粘贴", action: #selector(NSText.paste(_:)), key: "v", target: nil))
        edit.addItem(item("全选", action: #selector(NSText.selectAll(_:)), key: "a", target: nil))
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); let windows = NSMenu(title: "窗口")
        windows.addItem(item("显示主窗口", action: #selector(showMain)))
        windows.addItem(item("最小化", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", target: nil))
        windowItem.submenu = windows; main.addItem(windowItem); NSApp.windowsMenu = windows
        let helpItem = NSMenuItem(title: "帮助", action: nil, keyEquivalent: ""); let help = NSMenu(title: "帮助")
        help.addItem(item("体验标注", action: #selector(demo)))
        help.addItem(item("权限与快捷键", action: #selector(settings)))
        helpItem.submenu = help; main.addItem(helpItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        // First-responder edit/window actions need nil; app actions are implemented here.
        let appActions: [Selector] = [#selector(about), #selector(settings), #selector(openImage), #selector(region), #selector(captureWindow), #selector(fullscreen), #selector(scroll), #selector(showMain), #selector(demo)]
        item.target = target ?? (appActions.contains(action) ? self : nil)
        return item
    }

    private func installStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "拾光截图")
        let menu = NSMenu()
        menu.addItem(item("拾光截图 · LumaShot", action: #selector(showMain)))
        menu.addItem(.separator())
        menu.addItem(item("区域截图     ⌃⇧1", action: #selector(region)))
        menu.addItem(item("窗口截图     ⌃⇧2", action: #selector(captureWindow)))
        menu.addItem(item("全屏截图     ⌃⇧3", action: #selector(fullscreen)))
        menu.addItem(item("滚动长截图  ⌃⇧4", action: #selector(scroll)))
        menu.addItem(.separator())
        menu.addItem(item("显示主窗口", action: #selector(showMain)))
        menu.addItem(item("偏好设置…", action: #selector(settings)))
        menu.addItem(item("退出", action: #selector(NSApplication.terminate(_:)), target: NSApp))
        status.menu = menu; statusItem = status
    }

    @objc private func showMain() { model.showMainWindow() }
    @objc private func region() { model.capture(.region) }
    @objc private func captureWindow() { model.capture(.window) }
    @objc private func fullscreen() { model.capture(.fullscreen) }
    @objc private func scroll() { model.capture(.scroll) }
    @objc private func openImage() { model.importImage() }
    @objc private func settings() { model.section = .settings; model.showMainWindow() }
    @objc private func demo() { model.openEditor(DemoArtwork.make()) }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "拾光截图 LumaShot", .applicationVersion: AppVersion.current,
            .credits: NSAttributedString(string: "截下此刻，留住灵感。\n原生 macOS 截图、滚动拼接与轻量标注。\n开源许可：MIT · github.com/BenjaminXu24/LumaShot"),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © 2026 BenjaminXu24. MIT License."
        ])
    }

    private func renderPreviews(to path: String) async {
        do {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (section, filename) in [(AppSection.capture, "01-home.png"), (.history, "02-history.png"), (.settings, "03-settings.png")] {
                model.section = section
                try await Task.sleep(nanoseconds: 700_000_000)
                if let view = window?.contentView { try render(view, to: directory.appendingPathComponent(filename)) }
            }
            let editor = EditorWindowController(image: DemoArtwork.make(), onCopy: { _ in }, onSave: { _ in })
            editor.editorModel.commit(EditorAnnotation(tool: .rectangle, points: [CGPoint(x: 82, y: 273), CGPoint(x: 598, y: 448)], color: NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1), lineWidth: 5))
            editor.editorModel.commit(EditorAnnotation(tool: .arrow, points: [CGPoint(x: 625, y: 548), CGPoint(x: 826, y: 415)], color: NSColor(srgbRed: 0.98, green: 0.32, blue: 0.38, alpha: 1), lineWidth: 6))
            editor.editorModel.commit(EditorAnnotation(tool: .number, points: [CGPoint(x: 742, y: 210)], color: NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1), lineWidth: 5, number: 1, fontSize: 32))
            editor.editorModel.commit(EditorAnnotation(tool: .text, points: [CGPoint(x: 812, y: 178)], color: NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1), lineWidth: 5, text: "留住这一刻", fontSize: 30))
            previewEditor = editor; editor.showWindow(nil)
            try await Task.sleep(nanoseconds: 900_000_000)
            let copyTarget = NSApp.target(forAction: #selector(AnnotationCanvasView.copy(_:)), to: nil, from: nil)
            let undoTarget = NSApp.target(forAction: #selector(AnnotationCanvasView.undo(_:)), to: nil, from: nil)
            print("EDITOR_RESPONDER_COPY \(copyTarget is AnnotationCanvasView) UNDO \(undoTarget is AnnotationCanvasView)")
            if let view = editor.window?.contentView { try render(view, to: directory.appendingPathComponent("04-editor.png")) }
            print("PREVIEWS_OK \(path)")
        } catch { fputs("Preview failed: \(error)\n", stderr) }
        NSApp.terminate(nil)
    }

    private func render(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
