import SwiftUI

@main
struct OllamaBarApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(viewModel)
        } label: {
            MenuBarIconView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
