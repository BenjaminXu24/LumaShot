// Optional real ScreenCaptureKit smoke check. It never writes the captured pixels.
// Compile together with Models.swift and Capture/*.swift, then run from a process
// that already has Screen Recording approval. No permission prompt is requested.
import AppKit

@main
struct CaptureSmoke {
    @MainActor static func main() {
        guard CaptureService.hasScreenPermission else {
            print("CAPTURE_SMOKE_SKIPPED: Screen Recording approval is required")
            exit(77)
        }
        let application = NSApplication.shared
        let delegate = SmokeDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class SmokeDelegate: NSObject, NSApplicationDelegate {
    let service = CaptureService()
    func applicationDidFinishLaunching(_ notification: Notification) {
        service.onCapture = { image, mode in
            guard mode == .fullscreen,
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  cg.width > 0, cg.height > 0 else {
                fputs("CAPTURE_SMOKE_FAILED: Invalid bitmap\n", stderr); exit(2)
            }
            print("CAPTURE_SMOKE_OK: \(cg.width) × \(cg.height), pixels discarded")
            NSApp.terminate(nil)
        }
        service.onError = { error in fputs("CAPTURE_SMOKE_FAILED: \(error)\n", stderr); exit(2) }
        service.capture(.fullscreen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            fputs("CAPTURE_SMOKE_FAILED: Timed out\n", stderr); exit(3)
        }
    }
}
