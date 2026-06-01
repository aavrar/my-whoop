import Foundation

/// When the strap RTC in type-47 / EVENT payloads is far ahead of wall time, GET_DATA_RANGE's
/// newest marker can still look sane — so `rtcSkew` from range alone under-corrects. Snap any
/// offload batch whose decoded timestamps land in the future back to `wall`.
public enum HistoricalTimestampNormalize {
    /// Timestamps more than this many seconds after `wall` are treated as strap-fast RTC.
    public static let futureSlopSeconds = 7 * 86_400

    /// If any sample in `streams` is implausibly far in the future vs `wall`, shift every
    /// timestamp in the batch by `(wall - maxTs)` so the newest row aligns with connect-time wall.
    public static func applyIfNeeded(_ streams: Streams, wall: Int) -> Streams {
        guard let maxTs = allTimestamps(in: streams).max(), maxTs > wall + futureSlopSeconds else {
            return streams
        }
        return shift(streams, by: wall - maxTs)
    }

    private static func allTimestamps(in s: Streams) -> [Int] {
        var ts: [Int] = []
        ts.append(contentsOf: s.hr.map(\.ts))
        ts.append(contentsOf: s.rr.map(\.ts))
        ts.append(contentsOf: s.events.map(\.ts))
        ts.append(contentsOf: s.battery.map(\.ts))
        ts.append(contentsOf: s.spo2.map(\.ts))
        ts.append(contentsOf: s.skinTemp.map(\.ts))
        ts.append(contentsOf: s.resp.map(\.ts))
        ts.append(contentsOf: s.gravity.map(\.ts))
        return ts
    }

    private static func shift(_ s: Streams, by delta: Int) -> Streams {
        var out = s
        out.hr = s.hr.map { HRSample(ts: $0.ts + delta, bpm: $0.bpm) }
        out.rr = s.rr.map { RRInterval(ts: $0.ts + delta, rrMs: $0.rrMs) }
        out.events = s.events.map { WhoopEvent(ts: $0.ts + delta, kind: $0.kind, payload: $0.payload) }
        out.battery = s.battery.map {
            BatterySample(ts: $0.ts + delta, soc: $0.soc, mv: $0.mv, charging: $0.charging)
        }
        out.spo2 = s.spo2.map { SpO2Sample(ts: $0.ts + delta, red: $0.red, ir: $0.ir) }
        out.skinTemp = s.skinTemp.map { SkinTempSample(ts: $0.ts + delta, raw: $0.raw) }
        out.resp = s.resp.map { RespSample(ts: $0.ts + delta, raw: $0.raw) }
        out.gravity = s.gravity.map {
            GravitySample(ts: $0.ts + delta, x: $0.x, y: $0.y, z: $0.z)
        }
        return out
    }
}
