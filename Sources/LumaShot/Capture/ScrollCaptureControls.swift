import AppKit
import SwiftUI

@MainActor
final class ScrollCaptureControls {
    final class State: ObservableObject {
        @Published var status = "正在准备首张画面…"
        @Published var automatic = false
        @Published var frames = 1
        @Published var height = 0
        @Published var capturing = false
        @Published var accessibilityGranted = false
        var onFinish: (() -> Void)?
        var onCancel: (() -> Void)?
        var onAdd: (() -> Void)?
        var onToggleAutomatic: (() -> Void)?
    }

    let state = State()
    private var panel: NSPanel?
    private var outline: NSPanel?
    private var panelHiddenForCapture = false

    func scrollPoint(in rect: CGRect) -> CGPoint? {
        ScrollInput.target(in: rect, avoiding: panel?.frame)
    }

    func focus() { panel?.makeKeyAndOrderFront(nil) }

    func allowsScrolling(at point: CGPoint, in rect: CGRect) -> Bool {
        ScrollInput.allowsScrolling(at: point, in: rect, avoiding: panel?.frame)
    }

    func hideForCapture(in rect: CGRect) {
        panelHiddenForCapture = panel?.frame.insetBy(dx: -24, dy: -24).intersects(rect) ?? false
        if panelHiddenForCapture { panel?.orderOut(nil) }
        outline?.orderOut(nil)
    }

    func restoreAfterCapture() {
        outline?.orderFrontRegardless()
        if panelHiddenForCapture { panel?.makeKeyAndOrderFront(nil) }
        panelHiddenForCapture = false
    }

    func show(rect: CGRect, screen: NSScreen) {
        let border = NSPanel(contentRect: rect.insetBy(dx: -2, dy: -2), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.isOpaque = false
        border.backgroundColor = .clear
        border.ignoresMouseEvents = true
        border.level = .statusBar
        border.hasShadow = false
        border.isReleasedWhenClosed = false
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.contentView = BorderView(frame: CGRect(origin: .zero, size: border.frame.size))
        border.orderFrontRegardless()
        outline = border

        let size = CGSize(width: 480, height: 154)
        let visible = screen.visibleFrame
        var y = rect.maxY + 12
        if y + size.height > visible.maxY { y = rect.minY - size.height - 12 }
        y = min(max(y, visible.minY + 12), visible.maxY - size.height - 12)
        let x = min(max(rect.midX - size.width / 2, visible.minX + 12), visible.maxX - size.width - 12)
        let controls = ControlsPanel(contentRect: CGRect(origin: CGPoint(x: x, y: y), size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controls.level = .statusBar
        controls.isOpaque = false
        controls.backgroundColor = .clear
        controls.hasShadow = true
        controls.isReleasedWhenClosed = false
        controls.isMovableByWindowBackground = true
        controls.title = "滚动截图"
        controls.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controls.contentView = NSHostingView(rootView: ControlView(state: state))
        controls.makeKeyAndOrderFront(nil)
        panel = controls
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        outline?.orderOut(nil)
        outline?.close()
        panel = nil
        outline = nil
    }

    private struct ControlView: View {
        @ObservedObject var state: State

        var body: some View {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .foregroundStyle(Color(red: 0.68, green: 0.66, blue: 1))
                    Text("滚动截图").font(.system(size: 13, weight: .semibold))
                    Text("\(state.frames) 屏 · \(state.height) px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                    Spacer()
                    Button { state.onCancel?() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                    }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.55)).help("取消截图")
                }
                Text(state.status)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2).frame(height: 30, alignment: .topLeading)
                HStack(spacing: 8) {
                    Button { state.onToggleAutomatic?() } label: {
                        Label(state.automatic ? "暂停滚动" : (state.accessibilityGranted ? "自动滚动" : "开启辅助功能"),
                              systemImage: state.automatic ? "pause.fill" : "arrow.down")
                            .font(.system(size: 11, weight: .medium)).frame(height: 23)
                    }.buttonStyle(.bordered).tint(.white.opacity(0.1))
                    if !state.automatic {
                        Button { state.onAdd?() } label: {
                            Label("添加当前屏", systemImage: "plus").font(.system(size: 11, weight: .medium)).frame(height: 23)
                        }.buttonStyle(.bordered).disabled(state.capturing)
                    }
                    Spacer(minLength: 0)
                    Button { state.onFinish?() } label: {
                        Label("完成（\(state.frames) 屏）", systemImage: "checkmark").font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8).frame(height: 23)
                    }.buttonStyle(.borderedProminent).tint(Color(red: 0.52, green: 0.45, blue: 0.96))
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(Color(red: 0.09, green: 0.09, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.13), lineWidth: 1))
            .preferredColorScheme(.dark)
        }
    }

    private final class BorderView: NSView {
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(calibratedRed: 0.66, green: 0.62, blue: 1, alpha: 0.95).setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            path.lineWidth = 2
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.stroke()
        }
    }

    private final class ControlsPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}
