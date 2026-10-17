import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: CaptureStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.border.opacity(0.7)).frame(width: 1)
            ZStack(alignment: .bottom) {
                Palette.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        switch model.section {
                        case .capture: captureContent
                        case .history: HistoryView(model: model, store: store)
                        case .settings: SettingsContent(model: model)
                        }
                    }
                    .padding(.horizontal, 38).padding(.top, 44).padding(.bottom, 28)
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
                }
                if let toast = model.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(Palette.ink, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
                        .padding(.bottom, 24).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background.ignoresSafeArea())
        .tint(Palette.accent)
        .font(.system(size: 13))
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .alert("操作提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
            Button("权限设置") { model.section = .settings; model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.accent.gradient).frame(width: 39, height: 39)
                    Image(systemName: "viewfinder").font(.system(size: 24, weight: .medium)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("拾光截图").font(.system(size: 17, weight: .bold))
                    Text("L U M A S H O T").font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 23).padding(.top, 54).padding(.bottom, 42)

            Text("工作空间").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted).padding(.leading, 27).padding(.bottom, 12)
            VStack(spacing: 7) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { model.section = section }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.symbol).font(.system(size: 16, weight: .medium)).frame(width: 21)
                            Text(section.title).font(.system(size: 13, weight: model.section == section ? .semibold : .medium))
                            Spacer()
                            if section == .history && !store.items.isEmpty {
                                Text("\(store.items.count)").font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(model.section == section ? Palette.accent.opacity(0.1) : Color.black.opacity(0.035), in: Capsule())
                            }
                        }
                        .foregroundStyle(model.section == section ? Palette.accent : Palette.muted)
                        .padding(.horizontal, 13).frame(height: 43)
                        .background(model.section == section ? Palette.accent.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 15)

            Spacer(minLength: 36)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 0.27, green: 0.7, blue: 0.51)).frame(width: 6, height: 6)
                    Text("随时待命，轻按即截").font(.system(size: 11, weight: .medium))
                }
                Text("应用关闭窗口后，仍可通过\n菜单栏或快捷键唤起。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                HStack(spacing: 4) { KeyCap(text: "⌃"); KeyCap(text: "⇧"); KeyCap(text: "1") }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border.opacity(0.75)))
            .padding(.horizontal, 18)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 11))
                Text("只在本地，安心记录").font(.system(size: 10))
            }.foregroundStyle(Palette.muted).padding(.leading, 25).padding(.top, 22).padding(.bottom, 23)
        }.frame(width: 207).background(Color(red: 0.976, green: 0.977, blue: 0.989))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.section == .capture ? "MAKE A LITTLE SPACE FOR INSPIRATION" : model.section == .history ? "YOUR MOMENTS, COLLECTED" : "MAKE IT YOURS")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.muted)
                Text(model.section == .capture ? "截下此刻，留住灵感。" : model.section == .history ? "每一张，都在这里。" : "让截图更顺手。")
                    .font(.system(size: 27, weight: .bold)).tracking(-0.7)
                Text(model.section == .capture ? "从捕捉到表达，几步就好。" : model.section == .history ? "重新打开、继续标注，或分享刚刚的发现。" : "按你的习惯，调整每一个小细节。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button(action: model.importImage) {
                Label("打开图片", systemImage: "plus").font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            }.buttonStyle(.plain).help("打开本地图片并标注 · ⌘O")
        }
    }

    private var captureContent: some View {
        Group {
            hero
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("选择一种捕捉方式").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("全局快捷键 · Control + Shift").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 12) {
                    ForEach(CaptureMode.allCases) { mode in
                        CaptureCard(mode: mode, disabled: model.captureInProgress) { model.capture(mode) }
                    }
                }
            }
            if !model.screenPermission {
                HStack(spacing: 11) {
                    Image(systemName: "hand.raised.circle").font(.system(size: 22)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("第一次见面，先开启屏幕录制权限").font(.system(size: 11, weight: .semibold))
                        Text("macOS 需要你的授权，才可以捕捉其他应用的画面。")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("去开启 →", action: model.requestScreenPermission).buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 11, weight: .semibold))
                }.padding(15).background(Palette.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("最近捕捉").font(.system(size: 14, weight: .semibold))
                    if !store.items.isEmpty { Text("\(store.items.count)").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    Spacer()
                    Button("查看全部  ↗") { model.section = .history }.font(.system(size: 11)).foregroundStyle(Palette.muted).buttonStyle(.plain)
                }
                if store.items.isEmpty {
                    HStack(spacing: 15) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26, weight: .light)).foregroundStyle(Palette.accent.opacity(0.6))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("第一张灵感，等你来捕捉").font(.system(size: 12, weight: .medium))
                            Text("截图会自动保存在这里，随时回来继续编辑。 ").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("体验标注") { model.openEditor(DemoArtwork.make()) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                    }.padding(23).frame(maxWidth: .infinity)
                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border.opacity(0.7)))
                } else {
                    HStack(alignment: .top, spacing: 13) {
                        ForEach(Array(store.items.prefix(3))) { item in
                            CaptureThumbnail(item: item, model: model, store: store)
                        }
                        if store.items.count < 3 { Spacer(minLength: 0) }
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(Palette.accent)
                Text(model.status).foregroundStyle(Palette.muted)
                Spacer()
                Text("为 macOS 用心设计").foregroundStyle(Palette.muted.opacity(0.65))
            }.font(.system(size: 10))
        }
    }

    private var hero: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Label("小工具，大灵感", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.8), in: Capsule())
                Text("好想法，\n值得被好好留下。")
                    .font(.system(size: 25, weight: .bold)).tracking(-0.8).lineSpacing(5).padding(.top, 15)
                Text("截图 · 标注 · 分享，一气呵成。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 11)
                Button { model.capture(.region) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "viewfinder").font(.system(size: 15, weight: .medium))
                        Text(model.captureInProgress ? "正在准备…" : "开始截图").font(.system(size: 12, weight: .semibold))
                        Text("⌃ ⇧ 1").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7)).padding(.leading, 13)
                    }.foregroundStyle(.white).padding(.horizontal, 17).frame(height: 40)
                        .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Palette.accent.opacity(0.24), radius: 9, y: 5)
                }.buttonStyle(LiftButtonStyle()).disabled(model.captureInProgress).padding(.top, 23)
            }.padding(.leading, 29).padding(.vertical, 21)
            Spacer(minLength: 10)
            HeroIllustration().frame(width: 337, height: 225).padding(.trailing, 17)
        }
        .frame(maxWidth: .infinity, minHeight: 245)
        .background(LinearGradient(colors: [Color(red: 0.928, green: 0.921, blue: 0.994), Color(red: 0.953, green: 0.957, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.accent.opacity(0.08)))
    }
}

struct KeyCap: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.muted).frame(minWidth: 19, minHeight: 19)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.border))
    }
}

struct CaptureCard: View {
    let mode: CaptureMode
    var disabled: Bool
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: mode.symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(Palette.accent)
                        .frame(width: 34, height: 34).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium)).foregroundStyle(hovered ? Palette.accent : Palette.muted.opacity(0.45))
                }
                Text(mode.title).font(.system(size: 13, weight: .semibold)).padding(.top, 12)
                Text(mode.subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 6).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) { KeyCap(text: "⌃"); KeyCap(text: "⇧"); KeyCap(text: mode.keyNumber) }.padding(.top, 12)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(hovered ? Palette.accent.opacity(0.55) : Palette.border.opacity(0.8)))
                .shadow(color: Palette.accent.opacity(hovered ? 0.08 : 0), radius: 12, y: 4)
                .offset(y: hovered ? -3 : 0)
        }.buttonStyle(.plain).disabled(disabled).onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.16), value: hovered)
    }
}

struct HeroIllustration: View {
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.35)).frame(width: 206).offset(x: 25, y: -2)
            RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.83, green: 0.81, blue: 0.96)).frame(width: 233, height: 155).rotationEffect(.degrees(-9)).offset(x: 9, y: -3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in Circle().fill(Palette.accent.opacity(0.2)).frame(width: 5, height: 5) }
                    Spacer()
                    RoundedRectangle(cornerRadius: 2).fill(Palette.border).frame(width: 45, height: 4)
                }.padding(12)
                Divider().opacity(0.3)
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [Color(red: 0.80, green: 0.82, blue: 0.98), Color(red: 0.95, green: 0.81, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Circle().fill(.white.opacity(0.7)).frame(width: 37).offset(x: 10, y: -12)
                        Image(systemName: "mountain.2.fill").font(.system(size: 56)).foregroundStyle(Palette.accent.opacity(0.25)).offset(x: -2, y: 18)
                    }.frame(width: 83, height: 88).clipped()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("A little inspiration.").font(.system(size: 10, weight: .semibold))
                        RoundedRectangle(cornerRadius: 3).fill(Palette.border).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3).fill(Palette.border).frame(width: 66, height: 5)
                        Text("让灵感，不止一瞬。").font(.system(size: 8)).foregroundStyle(Palette.muted).padding(.top, 6)
                    }.padding(.top, 8)
                }.padding(15)
            }.frame(width: 245, height: 162).background(.white, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white, lineWidth: 3))
                .shadow(color: Palette.accent.opacity(0.14), radius: 18, y: 12).rotationEffect(.degrees(4))
            RoundedRectangle(cornerRadius: 5).stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: 120, height: 108).rotationEffect(.degrees(4)).offset(x: -59, y: 9)
            Image(systemName: "cursorarrow").font(.system(size: 26, weight: .medium)).foregroundStyle(Palette.accent)
                .shadow(color: .white, radius: 1).offset(x: 10, y: 66)
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow").foregroundStyle(Palette.accent)
                Image(systemName: "pencil.tip")
                Image(systemName: "arrow.up.right")
                Image(systemName: "textformat")
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 1, green: 0.65, blue: 0.50)).frame(width: 13, height: 13)
            }.font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.horizontal, 17).padding(.vertical, 12)
                .background(.white, in: Capsule()).shadow(color: Palette.accent.opacity(0.13), radius: 12, y: 4).offset(x: 19, y: 91)
            Label("捕捉成功", systemImage: "checkmark.circle.fill").font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(red: 0.23, green: 0.57, blue: 0.44)).padding(.horizontal, 11).padding(.vertical, 8)
                .background(.white, in: Capsule()).shadow(color: Palette.accent.opacity(0.08), radius: 8, y: 4).offset(x: 98, y: -78)
        }.accessibilityHidden(true)
    }
}

struct LiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
