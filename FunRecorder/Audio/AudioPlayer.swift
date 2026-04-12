import AVFoundation

@Observable
final class AudioPlayer {
    private(set) var isPlaying: Bool = false
    private(set) var playheadTime: Double = 0   // Seconds from start of full recording
    var isLooping: Bool = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var regionStart: AVAudioFramePosition = 0
    private var regionEnd: AVAudioFramePosition = 0
    private var playheadTimer: Timer?

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    func load(url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        audioFile = file
        regionStart = 0
        regionEnd = file.length
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
    }

    func play() {
        guard let file = audioFile, !isPlaying else { return }
        scheduleAndPlay(file: file, from: AVAudioFramePosition(playheadTime * file.processingFormat.sampleRate))
        isPlaying = true
        startPlayheadTimer()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopPlayheadTimer()
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        playheadTime = 0
        stopPlayheadTimer()
    }

    func seek(to time: Double) {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        playerNode.stop()
        isPlaying = false
        stopPlayheadTimer()
        playheadTime = max(Double(regionStart) / file.processingFormat.sampleRate,
                           min(Double(regionEnd) / file.processingFormat.sampleRate, time))
        if wasPlaying {
            scheduleAndPlay(file: file, from: AVAudioFramePosition(playheadTime * file.processingFormat.sampleRate))
            isPlaying = true
            startPlayheadTimer()
        }
    }

    func updateRegion(startSamples: Int, endSamples: Int) {
        regionStart = AVAudioFramePosition(startSamples)
        regionEnd = AVAudioFramePosition(endSamples)
        // Region changes take effect at next play/loop boundary
    }

    // MARK: - Private

    private func scheduleAndPlay(file: AVAudioFile, from startFrame: AVAudioFramePosition) {
        playerNode.stop()
        let clampedStart = max(regionStart, min(regionEnd - 1, startFrame))
        scheduleSegment(file: file, startFrame: clampedStart)
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
    }

    /// Schedules one segment; if looping, the completion handler pre-schedules the next.
    private func scheduleSegment(file: AVAudioFile, startFrame: AVAudioFramePosition) {
        let frameCount = AVAudioFrameCount(max(0, regionEnd - startFrame))
        guard frameCount > 0 else { return }

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataConsumed  // Fires while buffer still in hardware queue
        ) { [weak self] _ in
            guard let self, self.isLooping else {
                Task { @MainActor [weak self] in self?.handleNonLoopEnd() }
                return
            }
            // Pre-schedule the next loop iteration before current one ends (gapless)
            let loopFrameCount = AVAudioFrameCount(max(0, self.regionEnd - self.regionStart))
            if loopFrameCount > 0 {
                self.playerNode.scheduleSegment(
                    file, startingFrame: self.regionStart, frameCount: loopFrameCount, at: nil,
                    completionCallbackType: .dataConsumed
                ) { [weak self] _ in
                    self?.scheduleSegment(file: file, startFrame: self?.regionStart ?? 0)
                }
            }
        }
    }

    private func handleNonLoopEnd() {
        isPlaying = false
        playheadTime = Double(regionStart) / (audioFile?.processingFormat.sampleRate ?? 32000)
        stopPlayheadTimer()
    }

    private func startPlayheadTimer() {
        playheadTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePlayhead()
        }
    }

    private func stopPlayheadTimer() {
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    private func updatePlayhead() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let file = audioFile else { return }

        let sampleRate = file.processingFormat.sampleRate
        let currentFrame = regionStart + playerTime.sampleTime
        let loopLength = regionEnd - regionStart

        if isLooping && loopLength > 0 {
            let positionInLoop = (currentFrame - regionStart) % loopLength
            playheadTime = Double(regionStart + positionInLoop) / sampleRate
        } else {
            playheadTime = Double(min(currentFrame, regionEnd)) / sampleRate
        }
    }
}
