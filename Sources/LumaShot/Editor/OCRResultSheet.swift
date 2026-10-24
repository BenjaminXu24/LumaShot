import SwiftUI

struct OCRSheetPresenter: View {
    @ObservedObject var session: OCRSession
    var onCopied: (String) -> Void

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .sheet(isPresented: Binding(
                get: { session.isPresented },
                set: { presented in if !presented { session.dismiss() } }
            )) {
                OCRResultSheet(session: session, onCopied: onCopied)
            }
    }
}

struct OCRResultSheet: View {
    @ObservedObject var session: OCRSession
    var onCopied: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private let accent = Color(red: 0.49, green: 0.35, blue: 0.94)
    private let ink = Color(red: 0.17, green: 0.16, blue: 0.23)
    private let muted = Color(red: 0.58, green: 0.57, blue: 0.64)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.12))
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("识别文字").font(.system(size: 16, weight: .semibold))
                    if let scope = session.phase.scope {
                        Text(scope)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 0)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("仅在这台 Mac 上识别，不会上传图片。")
                .font(.system(size: 11))
                .foregroundStyle(muted)
            HStack(spacing: 10) {
                Spacer()
                Button("关闭") { close() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 34)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                Button(action: copy) {
                    Text(copied ? "已复制" : "复制文字")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(accent.opacity(session.phase.canCopy ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(!session.phase.canCopy)
                .accessibilityLabel("复制文字")
            }
        }
        .padding(22)
        .frame(width: 520, height: 420)
        .foregroundStyle(ink)
        .background(Color.white)
        .preferredColorScheme(.light)
        .onChange(of: session.phase) { _, _ in copied = false }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle, .recognizing:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在本机识别…").font(.system(size: 13)).foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message, _):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 28, weight: .regular)).foregroundStyle(accent)
                Text(message).font(.system(size: 13)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result(let text, _):
            resultText(text)
        }
    }

    @ViewBuilder
    private func resultText(_ text: String) -> some View {
        if session.phase.canCopy {
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.06)))
        } else {
            Text("没有识别到文字")
                .font(.system(size: 14))
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy() {
        guard session.copyToPasteboard() else { return }
        copied = true
        onCopied("已复制文字")
    }

    private func close() {
        session.dismiss()
        dismiss()
    }
}
