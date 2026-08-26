import Foundation
import HealthKit

/// Steps, distance, and workouts — "cheap, high-signal, low review friction"
/// per build spec §4. First provider recommended to build, and the only one
/// with no on-screen prompt of its own beyond the one system authorization
/// sheet (HealthKit batches every requested type into one dialog).
struct HealthSignalProvider: DaySignalProvider {
    let kind: DaySignalKind = .activity

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        ]
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        return types
    }

    func isAuthorized() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        // HealthKit deliberately doesn't reveal read-authorization status
        // (to avoid leaking whether data exists); a prior successful
        // `requestAuthorization` call is the only signal we get, tracked in
        // `SettingsStore.healthEnabled` at request time.
        return await SettingsStore.shared.healthEnabled
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await MainActor.run { SettingsStore.shared.healthEnabled = true }
            return true
        } catch {
            return false
        }
    }

    func collectSignals(for day: DateInterval) async throws -> [DaySignal] {
        guard await isAuthorized() else { return [] }

        async let steps = quantityTotal(for: HKQuantityType.quantityType(forIdentifier: .stepCount)!, unit: .count(), in: day)
        async let distance = quantityTotal(for: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!, unit: .meter(), in: day)
        async let workouts = workoutSummaries(in: day)
        async let sleep = sleepHours(in: day)

        let payload = ActivityPayload(
            stepCount: Int(await steps),
            distanceMeters: await distance,
            workoutSummaries: await workouts,
            sleepHours: await sleep
        )

        guard payload.stepCount > 0 || payload.distanceMeters > 0 || !payload.workoutSummaries.isEmpty || payload.sleepHours > 0 else {
            return []
        }

        let signal = DaySignal(kind: .activity, timestamp: day.start)
        signal.setPayload(payload)
        return [signal]
    }

    private func quantityTotal(for type: HKQuantityType, unit: HKUnit, in day: DateInterval) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    /// Total time spent in any "asleep" sub-state (as opposed to merely "in
    /// bed") across the day, summed from possibly-overlapping source
    /// samples. §4 lists "sleep" under the HealthKit signal table.
    private func sleepHours(in day: DateInterval) async -> Double {
        await withCheckedContinuation { continuation in
            let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let asleepSeconds = (samples as? [HKCategorySample] ?? [])
                    .filter { sample in
                        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
                        return HKCategoryValueSleepAnalysis.allAsleepValues.contains(value)
                    }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: asleepSeconds / 3600)
            }
            store.execute(query)
        }
    }

    private func workoutSummaries(in day: DateInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let summaries = workouts.map { workout in
                    "\(workout.workoutActivityType.name) for \(Int(workout.duration / 60)) min"
                }
                continuation.resume(returning: summaries)
            }
            store.execute(query)
        }
    }
}

private extension HKWorkoutActivityType {
    /// A short, human-readable label. HealthKit has no built-in display
    /// string, so this covers the common cases and falls back plainly.
    var name: String {
        switch self {
        case .running: "a run"
        case .walking: "a walk"
        case .cycling: "a bike ride"
        case .swimming: "a swim"
        case .yoga: "yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "strength training"
        case .hiking: "a hike"
        default: "a workout"
        }
    }
}
