import AVKit

struct SeekInfo {
    let time: CMTime
    let toleranceBefore: CMTime
    let toleranceAfter: CMTime
}

/// Implements "smooth seeking" as described in QA1820.
/// - Note: [QA1820](https://developer.apple.com/library/content/qa/qa1820/_index.html)
class PlayerSeeker {

    private let player: AVPlayer

    /// True if the seeker is performing a seek.
    /// - Note: Seeks started on the receiver's player directly (`player.seek`) are not
    ///   included.
    var isSeeking: Bool {
        return currentSeek != nil
    }

    /// The overall time the player is seeking towards.
    var finalSeekTime: CMTime? {
        return (nextSeek ?? currentSeek)?.time
    }

    /// The seek currently in progress.
    private(set) var currentSeek: SeekInfo?

    /// The seek that starts when `currentSeek` finishes.
    private(set) var nextSeek: SeekInfo?

    init(player: AVPlayer) {
        self.player = player
    }

    func cancelPendingSeeks() {
        player.currentItem?.cancelPendingSeeks()
    }

    /// "Smoothly" seeks to the given time by letting pending seeks finish before new ones
    /// are started when invoked in succession (such as from a `UISlider`). When the
    /// current seek finishes, the latest of the enqueued ones is started.
    ///
    /// To start a seek immediately, cancel pending seeks explicitly.
    ///
    /// - Note: [QA1820](https://developer.apple.com/library/content/qa/qa1820/_index.html)
    func seek(to time: CMTime, toleranceBefore: CMTime = .zero, toleranceAfter: CMTime = .zero) {
        let info = SeekInfo(time: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
        seek(with: info)
    }

    func seek(with info: SeekInfo) {
        guard info.time != player.currentTime() else { return }

        nextSeek = info

        if !isSeeking {
            pause()
            startNextSeek()
        }
    }

    private func startNextSeek() {
        guard let next = nextSeek else { fatalError("No next seek to start") }

        currentSeek = next
        nextSeek = nil

        player.seek(with: next) { [weak self] finished in
            self?.didFinishCurrentSeek(wasCancelled: !finished)
        }
    }

    private func didFinishCurrentSeek(wasCancelled: Bool) {
        currentSeek = nil
        let continueSeeking = !wasCancelled && (nextSeek != nil)

        if continueSeeking {
            startNextSeek()
        } else {
            didFinishAllSeeks(wasCancelled: wasCancelled)
        }
    }

    private func didFinishAllSeeks(wasCancelled: Bool) {
        currentSeek = nil
        nextSeek = nil
    }

    /// Utility.
    /// Cancels pending seeks and starts a new seek to the final seek time with the given
    /// tolerance. This can be used in certain situations to finish seeking faster, e.g.
    /// by using higher tolerances than the pending seeks and/or by replacing two pending
    /// seeks (current and next) with a single final seek.
    func seekToFinalTime(withToleranceBefore toleranceBefore: CMTime = .zero, toleranceAfter: CMTime = .zero) {
        guard let finalSeekTime = finalSeekTime else { return }

        cancelPendingSeeks()

        let info = SeekInfo(time: finalSeekTime, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
        seek(with: info)
    }
}

extension AVPlayer {
    func seek(with info: SeekInfo, completionHandler: @escaping (Bool) -> ()) {
        seek(to: info.time,
             toleranceBefore: info.toleranceBefore,
             toleranceAfter: info.toleranceAfter,
             completionHandler: completionHandler)
    }
}
