import ServiceManagement
import SwiftUI

@main
struct AISpendBarApp: App {
    @StateObject private var model = UsageModel()

    init() {
        if CommandLine.arguments.contains("--unregister-login") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.run(to: URL(fileURLWithPath: args[i + 1])) }
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
