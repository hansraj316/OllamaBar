import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    var settings: Settings {
        didSet { try? persistence.saveSettings(settings) }
    }

    private let persistence: PersistenceManager

    init(persistence: PersistenceManager = PersistenceManager()) {
        self.persistence = persistence
        self.settings = (try? persistence.loadSettings()) ?? Settings()
    }
}
