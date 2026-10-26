import XCTest
@testable import LumaShot

final class CaptureWindowLifecycleTests: XCTestCase {
    @MainActor func testSuccessfulCaptureHidesMainWindowRestoredByAnotherCaptureOwner() {
        let main = FakeCaptureWindow(isVisible: true)
        let editor = FakeCaptureWindow(isVisible: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        lifecycle.hideForCapture(editorWindows: [editor])
        XCTAssertFalse(main.isVisible)
        XCTAssertFalse(editor.isVisible)

        // CaptureService owns a separate restoration list and may reveal this
        // window before reporting success to AppModel.
        main.orderFront(nil)
        lifecycle.restoreAfterCapture(includingMainWindow: false)

        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(editor.isVisible)
    }

    @MainActor func testSuccessfulCaptureHidesMainWindowOpenedAfterTheCaptureSnapshot() {
        let main = FakeCaptureWindow(isVisible: false)
        let editor = FakeCaptureWindow(isVisible: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        lifecycle.hideForCapture(editorWindows: [editor])
        // This main window was absent from the original restoration list.
        main.makeKeyAndOrderFront(nil)
        lifecycle.restoreAfterCapture(includingMainWindow: false)

        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(editor.isVisible)
    }

    @MainActor func testClosingRestoredEditorDoesNotRevealMainOrRestoreTheEditorAgain() {
        let main = FakeCaptureWindow(isVisible: true)
        let editor = FakeCaptureWindow(isVisible: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        lifecycle.hideForCapture(editorWindows: [editor])
        lifecycle.restoreAfterCapture(includingMainWindow: false)
        XCTAssertTrue(editor.isVisible)

        editor.close()
        XCTAssertFalse(main.isVisible)
        lifecycle.restoreAfterCapture()

        XCTAssertFalse(main.isVisible)
        XCTAssertFalse(editor.isVisible)
        XCTAssertEqual(editor.orderFrontCount, 1)
    }

    @MainActor func testCancelledCaptureRestoresOnlyPreviouslyVisibleWindows() {
        let main = FakeCaptureWindow(isVisible: true)
        let visibleEditor = FakeCaptureWindow(isVisible: true)
        let closedEditor = FakeCaptureWindow(isVisible: false)
        let minimizedEditor = FakeCaptureWindow(isVisible: false, isMiniaturized: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        lifecycle.hideForCapture(editorWindows: [visibleEditor, closedEditor, minimizedEditor])
        lifecycle.restoreAfterCapture()

        XCTAssertTrue(main.isVisible)
        XCTAssertTrue(visibleEditor.isVisible)
        XCTAssertFalse(closedEditor.isVisible)
        XCTAssertFalse(minimizedEditor.isVisible)
        XCTAssertTrue(minimizedEditor.isMiniaturized)
    }

    @MainActor func testReopenFocusesTheLatestVisibleEditorWithoutOpeningMain() {
        let main = FakeCaptureWindow(isVisible: false)
        let earlierEditor = FakeCaptureWindow(isVisible: true)
        let latestEditor = FakeCaptureWindow(isVisible: true)
        let closedEditor = FakeCaptureWindow(isVisible: false)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        let handled = lifecycle.handleReopen(
            captureInProgress: false,
            hasVisibleWindows: true,
            editorWindows: [earlierEditor, latestEditor, closedEditor]
        )

        XCTAssertTrue(handled)
        XCTAssertFalse(main.isVisible)
        XCTAssertEqual(latestEditor.makeKeyCount, 1)
        XCTAssertEqual(earlierEditor.makeKeyCount, 0)
        XCTAssertFalse(closedEditor.isVisible)
    }

    @MainActor func testReopenRestoresAMinimizedEditorBeforeFocusingIt() {
        let main = FakeCaptureWindow(isVisible: false)
        let editor = FakeCaptureWindow(isVisible: false, isMiniaturized: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        let handled = lifecycle.handleReopen(
            captureInProgress: false,
            hasVisibleWindows: true,
            editorWindows: [editor]
        )

        XCTAssertTrue(handled)
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(editor.isVisible)
        XCTAssertFalse(editor.isMiniaturized)
        XCTAssertEqual(editor.deminiaturizeCount, 1)
        XCTAssertEqual(editor.makeKeyCount, 1)
        XCTAssertFalse(editor.wasFocusedWhileMiniaturized)
    }

    @MainActor func testDockReopenRestoresMinimizedMainWhenThereAreNoOpenEditors() {
        let main = FakeCaptureWindow(isVisible: false, isMiniaturized: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        // AppKit counts minimized windows as visible for this delegate flag.
        let handled = lifecycle.handleReopen(
            captureInProgress: false,
            hasVisibleWindows: true,
            editorWindows: []
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(main.isVisible)
        XCTAssertFalse(main.isMiniaturized)
        XCTAssertEqual(main.deminiaturizeCount, 1)
        XCTAssertEqual(main.makeKeyCount, 1)
        XCTAssertFalse(main.wasFocusedWhileMiniaturized)
    }

    @MainActor func testReopenDuringCaptureDoesNotRevealMainOrAnEditor() {
        for hasVisibleWindows in [false, true] {
            let main = FakeCaptureWindow(isVisible: false)
            let editor = FakeCaptureWindow(isVisible: false, isMiniaturized: true)
            let lifecycle = CaptureWindowLifecycle()
            lifecycle.mainWindow = main

            let handled = lifecycle.handleReopen(
                captureInProgress: true,
                hasVisibleWindows: hasVisibleWindows,
                editorWindows: [editor]
            )

            XCTAssertFalse(handled)
            XCTAssertFalse(main.isVisible)
            XCTAssertFalse(editor.isVisible)
            XCTAssertTrue(editor.isMiniaturized)
            XCTAssertEqual(editor.makeKeyCount, 0)
            XCTAssertEqual(editor.deminiaturizeCount, 0)
        }
    }

    @MainActor func testReopenWithoutOpenEditorsShowsMainAndDoesNotResurrectClosedEditors() {
        let main = FakeCaptureWindow(isVisible: false)
        let closedEditor = FakeCaptureWindow(isVisible: false)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        let handled = lifecycle.handleReopen(
            captureInProgress: false,
            hasVisibleWindows: false,
            editorWindows: [closedEditor]
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(main.isVisible)
        XCTAssertFalse(closedEditor.isVisible)
        XCTAssertEqual(closedEditor.makeKeyCount, 0)
    }

    @MainActor func testReopenWithAnotherVisibleWindowDoesNotCreateADashboardBehindIt() {
        let main = FakeCaptureWindow(isVisible: false)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        let handled = lifecycle.handleReopen(
            captureInProgress: false,
            hasVisibleWindows: true,
            editorWindows: []
        )

        XCTAssertFalse(handled)
        XCTAssertFalse(main.isVisible)
    }

    @MainActor func testExplicitShowMainWindowStillWorksAfterSuccessfulCapture() {
        let main = FakeCaptureWindow(isVisible: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main
        lifecycle.hideForCapture(editorWindows: [])
        lifecycle.restoreAfterCapture(includingMainWindow: false)
        XCTAssertFalse(main.isVisible)

        lifecycle.showMainWindow()

        XCTAssertTrue(main.isVisible)
        XCTAssertEqual(main.makeKeyCount, 1)
    }

    @MainActor func testExplicitShowMainWindowRestoresMinimizedMain() {
        let main = FakeCaptureWindow(isVisible: false, isMiniaturized: true)
        let lifecycle = CaptureWindowLifecycle()
        lifecycle.mainWindow = main

        lifecycle.showMainWindow()

        XCTAssertTrue(main.isVisible)
        XCTAssertFalse(main.isMiniaturized)
        XCTAssertEqual(main.deminiaturizeCount, 1)
        XCTAssertEqual(main.makeKeyCount, 1)
        XCTAssertFalse(main.wasFocusedWhileMiniaturized)
    }
}

@MainActor
private final class FakeCaptureWindow: CaptureWindow {
    var isVisible: Bool
    var isMiniaturized: Bool
    private(set) var orderFrontCount = 0
    private(set) var makeKeyCount = 0
    private(set) var deminiaturizeCount = 0
    private(set) var wasFocusedWhileMiniaturized = false

    init(isVisible: Bool, isMiniaturized: Bool = false) {
        self.isVisible = isVisible
        self.isMiniaturized = isMiniaturized
    }

    func orderOut(_ sender: Any?) {
        isVisible = false
    }

    func orderFront(_ sender: Any?) {
        orderFrontCount += 1
        isVisible = true
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyCount += 1
        wasFocusedWhileMiniaturized = wasFocusedWhileMiniaturized || isMiniaturized
        isVisible = true
    }

    func deminiaturize(_ sender: Any?) {
        deminiaturizeCount += 1
        isMiniaturized = false
        isVisible = true
    }

    func close() {
        isVisible = false
        isMiniaturized = false
    }
}
