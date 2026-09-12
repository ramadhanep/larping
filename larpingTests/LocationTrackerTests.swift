import XCTest
@testable import larping

final class LocationTrackerTests: XCTestCase {
    /// Injectable wall clock so start/pause/resume/finish happen at exact
    /// timestamps — no real sleeps, no flaky timing.
    private final class Clock {
        var now = Date()
    }

    private let clock = Clock()

    /// Scenario: 10' record, 20' pause, 10' record.
    @MainActor
    func testSinglePauseExcludesPausedTime() {
        let tracker = makeTracker()
        let start = beginRecording(tracker)
        advance(600)          // recording 10 min
        tracker.pause()
        let pausedAt = clock.now
        advance(1200)         // paused 20 min
        XCTAssertEqual(tracker.state, .paused)
        tracker.resume()
        advance(600)          // recording 10 min
        let finish = clock.now
        let recording = tracker.stop()

        XCTAssertEqual(recording.activeDurationSeconds, 1200, accuracy: 0.001)
        XCTAssertEqual(recording.durationSeconds, 1200)
        // wall-clock timestamps reflect the real (pause-inclusive) timeline
        XCTAssertEqual(recording.startedAt, start)
        XCTAssertEqual(pausedAt, start.addingTimeInterval(600))
        XCTAssertEqual(finish, start.addingTimeInterval(600 + 1200 + 600))
        XCTAssertEqual(recording.endedAt, finish)
    }

    @MainActor
    func testNoPauseUsesFullDuration() {
        let tracker = makeTracker()
        _ = beginRecording(tracker)
        advance(900)
        let recording = tracker.stop()

        XCTAssertEqual(recording.activeDurationSeconds, 900, accuracy: 0.001)
        XCTAssertEqual(recording.durationSeconds, 900)
        XCTAssertEqual(tracker.state, .idle)
    }

    @MainActor
    func testMultiplePausesResumesAccumulateActiveOnly() {
        let tracker = makeTracker()
        _ = beginRecording(tracker)
        advance(300)
        tracker.pause()
        advance(100)
        tracker.resume()
        advance(200)
        tracker.pause()
        advance(50)
        tracker.resume()
        advance(150)
        let recording = tracker.stop()

        // active segments: 300 + 200 + 150 = 650; pauses (100 + 50) ignored
        XCTAssertEqual(recording.activeDurationSeconds, 650, accuracy: 0.001)
        XCTAssertEqual(recording.durationSeconds, 650)
    }

    @MainActor
    func testFinishWhilePaused() {
        let tracker = makeTracker()
        _ = beginRecording(tracker)
        advance(600)
        tracker.pause()
        advance(999)          // idle the whole pause
        let recording = tracker.stop()   // finish while still paused

        XCTAssertEqual(recording.activeDurationSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(recording.durationSeconds, 600)
    }

    @MainActor
    func testFinishWhileRecordingIncludesFinalInterval() {
        let tracker = makeTracker()
        _ = beginRecording(tracker)
        advance(700)
        let recording = tracker.stop()   // finish mid-recording

        XCTAssertEqual(recording.activeDurationSeconds, 700, accuracy: 0.001)
        XCTAssertEqual(recording.durationSeconds, 700)
    }

    @MainActor
    func testNearZeroDurationIsSafe() {
        let tracker = makeTracker()
        _ = beginRecording(tracker)
        // finish immediately — sub-second, no accumulation event in between
        let recording = tracker.stop()

        XCTAssertLessThan(recording.activeDurationSeconds, 1)
        XCTAssertEqual(recording.durationSeconds, 0)
    }

    /// Displays whole seconds; after boundary recompute (pause/finish) the
    /// on-screen timer equals the active accumulation, never the pause.
    @MainActor
    func testElapsedSecondsTracksActiveTime() {
        let tracker = makeTracker()
        _ = beginRecording(tracker)
        advance(61)
        tracker.pause()
        XCTAssertEqual(tracker.elapsedSeconds, 61)
        advance(5000)     // huge pause
        tracker.resume()
        advance(39)
        tracker.pause()   // boundary recompute: 61 + 39
        XCTAssertEqual(tracker.elapsedSeconds, 100)
        tracker.resume()
        advance(7)
        let recording = tracker.stop()
        XCTAssertEqual(recording.activeDurationSeconds, 107, accuracy: 0.001)
        XCTAssertEqual(recording.durationSeconds, 107)
    }

    // MARK: - Helpers

    @MainActor
    private func beginRecording(_ tracker: LocationTracker) -> Date {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.now = start
        tracker.start()
        return start
    }

    @MainActor
    private func makeTracker() -> LocationTracker {
        LocationTracker { [clock] in clock.now }
    }

    private func advance(_ seconds: TimeInterval) {
        clock.now = clock.now.addingTimeInterval(seconds)
    }
}