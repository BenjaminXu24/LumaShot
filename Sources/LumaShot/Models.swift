import AppKit
import SwiftUI

enum AppVersion {
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2"
}

enum CaptureMode: String, CaseIterable, Codable, Identifiable {
    case region, window, fullscreen, scroll

    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return "区域截图"
        case .window: return "窗口截图"
        case .fullscreen: return "全屏截图"
        case .scroll: return "滚动长截图"
        }
    }
    var subtitle: String {
        switch self {
        case .region: return "自由框选，精准捕捉"
        case .window: return "完整窗口，干净利落"
        case .fullscreen: return "整个屏幕，一览无余"
        case .scroll: return "向下滚动，自动拼接"
        }
    }
    var symbol: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .fullscreen: return "display"
        case .scroll: return "arrow.down.square"
        }
    }
    var keyNumber: String {
        switch self { case .region: return "1"; case .window: return "2"; case .fullscreen: return "3"; case .scroll: return "4" }
    }
    var shortcut: String { "⌃ ⇧ " + keyNumber }
}

enum AppSection: String, CaseIterable, Identifiable {
    case capture, history, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .capture: return "开始截图"; case .history: return "截图历史"; case .settings: return "偏好设置" }
    }
    var symbol: String {
        switch self { case .capture: return "viewfinder"; case .history: return "square.stack.3d.up"; case .settings: return "slider.horizontal.3" }
    }
}

enum Palette {
    static let accent = Color(red: 0.46, green: 0.36, blue: 0.91)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.22)
    static let muted = Color(red: 0.51, green: 0.53, blue: 0.61)
    static let background = Color(red: 0.969, green: 0.973, blue: 0.985)
    static let border = Color(red: 0.90, green: 0.91, blue: 0.94)
}

extension NSImage {
    var pixelSizeDescription: String {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return "\(cg.width) × \(cg.height)"
    }
}
