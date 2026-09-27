import SwiftUI
import SwiftData
import SafariServices
import Observation

// MARK: - Safari browser wrapper (volledige Safari → geen cookie-beperkingen)

struct SafariBrowserView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        @Binding var isPresented: Bool
        private var callbackObserver: Any?

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
            super.init()
            // Sluit het venster zodra de callback is ontvangen
            callbackObserver = NotificationCenter.default.addObserver(
                forName: .oauthCallbackReceived, object: nil, queue: .main
            ) { [weak self] _ in
                self?.isPresented = false
            }
        }

        deinit {
            if let obs = callbackObserver { NotificationCenter.default.removeObserver(obs) }
        }

        @MainActor func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            // Gebruiker sluit browser handmatig → annuleer de OAuth-aanvraag
            OAuthCallbackHandler.shared.cancel()
            isPresented = false
        }
    }
}

// MARK: - View model

@Observable
final class MastodonSetupViewModel {

    enum SetupState: Equatable {
        static func == (lhs: SetupState, rhs: SetupState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.registering, .registering),
                (.waitingForOAuth, .waitingForOAuth), (.exchangingToken, .exchangingToken),
                (.verifyingCredentials, .verifyingCredentials), (.saving, .saving):
                return true
            case (.success(let a1, let b1), .success(let a2, let b2)): return a1 == a2 && b1 == b2
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }

        case idle
        case registering
        case waitingForOAuth
        case exchangingToken
        case verifyingCredentials
        case saving
        case success(username: String, instance: String)
        case error(String)
    }

    var instanceURLText = ""
    var state: SetupState = .idle
    var showSafari = false
    var pendingOAuthURL: URL?

    // MARK: - Connect flow

    @MainActor
    func connect(context: ModelContext) async {
        let normalized = normalize(instanceURLText)
        guard !normalized.isEmpty, URL(string: normalized) != nil else {
            state = .error("Ongeldig instantie-adres. Gebruik bijv. 'fosstodon.org'.")
            return
        }

        do {
            state = .registering
            let reg = try await MastodonService.shared.registerApp(instanceURL: normalized)

            state = .waitingForOAuth
            let authURL = try MastodonService.shared.buildAuthorizeURL(
                instanceURL: normalized, clientID: reg.clientId)
            let code = try await launchOAuthSession(url: authURL)

            state = .exchangingToken
            let token = try await MastodonService.shared.exchangeToken(
                instanceURL: normalized, clientID: reg.clientId,
                clientSecret: reg.clientSecret, code: code)

            state = .verifyingCredentials
            let creds = try await MastodonService.shared.verifyCredentials(
                instanceURL: normalized, accessToken: token.accessToken)

            state = .saving
            try persistAccount(normalized, reg: reg, token: token, creds: creds, context: context)

            let host = URL(string: normalized)?.host ?? normalized
            state = .success(username: creds.username, instance: host)

        } catch let e as MastodonError {
            if case .oauthCancelled = e {
                state = .idle
            } else {
                state = .error(e.errorDescription ?? "Onbekende fout")
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - OAuth via SFSafariViewController

    @MainActor
    private func launchOAuthSession(url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            OAuthCallbackHandler.shared.setPendingContinuation(continuation)
            pendingOAuthURL = url
            showSafari = true
        }
    }

    // MARK: - Persisteren

    private func persistAccount(
        _ instanceURL: String, reg: MastodonAppRegistration,
        token: MastodonToken, creds: MastodonVerifyCredentials,
        context: ModelContext
    ) throws {
        let socialFolder = findOrCreateSocialFolder(context: context)

        let account = MastodonAccount(
            instanceURL: instanceURL,
            accountID: creds.id,
            username: creds.username,
            displayName: creds.displayName,
            avatarURL: creds.avatar,
            clientID: reg.clientId,
            clientSecret: "",  // niet in SwiftData opslaan; clientSecret is alleen nodig tijdens setup
            accessToken: ""  // niet in SwiftData opslaan; token staat uitsluitend in Keychain
        )
        context.insert(account)

        // Token veilig opslaan in Keychain (via MastodonService — Services-laag)
        MastodonService.shared.saveToken(token.accessToken, instanceURL: instanceURL, accountID: creds.id)

        let host = URL(string: instanceURL)?.host ?? instanceURL
        let feedURL = "mastodon://\(host)/@\(creds.username)"
        let feedTitle = "\(creds.displayName) (@\(creds.username)@\(host))"
        let virtualFeed = Feed(url: feedURL, title: feedTitle)
        virtualFeed.folder = socialFolder
        context.insert(virtualFeed)
        account.feed = virtualFeed

        try context.save()
    }

    private func findOrCreateSocialFolder(context: ModelContext) -> FeedFolder {
        let descriptor = FetchDescriptor<FeedFolder>(
            predicate: #Predicate { $0.isSystem == true && $0.name == "Social" }
        )
        if let existing = try? context.fetch(descriptor).first { return existing }

        let allDesc = FetchDescriptor<FeedFolder>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let maxOrder = (try? context.fetch(allDesc).first?.sortOrder) ?? -1
        let folder = FeedFolder(name: "Social", sortOrder: maxOrder + 1, isSystem: true)
        context.insert(folder)
        return folder
    }

    // MARK: - Helpers

    private func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    var stateLabel: String {
        switch state {
        case .idle: return ""
        case .registering: return "App registreren bij instantie…"
        case .waitingForOAuth: return "Wacht op inloggen…"
        case .exchangingToken: return "Toegangstoken ophalen…"
        case .verifyingCredentials: return "Account verifiëren…"
        case .saving: return "Opslaan…"
        case .success: return ""
        case .error: return ""
        }
    }

    var isWorking: Bool {
        switch state {
        case .registering, .waitingForOAuth, .exchangingToken, .verifyingCredentials, .saving: return true
        default: return false
        }
    }
}

// MARK: - View

struct MastodonSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = MastodonSetupViewModel()

    var body: some View {
        @Bindable var vm = viewModel
        return NavigationStack {
            Form {
                Section {
                    TextField("bijv. fosstodon.org", text: $vm.instanceURLText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(viewModel.isWorking)
                } header: {
                    Text("Mastodon instantie")
                } footer: {
                    Text("Vul het domein van jouw Mastodon-instantie in.")
                }

                Section {
                    switch viewModel.state {
                    case .idle, .error:
                        Button {
                            Task { await viewModel.connect(context: modelContext) }
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("Verbinden met Mastodon")
                            }
                        }
                        .disabled(viewModel.instanceURLText.trimmingCharacters(in: .whitespaces).isEmpty)

                    case .success(let username, let instance):
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Verbonden")
                                    .font(.headline)
                                Text("@\(username)@\(instance)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                    default:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(viewModel.stateLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if case .error(let msg) = viewModel.state {
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mastodon toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleren") { dismiss() }
                        .disabled(viewModel.isWorking)
                }
                if case .success = viewModel.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Gereed") { dismiss() }
                    }
                }
            }
            // SFSafariViewController — volledige Safari-cookies, geen CSRF-problemen
            .fullScreenCover(isPresented: $vm.showSafari) {
                if let url = viewModel.pendingOAuthURL {
                    SafariBrowserView(url: url, isPresented: $vm.showSafari)
                        .ignoresSafeArea()
                }
            }
        }
    }
}
