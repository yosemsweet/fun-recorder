import SwiftUI
import SwiftData

@main
struct FunRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Clip.self)
    }
}
