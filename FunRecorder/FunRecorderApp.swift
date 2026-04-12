import SwiftUI
import SwiftData

@main
struct FunRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Loading…")
        }
        .modelContainer(for: Clip.self)
    }
}
