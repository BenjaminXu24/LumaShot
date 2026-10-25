import Foundation

/// Serializes scrolling and frame collection. Pause/Finish change the next action;
/// only Cancel may interrupt a gesture or discard an uncollected frame.
@MainActor
final class ScrollCaptureDriver {
    enum Delay {
        case preparation, settling, interval

        var duration: Duration {
            switch self {
            case .preparation: return .milliseconds(500)
            case .settling: return .milliseconds(680)
            case .interval: return .milliseconds(220)
            }
        }
    }

    private enum Intent { case paused, automatic, finishing, cancelled }
    private var intent = Intent.paused
    private var worker: Task<Void, Never>?
    private var needsPreparation = false
    private var manualFrameRequested = false
    private(set) var isCollectingFrame = false
    var isAutomatic: Bool { intent == .automatic }
    var isFinishing: Bool { intent == .finishing }

    private let prepare: () -> Void
    private let scroll: () async throws -> Bool
    private let capture: () async -> ImageStitcher.AppendResult?
    private let onAutomaticChange: (Bool) -> Void
    private let onCaptureActivityChange: (Bool) -> Void
    private let onFinish: () -> Void
    private let onEnd: () -> Void
    private let onError: (Error) -> Void
    private let wait: (Delay) async throws -> Void

    init(prepare: @escaping () -> Void,
         scroll: @escaping () async throws -> Bool,
         capture: @escaping () async -> ImageStitcher.AppendResult?,
         onAutomaticChange: @escaping (Bool) -> Void,
         onCaptureActivityChange: @escaping (Bool) -> Void,
         onFinish: @escaping () -> Void,
         onEnd: @escaping () -> Void,
         onError: @escaping (Error) -> Void,
         wait: @escaping (Delay) async throws -> Void = { try await Task.sleep(for: $0.duration) }) {
        self.prepare = prepare
        self.scroll = scroll
        self.capture = capture
        self.onAutomaticChange = onAutomaticChange
        self.onCaptureActivityChange = onCaptureActivityChange
        self.onFinish = onFinish
        self.onEnd = onEnd
        self.onError = onError
        self.wait = wait
    }

    func resume() {
        guard intent == .paused else { return }
        intent = .automatic
        needsPreparation = true
        onAutomaticChange(true)
        startWorkerIfNeeded()
    }

    func pause() {
        guard intent == .automatic else { return }
        intent = .paused
        onAutomaticChange(false)
    }

    func addCurrentFrame() {
        guard intent == .paused, !isCollectingFrame else { return }
        manualFrameRequested = true
        startWorkerIfNeeded()
    }

    func finish() {
        guard intent != .cancelled, intent != .finishing else { return }
        intent = .finishing
        onAutomaticChange(false)
        startWorkerIfNeeded()
    }

    func cancel() {
        intent = .cancelled
        worker?.cancel()
        worker = nil
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
    }

    private func setCollectingFrame(_ collecting: Bool) {
        guard isCollectingFrame != collecting else { return }
        isCollectingFrame = collecting
        onCaptureActivityChange(collecting)
    }

    private func run() async {
        defer {
            worker = nil
            if intent != .cancelled { setCollectingFrame(false) }
        }
        var unchangedCount = 0
        do {
            while intent != .cancelled, !Task.isCancelled {
                if manualFrameRequested {
                    manualFrameRequested = false
                    setCollectingFrame(true)
                    _ = await capture()
                    guard intent != .cancelled, !Task.isCancelled else { return }
                    setCollectingFrame(false)
                }
                if intent == .finishing {
                    // Allow retry if bitmap allocation fails in the callback.
                    intent = .paused
                    onFinish()
                    return
                }
                guard intent == .automatic else { return }
                if needsPreparation {
                    needsPreparation = false
                    unchangedCount = 0
                    prepare()
                    try await wait(.preparation)
                    continue
                }
                setCollectingFrame(true)
                guard try await scroll() else {
                    setCollectingFrame(false)
                    pause()
                    continue
                }
                // Always collect this gesture's frame, even when Pause, Resume,
                // or Finish arrives while scrolling, settling, or capturing.
                try await wait(.settling)
                guard intent != .cancelled, !Task.isCancelled else { return }
                let result = await capture()
                guard intent != .cancelled, !Task.isCancelled else { return }
                setCollectingFrame(false)
                if result == .unchanged { unchangedCount += 1 } else { unchangedCount = 0 }
                if unchangedCount >= 2, intent == .automatic {
                    pause()
                    onEnd()
                }
                if intent == .automatic { try await wait(.interval) }
            }
        } catch {
            if intent != .cancelled {
                pause()
                onError(error)
            }
        }
    }
}
