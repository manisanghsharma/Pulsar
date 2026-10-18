import SwiftUI

@main
struct PulsarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Pulsar", id: "main") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: model.clicking || model.playing ? "cursorarrow.click.badge.clock" : "cursorarrow.rays")
        }
    }
}
