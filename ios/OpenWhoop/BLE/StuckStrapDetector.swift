import Foundation

/// Detects a "stuck strap": the strap reports records newer than ours (`strapNewestTs` from
/// GET_DATA_RANGE) AND our biometric data frontier (`ourFrontierTs` = max persisted HR ts; NOT the
/// strap_trim cursor, which climbs on empty ENDs while stuck) hasn't advanced for `stuckAfterSeconds`.
/// Comparing the two is what separates genuinely stuck from off-wrist / caught-up (strap not ahead of
/// us → no new data expected → never stuck). Pure + value-typed so it's trivially testable.
struct StuckStrapDetector {
    let stuckAfterSeconds: TimeInterval
    /// How far ahead the strap must be (seconds) before "frozen frontier" counts as behind, not noise.
    let behindGapSeconds: Int
    private var lastFrontierTs: Int?
    private var lastTrimCursor: Int?
    private var lastAdvanceWall: TimeInterval?

    init(stuckAfterSeconds: TimeInterval, behindGapSeconds: Int = 300) {
        self.stuckAfterSeconds = stuckAfterSeconds
        self.behindGapSeconds = behindGapSeconds
    }

    /// `strapNewestTs` = newest record the strap reports having (GET_DATA_RANGE). `ourFrontierTs` =
    /// newest record we've persisted. `trimCursor` = the offload's strap_trim position. Stuck when
    /// our frontier hasn't advanced for >= stuckAfterSeconds AND the offload is *trying* — either the
    /// strap is ahead by > behindGapSeconds, OR the trim cursor is advancing while no real data lands
    /// (the empty-END spin). The trim signal is clock-independent, so a wrong RTC (which can make
    /// strapNewest look not-behind) no longer masks a wedged offload. Advancing frontier → healthy.
    mutating func observe(strapNewestTs: Int?, ourFrontierTs: Int?, trimCursor: Int? = nil, now: TimeInterval) -> Bool {
        guard let frontier = ourFrontierTs else { return false }
        let trimAdvanced = (trimCursor != nil && lastTrimCursor != nil && trimCursor! > lastTrimCursor!)
        if let t = trimCursor { lastTrimCursor = t }      // captured trimAdvanced above; update for next call

        guard let last = lastFrontierTs else {            // first observation: seed, not stuck
            lastFrontierTs = frontier; lastAdvanceWall = now; return false
        }
        if frontier > last {                              // progressing → healthy, reset the clock
            lastFrontierTs = frontier; lastAdvanceWall = now; return false
        }
        let behind = (strapNewestTs.map { $0 - frontier > behindGapSeconds }) ?? false
        if !(behind || trimAdvanced) {                    // caught up / off-wrist / idle → not stuck
            lastAdvanceWall = now; return false
        }
        return (now - (lastAdvanceWall ?? now)) >= stuckAfterSeconds  // frozen + offload trying → stuck
    }
}
