import SwiftUI
import OctoshotCore

@main
enum OctoshotMain {
    @MainActor
    static func main() async {
        #if DEBUG
        await DiarySnapshotHarness.runIfRequested()
        QuickAccessSnapshotHarness.runIfRequested()
        #endif
        OctoshotApp.main()
    }
}

struct OctoshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings UI is hosted by `SettingsWindowController` (LSUIElement-safe).
        // Keep an empty Settings scene so SwiftUI provides a standard app lifecycle.
        Settings {
            EmptyView()
        }
    }
}
