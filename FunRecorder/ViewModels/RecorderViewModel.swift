import Foundation
import SwiftData

@Observable
final class RecorderViewModel {
    enum AppState { case empty, recording, editing }

    private(set) var appState: AppState = .empty
    private(set) var beatGrid: BeatGrid?
    private(set) var currentDuration: TimeInterval = 0
    private(set) var currentURL: URL?
    var pendingSaveName: String? = nil  // Non-nil while rename field is shown

    var regionStartSamples: Int = 0
    var regionEndSamples: Int = 0

    let recorder = AudioRecorder()
    let player = AudioPlayer()

    // MARK: - Convenience accessors

    var levels: [Float] { recorder.levels }
    var isPlaying: Bool { player.isPlaying }
    var playheadTime: Double { player.playheadTime }
    var isLooping: Bool {
        get { player.isLooping }
        set { player.isLooping = newValue }
    }

    // MARK: - Recording

    func startRecording() async throws {
        guard await recorder.requestMicrophonePermission() else {
            throw AudioRecorderError.permissionDenied
        }
        let url = try recorder.start()
        currentURL = url
        appState = .recording
    }

    func stopRecording() async {
        recorder.stop()
        guard let url = recorder.recordedURL, recorder.recordedDuration > 0 else {
            appState = .empty
            return
        }
        currentDuration = recorder.recordedDuration
        currentURL = url
        regionStartSamples = 0
        regionEndSamples = Int(recorder.recordedDuration * AudioRecorder.sampleRate)
        player.updateRegion(startSamples: regionStartSamples, endSamples: regionEndSamples)
        try? player.load(url: url)
        appState = .editing

        // Beat detection runs in background after UI transitions to editing
        if let result = await BeatDetector.detect(audioFileURL: url, duration: currentDuration) {
            beatGrid = result.grid
        } else {
            beatGrid = nil
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to time: Double) {
        player.seek(to: time)
    }

    // MARK: - Region selection

    /// Updates region, enforcing minimum size of 1 second (32000 samples).
    func updateRegion(startSamples: Int, endSamples: Int) {
        let minSamples = Int(AudioRecorder.sampleRate)  // 1 second
        let totalSamples = Int(currentDuration * AudioRecorder.sampleRate)
        let clampedStart = max(0, min(startSamples, totalSamples - minSamples))
        let clampedEnd = max(clampedStart + minSamples, min(endSamples, totalSamples))
        regionStartSamples = clampedStart
        regionEndSamples = clampedEnd
        player.updateRegion(startSamples: clampedStart, endSamples: clampedEnd)
    }

    func snappedTime(for time: Double) -> Double {
        beatGrid?.nearestSixteenth(to: time) ?? time
    }

    func beatLabel(for time: Double) -> String? {
        beatGrid?.label(at: time)
    }

    // MARK: - Save / Load

    func beginSave() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        pendingSaveName = formatter.string(from: Date())
    }

    func cancelSave() {
        pendingSaveName = nil
    }

    func confirmSave(name: String, context: ModelContext) throws {
        guard let url = currentURL else { return }
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (pendingSaveName ?? "Untitled")
            : name
        let clip = Clip(
            name: finalName,
            duration: currentDuration,
            audioFileName: url.lastPathComponent,
            detectedTempoBPM: beatGrid?.bpm,
            regionStartSamples: regionStartSamples,
            regionEndSamples: regionEndSamples
        )
        context.insert(clip)
        try context.save()
        pendingSaveName = nil
    }

    func load(clip: Clip) throws {
        player.stop()
        let url = clipsDirectory().appendingPathComponent(clip.audioFileName)
        try player.load(url: url)
        currentURL = url
        currentDuration = clip.duration
        regionStartSamples = clip.regionStartSamples
        regionEndSamples = clip.regionEndSamples
        player.updateRegion(startSamples: clip.regionStartSamples, endSamples: clip.regionEndSamples)
        if let bpm = clip.detectedTempoBPM {
            beatGrid = BeatGrid.build(bpm: bpm, startOffset: 0, duration: clip.duration)
        } else {
            beatGrid = nil
        }
        appState = .editing
    }

    func delete(clip: Clip, context: ModelContext) throws {
        let url = clipsDirectory().appendingPathComponent(clip.audioFileName)
        try? FileManager.default.removeItem(at: url)
        context.delete(clip)
        try context.save()
    }

    func newRecording() {
        player.stop()
        recorder.reset()
        beatGrid = nil
        currentURL = nil
        currentDuration = 0
        regionStartSamples = 0
        regionEndSamples = 0
        pendingSaveName = nil
        appState = .empty
    }

    // MARK: - Private

    private func clipsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
