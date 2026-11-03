import SwiftUI
import AVFoundation

@main
struct MeowApp: App {
    init() {
        // Let the built-in music player keep playing with the screen locked / silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
    }
}
