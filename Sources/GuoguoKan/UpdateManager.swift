import Sparkle
import SwiftUI

@MainActor
final class UpdateManager {
    static let shared = UpdateManager()
    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    func check() { controller.checkForUpdates(nil) }
}
