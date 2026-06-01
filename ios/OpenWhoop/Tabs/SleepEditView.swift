import SwiftUI
import WhoopStore
import WhoopCompute

struct SleepEditView: View {
    let session: CachedSleepSession
    let deviceId: String
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metrics: MetricsRepository

    @State private var sleepStart: Date
    @State private var sleepEnd: Date
    @State private var hasExtraSegment = false
    @State private var extraStart: Date
    @State private var extraEnd: Date
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    init(session: CachedSleepSession, deviceId: String, onSave: @escaping () async -> Void) {
        self.session = session
        self.deviceId = deviceId
        self.onSave = onSave
        let start = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        let end   = Date(timeIntervalSince1970: TimeInterval(session.endTs))
        _sleepStart = State(initialValue: start)
        _sleepEnd   = State(initialValue: end)
        _extraStart = State(initialValue: end)
        _extraEnd   = State(initialValue: end.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                Form {
                    mainSegmentSection
                    extraSegmentSection
                    summarySection
                }
                .scrollContentBackground(.hidden)
                .background(WH.Color.background)
            }
            .navigationTitle("Edit Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WH.Color.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundStyle(WH.Color.strainBlue)
                        }
                    }
                    .disabled(isSaving || !isValid)
                }
            }
        }
    }

    // MARK: - Sections

    private var mainSegmentSection: some View {
        Section {
            DatePicker("Sleep", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                .tint(WH.Color.strainBlue)
                .foregroundStyle(WH.Color.textPrimary)
                .listRowBackground(WH.Color.surface)

            DatePicker("Wake", selection: $sleepEnd, in: sleepStart..., displayedComponents: [.date, .hourAndMinute])
                .tint(WH.Color.strainBlue)
                .foregroundStyle(WH.Color.textPrimary)
                .listRowBackground(WH.Color.surface)
        } header: {
            sectionHeader("Main Sleep")
        }
    }

    private var extraSegmentSection: some View {
        Section {
            Toggle("Add another sleep period", isOn: $hasExtraSegment)
                .tint(WH.Color.sleepPurple)
                .foregroundStyle(WH.Color.textPrimary)
                .listRowBackground(WH.Color.surface)

            if hasExtraSegment {
                DatePicker("Sleep", selection: $extraStart, in: sleepEnd..., displayedComponents: [.date, .hourAndMinute])
                    .tint(WH.Color.strainBlue)
                    .foregroundStyle(WH.Color.textPrimary)
                    .listRowBackground(WH.Color.surface)

                DatePicker("Wake", selection: $extraEnd, in: extraStart..., displayedComponents: [.date, .hourAndMinute])
                    .tint(WH.Color.strainBlue)
                    .foregroundStyle(WH.Color.textPrimary)
                    .listRowBackground(WH.Color.surface)
            }
        } header: {
            sectionHeader("Additional Period")
        } footer: {
            Text("Use this for returning to sleep after briefly waking up — e.g. getting up to use the bathroom then going back to sleep.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var summarySection: some View {
        Section {
            HStack {
                Text("Total time in bed")
                    .foregroundStyle(WH.Color.textSecondary)
                Spacer()
                Text(formatMinutes(totalMinutes))
                    .foregroundStyle(WH.Color.textPrimary)
                    .fontWeight(.medium)
            }
            .listRowBackground(WH.Color.surface)
        } header: {
            sectionHeader("Summary")
        }
    }

    // MARK: - Helpers

    private var totalMinutes: Double {
        let main = sleepEnd.timeIntervalSince(sleepStart) / 60
        let extra = hasExtraSegment ? extraEnd.timeIntervalSince(extraStart) / 60 : 0
        return max(0, main + extra)
    }

    private var isValid: Bool {
        sleepEnd > sleepStart && (!hasExtraSegment || extraEnd > extraStart)
    }

    private func save() async {
        isSaving = true

        guard let path = try? StorePaths.defaultDatabasePath(),
              let store = try? await WhoopStore(path: path) else {
            errorMessage = "Could not open local database"
            isSaving = false
            return
        }

        let mainStartTs = Int(sleepStart.timeIntervalSince1970)
        let mainEndTs   = Int(sleepEnd.timeIntervalSince1970)
        let mergedEnd   = hasExtraSegment ? Int(extraEnd.timeIntervalSince1970) : mainEndTs

        // Build stagesJSON here rather than letting the engine re-stage the merged window.
        // Staging the full merged window misreads the wake gap as prolonged wakefulness.
        let stagesJSON: String? = await buildStagesJSON(
            store: store,
            mainStartTs: mainStartTs,
            mainEndTs: mainEndTs,
            extraStartTs: hasExtraSegment ? Int(extraStart.timeIntervalSince1970) : nil,
            extraEndTs:   hasExtraSegment ? Int(extraEnd.timeIntervalSince1970)   : nil
        )

        let overrideSession = CachedSleepSession(
            startTs: mainStartTs,
            endTs: mergedEnd,
            efficiency: nil,
            restingHr: nil,
            avgHrv: nil,
            stagesJSON: stagesJSON,
            isManualOverride: true
        )

        do {
            try await store.deleteSleepSession(deviceId: deviceId, startTs: session.startTs)
            _ = try await store.upsertSleepSessions([overrideSession], deviceId: deviceId)
        } catch {
            errorMessage = "DB write failed: \(error.localizedDescription)"
            isSaving = false
            return
        }

        // Engine re-runs to recompute HRV/RHR/recovery/strain from the corrected window.
        // It will use our pre-built stagesJSON and skip its own staging pass.
        let engine = OnDeviceEngine(store: store, deviceId: deviceId)
        if let data = UserDefaults.standard.data(forKey: "com.openwhoop.profile.v1"),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var p = EngineProfile()
            if let age = raw["age"] as? Int { p.age = age }
            if let sex = raw["sex"] as? String { p.sex = sex }
            if let w = raw["weight_kg"] as? Double { p.weightKg = w }
            if let h = raw["height_cm"] as? Double { p.heightCm = h }
            await engine.setProfile(p)
        }
        await engine.computeRecent(days: 3, force: true)

        await metrics.reloadFromStore()
        await onSave()
        isSaving = false
        dismiss()
    }

    /// Build the merged stagesJSON for the override session.
    ///
    /// Strategy:
    /// - Original stages (from the auto-detected session) are correct for the main window.
    /// - If the user just extended the end time: append "light" for the extra tail
    ///   (morning return-to-sleep is almost always light/REM, never deep).
    /// - If the user added a distinct extra segment (gap ≤ 30 min): query raw sensor data
    ///   and run SleepStaging independently on just that window, then combine.
    /// - If gap > 30 min: treat extra as independent, stage it too (likely a nap).
    private func buildStagesJSON(
        store: WhoopStore,
        mainStartTs: Int, mainEndTs: Int,
        extraStartTs: Int?, extraEndTs: Int?
    ) async -> String? {
        // Work with raw JSON arrays via JSONSerialization to avoid cross-module Codable issues.
        // A stage dict is { "start": Int, "end": Int, "stage": String }.

        // Parse original auto-detected stages for the main sleep period.
        var combined: [[String: Any]] = []
        if let json = session.stagesJSON,
           let data = json.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Trim stages that exceed new mainEndTs (user may have shortened end).
            combined = arr.compactMap { seg -> [String: Any]? in
                guard let start = seg["start"] as? Int,
                      let end   = seg["end"]   as? Int,
                      let stage = seg["stage"] as? String,
                      start < mainEndTs else { return nil }
                return ["start": start, "end": min(end, mainEndTs), "stage": stage]
            }
        }

        // No extra segment: just extend end time with "light" if the user pushed it later.
        guard let extraStart = extraStartTs, let extraEnd = extraEndTs else {
            let origEnd = session.endTs
            if mainEndTs > origEnd {
                combined.append(["start": origEnd, "end": mainEndTs, "stage": "light"])
            }
            return jsonString(combined)
        }

        // Wake gap between main sleep end and extra segment start.
        if extraStart > mainEndTs {
            combined.append(["start": mainEndTs, "end": extraStart, "stage": "wake"])
        }

        // Stage the extra segment independently using real sensor data.
        let extGrav = (try? await store.gravitySamples(deviceId: deviceId,
                                                        from: mainEndTs, to: extraEnd,
                                                        limit: 50_000)) ?? []
        let extHR   = (try? await store.hrSamples(deviceId: deviceId,
                                                   from: mainEndTs, to: extraEnd,
                                                   limit: 50_000)) ?? []
        let extRR   = (try? await store.rrIntervals(deviceId: deviceId,
                                                     from: mainEndTs, to: extraEnd,
                                                     limit: 50_000)) ?? []

        let extGravInput = extGrav.map { SleepDetection.GravitySample(ts: $0.ts, x: $0.x, y: $0.y, z: $0.z) }
        let extHRInput   = extHR.map   { (ts: $0.ts, bpm: $0.bpm) }
        let extRRInput   = extRR.map   { (ts: $0.ts, rrMs: $0.rrMs) }

        let extraStages = SleepStaging.stage(
            sleepStart: extraStart, sleepEnd: extraEnd,
            gravity: extGravInput, hr: extHRInput, rr: extRRInput
        )

        // If staging produced nothing useful fall back to "light" — brief morning
        // return-to-sleep is almost always light/REM, never deep.
        if extraStages.isEmpty || extraStages.allSatisfy({ $0.stage == "wake" }) {
            combined.append(["start": extraStart, "end": extraEnd, "stage": "light"])
        } else {
            combined.append(contentsOf: extraStages.map {
                ["start": $0.start, "end": $0.end, "stage": $0.stage] as [String: Any]
            })
        }

        return jsonString(combined)
    }

    private func jsonString(_ arr: [[String: Any]]) -> String? {
        guard !arr.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.2)
    }

    private func formatMinutes(_ m: Double) -> String {
        let h = Int(m) / 60
        let min = Int(m) % 60
        if h == 0 { return "\(min)m" }
        return min == 0 ? "\(h)h" : "\(h)h \(min)m"
    }
}
