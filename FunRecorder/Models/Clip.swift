import Foundation
import SwiftData

@Model
final class Clip {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var detectedTempoBPM: Double?
    var regionStartSamples: Int
    var regionEndSamples: Int
    var sampleRate: Int

    init(
        id: UUID = UUID(),
        name: String,
        duration: TimeInterval,
        audioFileName: String,
        detectedTempoBPM: Double? = nil,
        regionStartSamples: Int,
        regionEndSamples: Int,
        sampleRate: Int = 32000
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.duration = duration
        self.audioFileName = audioFileName
        self.detectedTempoBPM = detectedTempoBPM
        self.regionStartSamples = regionStartSamples
        self.regionEndSamples = regionEndSamples
        self.sampleRate = sampleRate
    }

    var regionStartTime: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(regionStartSamples) / TimeInterval(sampleRate)
    }

    var regionEndTime: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(regionEndSamples) / TimeInterval(sampleRate)
    }
}
