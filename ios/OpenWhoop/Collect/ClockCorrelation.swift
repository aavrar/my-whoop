import Foundation
import WhoopProtocol
import WhoopStore

/// Pure helper: correlate the strap's monotonic device clock to wall time.
/// REALTIME_DATA timestamps are a device monotonic epoch; the server/app maps them to
/// unix time using the (device, wall) pair captured at connect via GET_CLOCK + now.
/// No CoreBluetooth, no I/O — fully unit-testable.
enum ClockCorrelation {
    /// Build a `ClockRef` from a decoded GET_CLOCK COMMAND_RESPONSE frame and the wall
    /// time observed when the response arrived. Returns nil unless the frame parsed OK,
    /// passed CRC, and carries a `clock` value. NOTE: `clock` is the device-epoch (since-boot),
    /// NOT the RTC — it maps type-40/43 device timestamps, not the type-47 RTC unix.
    static func clockRef(from parsed: ParsedFrame, wall: Int) -> ClockRef? {
        guard parsed.ok, parsed.crcOK != false,
              let device = parsed.parsed["clock"]?.intValue else { return nil }
        return ClockRef(device: device, wall: wall)
    }
}

/// The strap RTC error (wall − strap-RTC), in seconds, applied to type-47 + EVENT timestamps which
/// carry the strap RTC (real unix). Measured from GET_DATA_RANGE's newest record (also RTC real
/// unix) against wall time, and persisted so the offload path can correct even before the next
/// range reply lands. 0 when the RTC is accurate.
enum RtcSkew {
    private static let key = "rtcSkewSeconds.v1"

    /// Plausible strap-RTC range for a real-unix reading (2023-11 .. 2027-04).
    static let plausibleRTC: ClosedRange<Int> = 1_700_000_000...1_900_000_000

    /// A correction is only trusted when the strap reads BEHIND wall by a sane margin (this strap
    /// resets ~1.5y into the past). Anything outside this band is noise — GET_DATA_RANGE's loose
    /// u32 scan can surface non-timestamp fields — and must NOT be applied, or it mis-dates data.
    static let plausibleSkew: ClosedRange<Int> = -86_400...(800 * 86_400)   // -1d .. +800d

    /// Skew implied by a strap newest-record RTC seen at `wall`, or nil if the reading or the
    /// resulting skew is implausible (then the last good skew / 0 stands).
    static func measure(strapNewestRTC: Int, wall: Int) -> Int? {
        guard plausibleRTC.contains(strapNewestRTC) else { return nil }
        let skew = wall - strapNewestRTC
        guard plausibleSkew.contains(skew) else { return nil }
        return skew
    }

    static func save(_ seconds: Int) {
        guard plausibleSkew.contains(seconds) else { return }
        UserDefaults.standard.set(seconds, forKey: key)
    }

    /// Persisted skew, or 0 if absent/out-of-band (a stale bad value never mis-dates data).
    static func load() -> Int {
        let v = UserDefaults.standard.integer(forKey: key)
        return plausibleSkew.contains(v) && v != 0 ? v : 0
    }
}
