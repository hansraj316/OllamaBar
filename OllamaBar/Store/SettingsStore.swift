import Foundation
import Observation
@Observable
@MainActor
final class SettingsStore {
    var settings = Settings()
    init(persistence: PersistenceManager = PersistenceManager()) {}
}
