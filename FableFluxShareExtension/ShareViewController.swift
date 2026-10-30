import SwiftUI
import UIKit

/// `NSExtensionPrincipalClass` van de Share Extension (#201). Omdat Share Extensions geen
/// SwiftUI-`App`-lifecycle hebben, is de principal class een `UIViewController` die de
/// SwiftUI-inhoud embedt via `UIHostingController`.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareExtensionView(extensionContext: extensionContext)
        let hosting = UIHostingController(rootView: shareView)

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
