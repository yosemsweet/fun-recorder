import XCTest
@testable import FunRecorder

final class BeatGridTests: XCTestCase {
    // 120 BPM: quarter note = 0.5s, 16th note = 0.125s
    let grid120 = BeatGrid.build(bpm: 120, startOffset: 0, duration: 4.0)

    func test_build_generatesCorrectNumberOf16ths() {
        // 4 seconds at 120 BPM = 8 quarter notes = 32 sixteenths
        // +1 for position at t=0
        XCTAssertEqual(grid120.sixteenthPositions.count, 33)
    }

    func test_build_firstPositionIsAtStartOffset() {
        XCTAssertEqual(grid120.sixteenthPositions.first!, 0.0, accuracy: 0.001)
    }

    func test_build_16thSpacingIsCorrect() {
        let spacing = grid120.sixteenthPositions[1] - grid120.sixteenthPositions[0]
        XCTAssertEqual(spacing, 0.125, accuracy: 0.001)  // 60/120/4
    }

    func test_nearestSixteenth_snapsToClosestPosition() {
        // 0.13 is closer to 0.125 than to 0.25
        XCTAssertEqual(grid120.nearestSixteenth(to: 0.13), 0.125, accuracy: 0.001)
    }

    func test_nearestSixteenth_exactMatchReturnsExact() {
        XCTAssertEqual(grid120.nearestSixteenth(to: 0.5), 0.5, accuracy: 0.001)
    }

    func test_nearestSixteenth_emptyGridReturnsSameTime() {
        let empty = BeatGrid(bpm: 120, sixteenthPositions: [])
        XCTAssertEqual(empty.nearestSixteenth(to: 1.23), 1.23, accuracy: 0.001)
    }

    func test_label_quarterBeatShowsBarAndBeat() {
        // 120 BPM, 4/4: bar 1 beat 1 = 0.0s, bar 1 beat 2 = 0.5s
        XCTAssertEqual(grid120.label(at: 0.0), "Bar 1, beat 1")
        XCTAssertEqual(grid120.label(at: 0.5), "Bar 1, beat 2")
    }

    func test_label_nonQuarterShowsSixteenth() {
        // 0.125s = bar 1, beat 1, 16th 2
        XCTAssertEqual(grid120.label(at: 0.125), "Bar 1, beat 1.2")
    }
}
