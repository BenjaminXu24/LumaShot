import AppKit

@MainActor
protocol CaptureWindow: AnyObject {
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }
    func orderOut(_ sender: Any?)
    func orderFront(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
    func deminiaturize(_ sender: Any?)
}

extension NSWindow: CaptureWindow {}

/// Keeps capture restoration and application reopen events from leaving the
/// dashboard behind the editor. Window operations are injectable for tests.
@MainActor
final class CaptureWindowLifecycle {
    weak var mainWindow: (any CaptureWindow)?
    private var hiddenForCapture: [any CaptureWindow] = []

    func hideForCapture(editorWindows: [any CaptureWindow]) {
        let windows = [mainWindow].compactMap { $0 } + editorWindows
        hiddenForCapture = windows.filter(\.isVisible)
        hiddenForCapture.forEach { $0.orderOut(nil) }
    }

    func restoreAfterCapture(includingMainWindow: Bool = true) {
        if !includingMainWindow {
            // CaptureService also restores windows, and reopen may have shown
            // the dashboard since our snapshot. Hide its current state too.
            mainWindow?.orderOut(nil)
        }
        for window in hiddenForCapture where includingMainWindow || window !== mainWindow {
            window.orderFront(nil)
        }
        hiddenForCapture.removeAll()
    }

    @discardableResult
    func handleReopen(captureInProgress: Bool, hasVisibleWindows: Bool,
                      editorWindows: [any CaptureWindow]) -> Bool {
        guard !captureInProgress else { return false }
        if let editor = editorWindows.last(where: { $0.isVisible || $0.isMiniaturized }) {
            if editor.isMiniaturized { editor.deminiaturize(nil) }
            editor.makeKeyAndOrderFront(nil)
            return true
        }
        // AppKit counts minimized windows as visible for reopen events.
        guard mainWindow?.isMiniaturized == true || !hasVisibleWindows else { return false }
        showMainWindow()
        return mainWindow != nil
    }

    func showMainWindow() {
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}
