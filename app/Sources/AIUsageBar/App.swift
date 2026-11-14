import ServiceManagement
import SwiftUI

@main
struct AIUsageBarApp: App {
    @StateObject private var model = UsageModel()

    init() {
        if CommandLine.arguments.contains("--unregister-login") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(model)
        } label: {
            Text(model.menuLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
