import XCTest
@testable import FunRecorder

final class ClipTests: XCTestCase {
    func test_regionStartTime_convertsFromSamples() {
        let clip = Clip(
            name: "Test", duration: 10,
            audioFileName: "test.wav",
            regionStartSamples: 32000,
            regionEndSamples: 64000
        )
        XCTAssertEqual(clip.regionStartTime, 1.0, accuracy: 0.001)
    }

    func test_regionEndTime_convertsFromSamples() {
        let clip = Clip(
            name: "Test", duration: 10,
            audioFileName: "test.wav",
            regionStartSamples: 32000,
            regionEndSamples: 64000
        )
        XCTAssertEqual(clip.regionEndTime, 2.0, accuracy: 0.001)
    }

    func test_defaultSampleRate_is32000() {
        let clip = Clip(
            name: "Test", duration: 5,
            audioFileName: "test.wav",
            regionStartSamples: 0,
            regionEndSamples: 160000
        )
        XCTAssertEqual(clip.sampleRate, 32000)
    }
}
