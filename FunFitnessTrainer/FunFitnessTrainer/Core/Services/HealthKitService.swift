import Foundation
import HealthKit

/// Reads steps + active energy from Apple Health (Watch, iPhone, other synced devices).
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    @Published private(set) var stepsToday: Double = 0
    @Published private(set) var activeEnergyToday: Double = 0
    @Published private(set) var isAuthorized = false
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    let isAvailable = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var hasStartedObserving = false

    private var stepType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .stepCount)!
    }

    private var energyType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    }

    private var readTypes: Set<HKObjectType> {
        [stepType, energyType]
    }

    private init() {
        isConnected = HealthActivityPreferences.isConnected
        if isConnected {
            Task { await bootstrapIfConnected() }
        }
    }

    /// Restores a previous Health connection without showing the permission sheet again.
    func bootstrapIfConnected() async {
        guard isAvailable else {
            isConnected = HealthActivityPreferences.isConnected
            return
        }

        if HealthActivityPreferences.isConnected {
            await resumeConnectedSession()
            return
        }

        guard !HealthActivityPreferences.hasExplicitlyDisconnected else {
            isConnected = false
            return
        }

        // Recover from the old bug that cleared the connected flag after a successful grant.
        if await authorizationAlreadyDetermined() {
            setConnected(true)
            await resumeConnectedSession()
        }
    }

    @discardableResult
    func connect() async -> Bool {
        guard isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return false
        }

        do {
            if await authorizationAlreadyDetermined() {
                HealthActivityPreferences.hasExplicitlyDisconnected = false
                setConnected(true)
                isAuthorized = true
                lastError = nil
                await resumeConnectedSession()
                return true
            }

            try await store.requestAuthorization(toShare: [], read: readTypes)
            HealthActivityPreferences.hasExplicitlyDisconnected = false
            setConnected(true)
            isAuthorized = true
            lastError = nil
            await resumeConnectedSession()
            if HealthActivityPreferences.stepNotificationsEnabled {
                await NotificationService.shared.requestAuthorization()
            }
            return true
        } catch {
            lastError = error.localizedDescription
            isAuthorized = false
            return false
        }
    }

    func disconnect() {
        stopObserving()
        HealthActivityPreferences.hasExplicitlyDisconnected = true
        setConnected(false)
        isAuthorized = false
        stepsToday = 0
        activeEnergyToday = 0
    }

    func refreshToday() async {
        guard isAvailable, HealthActivityPreferences.isConnected else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let steps = sumToday(for: stepType, unit: .count())
        async let energy = sumToday(for: energyType, unit: .kilocalorie())

        let (stepSum, energySum) = await (steps, energy)
        stepsToday = stepSum
        activeEnergyToday = energySum

        await NotificationService.shared.notifyStepGoalIfNeeded(steps: stepsToday)
    }

    /// Active energy for activity display. Does not increase today's food target.
    var calorieBonusFromHealth: Double {
        guard isConnected else { return 0 }
        return activeEnergyToday
    }

    private func resumeConnectedSession() async {
        isConnected = true
        isAuthorized = true
        lastError = nil
        await refreshToday()
        startObservingIfNeeded()
    }

    /// Read permission is not exposed as granted/denied. `.unnecessary` means iOS already asked.
    private func authorizationAlreadyDetermined() async -> Bool {
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            return status == .unnecessary
        } catch {
            let stepStatus = store.authorizationStatus(for: stepType)
            let energyStatus = store.authorizationStatus(for: energyType)
            return stepStatus == .sharingAuthorized || energyStatus == .sharingAuthorized
        }
    }

    private func setConnected(_ value: Bool) {
        HealthActivityPreferences.isConnected = value
        isConnected = value
    }

    // MARK: - Queries

    private func sumToday(for type: HKQuantityType, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let start = Calendar.current.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Background updates

    private func startObservingIfNeeded() {
        guard isAvailable, HealthActivityPreferences.isConnected, !hasStartedObserving else { return }
        hasStartedObserving = true

        for type in [stepType, energyType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                Task { @MainActor in
                    if error == nil {
                        await self?.refreshToday()
                    }
                    completionHandler()
                }
            }
            store.execute(query)
            observerQueries.append(query)

            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    private func stopObserving() {
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
        hasStartedObserving = false
        store.disableAllBackgroundDelivery { _, _ in }
    }
}
