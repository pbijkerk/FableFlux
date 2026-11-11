import UIKit

/// Ontvangt de systeemgebeurtenissen die SwiftUI zelf niet doorgeeft (#233): iOS start de
/// app op de achtergrond zodra een podcastdownload klaar is, en verwacht dat de
/// achtergrond-`URLSession` met dezelfde identifier opnieuw wordt aangemaakt.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        PodcastDownloadService.shared.handleBackgroundEvents(
            identifier: identifier, completionHandler: completionHandler)
    }
}
