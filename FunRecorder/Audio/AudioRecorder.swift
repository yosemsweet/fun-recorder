import AVFoundation
import Accelerate

enum AudioRecorderError: Error {
    case permissionDenied
    case fileCreationFailed
}

@Observable
final class AudioRecorder {
    enum State { case idle, recording, finished }

    private(set) var state: State = .idle
    private(set) var levels: [Float] = []         // Amplitude values for live waveform (max 300)
    private(set) var recordedURL: URL?
    private(set) var recordedDuration: TimeInterval = 0

    static let sampleRate: Double = 32000
    static let maxDuration: TimeInterval = 30
    private static let maxFrames = AVAudioFrameCount(sampleRate * maxDuration)

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordedFrameCount: AVAudioFrameCount = 0
    private var autoStopTimer: Timer?
    private var converter: AVAudioConverter?
    private var resampleBuffer: AVAudioPCMBuffer?   // Pre-allocated; avoids per-callback heap allocation

    // Float32 required by AVAudioEngine tap; AVAudioFile converts to Int16 PCM on write
    private static let tapFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
    }

    /// Returns the URL of the file being written to.
    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = clipsDirectory().appendingPathComponent("\(UUID().uuidString).wav")
        let writeSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        audioFile = try AVAudioFile(forWriting: url, settings: writeSettings)
        recordedFrameCount = 0
        levels = []
        recordedURL = url

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        if hwFormat.sampleRate != Self.sampleRate {
            converter = AVAudioConverter(from: hwFormat, to: Self.tapFormat)
            let maxOutputFrames = AVAudioFrameCount(Double(4096) * Self.sampleRate / hwFormat.sampleRate + 4)
            resampleBuffer = AVAudioPCMBuffer(pcmFormat: Self.tapFormat, frameCapacity: maxOutputFrames)
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }
        try engine.start()
        state = .recording

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        return url
    }

    func stop() {
        guard state == .recording else { return }
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recordedDuration = TimeInterval(recordedFrameCount) / Self.sampleRate
        audioFile = nil
        converter = nil
        resampleBuffer = nil
        state = .finished
    }

    func reset() {
        if state == .recording { stop() }
        recordedURL = nil
        recordedDuration = 0
        recordedFrameCount = 0
        levels = []
        state = .idle
    }

    // MARK: - Private

    private func resample(_ inBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let output = resampleBuffer else { return inBuffer }
        var consumed = false
        var convError: NSError?
        converter.convert(to: output, error: &convError) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData
            consumed = true
            return inBuffer
        }
        return convError == nil ? output : nil
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let processBuffer = resample(buffer) else { return }
        guard recordedFrameCount < Self.maxFrames, let audioFile else { return }

        let remaining = Self.maxFrames - recordedFrameCount
        let framesToWrite = min(processBuffer.frameLength, remaining)

        if framesToWrite > 0 {
            let bufferToWrite: AVAudioPCMBuffer
            if framesToWrite == processBuffer.frameLength {
                bufferToWrite = processBuffer
            } else if let trimmed = processBuffer.trimmedCopy(frameCount: framesToWrite) {
                bufferToWrite = trimmed
            } else {
                return
            }
            // AVAudioFile converts float32 → int16 automatically based on write settings
            try? audioFile.write(from: bufferToWrite)
            recordedFrameCount += framesToWrite
        }

        if recordedFrameCount >= Self.maxFrames {
            Task { @MainActor [weak self] in self?.stop() }
            return
        }

        if let channelData = processBuffer.floatChannelData {
            var rms: Float = 0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(processBuffer.frameLength))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.levels.append(rms)
                if self.levels.count > 300 { self.levels.removeFirst() }
            }
        }
    }

    private func clipsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - AVAudioPCMBuffer helper

private extension AVAudioPCMBuffer {
    func trimmedCopy(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frameCount <= self.frameLength,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        copy.frameLength = frameCount
        guard let src = floatChannelData, let dst = copy.floatChannelData else { return nil }
        for ch in 0..<Int(format.channelCount) {
            memcpy(dst[ch], src[ch], Int(frameCount) * MemoryLayout<Float>.size)
        }
        return copy
    }
}
