import KortexCloud
import KortexKit
import SwiftUI

@main
struct KortexApp: App {
    @State private var model = AppModel()
    @State private var session: CloudSession

    init() {
        KortexFonts.register()
        Cloud.configure()
        let session = CloudSession()
        session.start()
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup("Kortex") {
            RootView(model: model, session: session)
                .frame(minWidth: 1024, minHeight: 680)
                .onOpenURL { Cloud.handle($0) }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            SidebarCommands()
            GoCommands(model: model)
            NewEntryCommands(model: model, enabled: session.user != nil)
            // File › Import from iPhone: Continuity Camera photos arrive as receipts.
            ImportFromDevicesCommands()
            CommandGroup(after: .appSettings) {
                Button("Sign Out") { session.signOut() }
                    .disabled(session.user == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
