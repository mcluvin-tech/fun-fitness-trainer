import Foundation
import SwiftData

final class PersistenceController {
    static let shared = PersistenceController()

    /// Bump when `@Model` types change in a non-migratable way.
    private static let schemaVersion = 3
    private static let schemaVersionKey = "swiftDataSchemaVersion"

    let container: ModelContainer

    private init(inMemory: Bool = false) {
        if !inMemory {
            Self.applySchemaUpgradeIfNeeded()
        }

        let schema = Schema([
            Meal.self,
            ExerciseLog.self,
            DailyGoal.self,
            TrainerPhrase.self,
            UserSettings.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)

        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            self.container = container
            return
        }

        // Last resort: wipe incompatible store (e.g. after adding UserSettings fields).
        Self.removePersistentStoreFiles()
        Self.resetAppStateAfterStoreReset()

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData failed after store reset: \(error)")
        }
    }

    // MARK: - Schema upgrades

    private static func applySchemaUpgradeIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: schemaVersionKey)
        guard stored < schemaVersion else { return }

        removePersistentStoreFiles()
        resetAppStateAfterStoreReset()
        UserDefaults.standard.set(schemaVersion, forKey: schemaVersionKey)
    }

    private static func resetAppStateAfterStoreReset() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    private static func removePersistentStoreFiles() {
        let storeURL = ModelConfiguration().url
        let fm = FileManager.default
        let basePath = storeURL.path
        for suffix in ["", "-shm", "-wal"] {
            let path = basePath + suffix
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
    }
}
