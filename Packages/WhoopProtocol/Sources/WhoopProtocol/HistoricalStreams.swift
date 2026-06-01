import Foundation

/// Turn historical (offload) parsed frames into datastore rows. Port of
/// interpreter.extract_historical_streams.
///
/// HR/R-R come from REALTIME_RAW_DATA (type 43) headers — the canonical stream
/// during a historical backfill, where type-40 frames are absent.
/// EVENT and COMMAND_RESPONSE handling is identical to extractStreams.
/// CRC-failed and non-ok frames are skipped.
///
/// Two strap clocks are in play. type-43 `timestamp` is the device-epoch (since-boot) and is
/// mapped to wall via the (deviceClockRef, wallClockRef) correlation from GET_CLOCK. type-47 `unix`
/// and EVENT timestamps are the strap RTC (real unix); when the RTC is wrong they are corrected by
/// `rtcSkew` (wall − strap-RTC-now, measured from GET_DATA_RANGE). rtcSkew is 0 when the RTC is good.
public func extractHistoricalStreams(_ parsed: [ParsedFrame],
                                     deviceClockRef: Int, wallClockRef: Int,
                                     rtcSkew: Int = 0) -> Streams {
    func wall(_ deviceTs: Int?) -> Int? {
        guard let d = deviceTs else { return nil }
        return wallClockRef + (d - deviceClockRef)
    }
    func rtc(_ rtcTs: Int?) -> Int? {
        guard let t = rtcTs else { return nil }
        return t + rtcSkew
    }
    var out = Streams()
    for r in parsed {
        if !r.ok || r.crcOK == false { continue }
        let p = r.parsed
        switch r.typeName {
        case "HISTORICAL_DATA":
            // type-47 unix is the strap RTC; rtc() applies the RTC skew (0 when the RTC is correct).
            guard let ts = rtc(p["unix"]?.intValue) else { continue }
            if let bpm = p["heart_rate"]?.intValue, bpm != 0 {  // skip startup hr=0
                out.hr.append(HRSample(ts: ts, bpm: bpm))
            }
            if let rrs = p["rr_intervals"]?.intArrayValue {
                for rr in rrs { out.rr.append(RRInterval(ts: ts, rrMs: rr)) }
            }
            if let red = p["spo2_red"]?.intValue {
                out.spo2.append(SpO2Sample(ts: ts, red: red, ir: p["spo2_ir"]?.intValue ?? 0))
            }
            if let raw = p["skin_temp_raw"]?.intValue {
                out.skinTemp.append(SkinTempSample(ts: ts, raw: raw))
            }
            if let raw = p["resp_rate_raw"]?.intValue {
                out.resp.append(RespSample(ts: ts, raw: raw))
            }
            if let gx = p["gravity_x"]?.doubleValue {
                out.gravity.append(GravitySample(ts: ts, x: gx,
                    y: p["gravity_y"]?.doubleValue ?? 0, z: p["gravity_z"]?.doubleValue ?? 0))
            }
        case "REALTIME_RAW_DATA":
            let ts = wall(p["timestamp"]?.intValue)
            if let ts = ts, let bpm = p["heart_rate"]?.intValue {
                out.hr.append(HRSample(ts: ts, bpm: bpm))
            }
            if let ts = ts, let rrs = p["rr_intervals"]?.intArrayValue {
                for rr in rrs { out.rr.append(RRInterval(ts: ts, rrMs: rr)) }
            }
        case "EVENT":
            // EVENT timestamps are strap RTC seconds; rtc() applies the RTC skew (0 when correct).
            guard let ts = rtc(p["event_timestamp"]?.intValue) else { continue }
            let kind = p["event"]?.stringValue ?? ""
            if kind.hasPrefix("BATTERY_LEVEL") { appendBattery(&out, ts: ts, p: p) }  // "BATTERY_LEVEL(3)"
            var payload = p
            payload.removeValue(forKey: "event")
            payload.removeValue(forKey: "event_timestamp")
            out.events.append(WhoopEvent(ts: ts, kind: kind, payload: payload))
        case "COMMAND_RESPONSE":
            // No device timestamp on COMMAND_RESPONSE → stamp battery at wallClockRef.
            appendBattery(&out, ts: wallClockRef, p: p)
        default:
            continue
        }
    }
    return out
}
