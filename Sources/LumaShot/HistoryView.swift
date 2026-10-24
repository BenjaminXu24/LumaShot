import AppKit
import SwiftUI

struct CaptureThumbnail: View {
    let item: CaptureItem
    @ObservedObject var model: AppModel
    @ObservedObject var store: CaptureStore
    var onRecognize: () -> Void
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { if let image = store.image(for: item) { model.openEditor(image) } } label: {
                ZStack {
                    Color(red: 0.94, green: 0.94, blue: 0.97)
                    if let image = store.thumbnail(for: item) {
                        Image(nsImage: image).resizable().scaledToFit().padding(10)
                    }
                    if hovered {
                        Color.black.opacity(0.12)
                        Label("继续标注", systemImage: "pencil.tip").font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 8).background(.white, in: Capsule())
                    }
                }.frame(height: 135).clipped()
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.mode.title).font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button(action: onRecognize) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 22, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("识别文字")
                    .accessibilityLabel("识别文字")
                    Menu {
                        Button("打开标注") { if let image = store.image(for: item) { model.openEditor(image) } }
                        Button("识别文字") { onRecognize() }
                        Button("复制到剪贴板") {
                            if let image = store.image(for: item), ExportService.copy(image) { model.showToast("已复制到剪贴板") }
                        }
                        Button("另存为…") { if let image = store.image(for: item) { _ = ExportService.save(image) } }
                        Divider()
                        Button("从历史删除", role: .destructive) { store.delete(item) }
                    } label: { Image(systemName: "ellipsis").frame(width: 15, height: 12) }.menuStyle(.borderlessButton).frame(width: 20)
                }
                HStack {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    Spacer()
                    Text("\(item.pixelWidth) × \(item.pixelHeight)")
                }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.padding(12)
        }.frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 11))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(hovered ? Palette.accent.opacity(0.4) : Palette.border.opacity(0.8)))
            .onHover { hovered = $0 }.animation(.easeOut(duration: 0.15), value: hovered)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: CaptureStore
    @StateObject private var ocrSession = OCRSession()
    @State private var filter: CaptureMode?
    @State private var clearConfirmation = false
    private var filtered: [CaptureItem] {
        store.items.filter { item in
            (filter == nil || item.mode == filter) && (model.search.isEmpty || item.mode.title.localizedCaseInsensitiveContains(model.search) || item.filename.localizedCaseInsensitiveContains(model.search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("搜索截图类型或文件名", text: $model.search).textFieldStyle(.plain)
                }.padding(10).frame(maxWidth: 290).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
                Spacer()
                Button(action: model.revealHistory) { Image(systemName: "folder").help("在访达中打开") }.buttonStyle(.plain)
                Button { clearConfirmation = true } label: { Image(systemName: "trash").help("清空历史") }.buttonStyle(.plain).disabled(store.items.isEmpty)
            }
            HStack(spacing: 8) {
                filterButton("全部", selected: filter == nil) { filter = nil }
                ForEach(CaptureMode.allCases) { mode in filterButton(mode.title, selected: filter == mode) { filter = mode } }
                Spacer()
                Text("\(filtered.count) 张截图").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if filtered.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Palette.accent.opacity(0.5))
                    Text(store.items.isEmpty ? "这里即将装满你的灵感" : "没有找到相关截图").font(.system(size: 15, weight: .medium))
                    Text(store.items.isEmpty ? "用 ⌃ ⇧ 1 开始你的第一张截图。" : "试试其他类型，或换个关键词。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if store.items.isEmpty { Button("开始截图") { model.capture(.region) }.buttonStyle(.borderedProminent).padding(.top, 5) }
                }.frame(maxWidth: .infinity).frame(height: 360)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 15)], spacing: 16) {
                    ForEach(filtered) { item in
                        CaptureThumbnail(item: item, model: model, store: store, onRecognize: { recognize(item) })
                    }
                }
            }
            Text("仅保存在这台 Mac · 最多保留最近 100 张原始截图 · 标注结果请复制或另存为")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .background(OCRSheetPresenter(session: ocrSession) { model.showToast($0) })
        .confirmationDialog("清空全部截图历史？", isPresented: $clearConfirmation) {
            Button("清空历史", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        } message: { Text("这会删除应用内保留的原始截图；已另存到其他位置的图片不会被删除。") }
    }

    private func recognize(_ item: CaptureItem) {
        guard let image = store.image(for: item), let cgImage = ImageEncoding.cgImage(from: image) else {
            model.showToast("无法读取这张截图")
            return
        }
        ocrSession.recognize(image: cgImage, region: nil, kind: "历史原图")
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.accent : Palette.muted)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? Palette.accent.opacity(0.08) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
}
