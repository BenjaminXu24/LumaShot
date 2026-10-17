import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController {
    let editorModel: AnnotationEditorModel
    init(image: NSImage, onCopy: @escaping (NSImage) -> Void, onSave: @escaping (NSImage) -> Void) {
        editorModel = AnnotationEditorModel(image: image, onCopy: onCopy, onSave: onSave)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1160, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "截图标注 — 拾光截图"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 1000, height: 720)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(srgbRed: 0.975, green: 0.975, blue: 0.99, alpha: 1)
        window.contentView = NSHostingView(rootView: AnnotationEditorView(model: editorModel))
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationEditorModel
    private let accent = Color(red: 0.49, green: 0.35, blue: 0.94)
    private let ink = Color(red: 0.17, green: 0.16, blue: 0.23)
    private let muted = Color(red: 0.58, green: 0.57, blue: 0.64)
    private let colors: [NSColor] = [
        NSColor(srgbRed: 0.49, green: 0.35, blue: 0.94, alpha: 1),
        NSColor(srgbRed: 0.98, green: 0.32, blue: 0.38, alpha: 1),
        NSColor(srgbRed: 1, green: 0.65, blue: 0.15, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.70, blue: 0.54, alpha: 1),
        NSColor(srgbRed: 0.22, green: 0.55, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.15, green: 0.16, blue: 0.21, alpha: 1)
    ]
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
            ZStack(alignment: .top) {
                EditorCanvas(model: model)
                toolPalette.padding(.top, 20).padding(.horizontal, 20)
                if let toast = model.toast {
                    VStack {
                        Spacer()
                        Label(toast, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(ink.opacity(0.92), in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
                            .padding(.bottom, 28)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            footer
        }
        .background(Color.white)
        .foregroundStyle(ink)
        .tint(accent)
        .preferredColorScheme(.light)
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.12))
                Image(systemName: "viewfinder").font(.system(size: 19, weight: .semibold)).foregroundStyle(accent)
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("截图标注").font(.system(size: 15, weight: .semibold))
                Text("LUMASHOT  /  拾光截图").font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.3).foregroundStyle(muted)
            }
            Text("\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(muted)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.black.opacity(0.035), in: Capsule())
                .padding(.leading, 6)
            Spacer(minLength: 12)
            iconButton("folder", help: "打开图片 · ⌘O", action: model.openImage)
                .keyboardShortcut("o", modifiers: .command)
            divider
            iconButton("arrow.uturn.backward", help: "撤销 · ⌘Z", action: model.undo)
                .disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
            iconButton("arrow.uturn.forward", help: "重做 · ⇧⌘Z", action: model.redo)
                .disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            divider
            Button(action: model.copyImage) {
                Label("复制", systemImage: "square.on.square")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 15).frame(height: 34)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).keyboardShortcut("c", modifiers: .command).help("复制到剪贴板 · ⌘C")
            Button(action: model.saveImage) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.to.line")
                    Text("保存图片")
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 34)
                .background(accent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).keyboardShortcut("s", modifiers: .command).help("保存到本地 · ⌘S")
        }
        .padding(.leading, 84).padding(.trailing, 22)
        .frame(height: 76)
        .background(Color.white)
    }
    private var toolPalette: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                ToolButton(tool: tool, isSelected: model.tool == tool, accent: accent) {
                    model.tool = tool
                    model.selectedID = nil
                }
                .keyboardShortcut(shortcut(for: tool), modifiers: [])
            }
            divider.padding(.horizontal, 7)
            HStack(spacing: 7) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Button { model.color = color } label: {
                        Circle().fill(Color(nsColor: color)).frame(width: 18, height: 18)
                            .overlay {
                                if model.color.isEqual(color) {
                                    Circle().strokeBorder(Color.white, lineWidth: 2).padding(3)
                                }
                            }
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                            .padding(2)
                    }
                    .buttonStyle(.plain).help("选择标注颜色")
                }
            }
            ColorPicker("自定颜色", selection: Binding(get: { Color(nsColor: model.color) },
                                                set: { model.color = NSColor($0) }), supportsOpacity: false)
                .labelsHidden().frame(width: 27).help("自定颜色")
            divider.padding(.horizontal, 7)
            Menu {
                let base = max(4, min(14, model.pixelSize.width / 200))
                Button("细线") { model.lineWidth = base * 0.55 }
                Button("标准") { model.lineWidth = base }
                Button("粗线") { model.lineWidth = base * 1.9 }
            } label: {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).frame(width: 19, height: min(6, max(2, model.lineWidth / 3)))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }.frame(width: 37, height: 34)
            }
            .menuStyle(.borderlessButton).fixedSize().help("线条粗细")
            divider.padding(.horizontal, 5)
            iconButton("trash", help: "清除全部标注，可撤销", action: model.clear)
                .disabled(model.annotations.isEmpty)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.black.opacity(0.065), lineWidth: 1))
        .shadow(color: Color(red: 0.20, green: 0.17, blue: 0.38).opacity(0.09), radius: 18, y: 7)
        .fixedSize(horizontal: true, vertical: false)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(accent.opacity(0.8)).frame(width: 5, height: 5)
            Text(model.tool.hint).font(.system(size: 11)).foregroundStyle(muted)
            Spacer()
            if !model.annotations.isEmpty {
                Text("\(model.annotations.count) 处标注").font(.system(size: 11)).foregroundStyle(muted)
                divider.padding(.horizontal, 8)
            }
            iconButton("minus", help: "缩小") { model.changeZoom(by: 1 / 1.25) }
            Menu {
                Button("适应窗口 · ⌘0") { model.zoom = nil }
                Button("实际大小 · ⌘1") { model.zoom = 1 }
                Divider()
                ForEach([25, 50, 75, 100, 150, 200, 400], id: \.self) { value in
                    Button("\(value)%") { model.zoom = CGFloat(value) / 100 }
                }
            } label: {
                Text(model.zoom == nil ? "适应 · \(Int((model.effectiveScale * 100).rounded()))%" : "\(Int((model.effectiveScale * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).frame(minWidth: 80)
            }.menuStyle(.borderlessButton).fixedSize()
            iconButton("plus", help: "放大") { model.changeZoom(by: 1.25) }
            iconButton("arrow.up.left.and.arrow.down.right", help: "适应窗口 · ⌘0") { model.zoom = nil }
                .keyboardShortcut("0", modifiers: .command)
            Button("") { model.zoom = 1 }.keyboardShortcut("1", modifiers: .command).hidden().frame(width: 0)
        }
        .padding(.horizontal, 22).frame(height: 45)
        .background(Color.white)
        .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1) }
    }
    private var divider: some View {
        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1, height: 21)
    }
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 29, height: 31).contentShape(Rectangle())
        }.buttonStyle(EditorIconButtonStyle()).help(help).accessibilityLabel(help)
    }
    private func shortcut(for tool: AnnotationTool) -> KeyEquivalent {
        switch tool {
        case .select: return "v"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .pen: return "p"
        case .text: return "t"
        case .number: return "n"
        case .mosaic: return "m"
        case .hand: return "h"
        }
    }
}

private struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tool.symbol).font(.system(size: 16, weight: .medium)).frame(height: 18)
                Text(tool.name).font(.system(size: 9, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? accent : Color(red: 0.42, green: 0.41, blue: 0.48))
            .frame(width: 43, height: 44)
            .background(isSelected ? accent.opacity(0.1) : hovered ? Color.black.opacity(0.035) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .help(tool.hint)
        .accessibilityLabel(tool.name)
    }
}

private struct EditorIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.40, green: 0.39, blue: 0.47).opacity(enabled ? 1 : 0.27))
            .background(configuration.isPressed ? Color.black.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
}
