import Foundation
import ZappaleCore

extension SettingsBackup {
    @MainActor
    static func export(core: AppCore) -> Data {
        export(
            settings: core.settings,
            quicklinks: core.quicklinks?.links ?? [],
            snippets: core.snippets?.snippets ?? [],
            commands: core.commands?.commands ?? []
        )
    }

    @MainActor
    static func `import`(data: Data, core: AppCore) throws {
        try `import`(
            data: data,
            settings: core.settings,
            quicklinks: core.quicklinks,
            snippets: core.snippets,
            commands: core.commands
        )
    }
}
