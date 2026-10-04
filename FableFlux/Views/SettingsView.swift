import SwiftUI
import SwiftData

private let retentionOptions: [(label: String, days: Int)] = [
    ("1 dag", 1),
    ("2 dagen", 2),
    ("7 dagen", 7),
    ("14 dagen", 14),
    ("30 dagen", 30),
    ("60 dagen", 60),
    ("90 dagen", 90),
    ("180 dagen", 180),
    ("1 jaar", 365),
    ("Nooit", 0),
]

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var mastodonAccounts: [MastodonAccount]

    /// API-sleutels uit Keychain — geladen via .onAppear, opgeslagen via .onChange
    @State private var claudeAPIKey = ""
    @State private var googleFactCheckAPIKey = ""

    /// Status van de Claude-sleutelvalidatie — niet persistent, opnieuw bepaald bij
    /// verschijnen en bij elke (gedebouncede) wijziging van het sleutelveld.
    @State private var claudeKeyStatus: ClaudeKeyStatus = .noKey
    /// Lopende validatietaak; wordt gecancelled bij een nieuwe toetsaanslag (debounce).
    @State private var claudeValidationTask: Task<Void, Never>?

    /// Vier standen van de sleutelvalidatie-indicator.
    private enum ClaudeKeyStatus {
        case noKey  // geen sleutel → neutrale "lokale samenvattingen"
        case validating  // bezig met valideren
        case valid  // sleutel geldig → groen "AI-samenvattingen actief"
        case invalid  // 401/403 → foutstatus
        case couldNotValidate  // netwerk-/overige fout → neutrale "kon niet valideren"
    }

    @AppStorage(AppConfiguration.UserDefaultsKeys.retentionDays)
    private var defaultRetentionDays = AppConfiguration.defaultRetentionDays

    @AppStorage(AppConfiguration.UserDefaultsKeys.hideReadArticles) private var hideReadArticles = false
    @AppStorage(AppConfiguration.UserDefaultsKeys.feedCountMode) private var feedCountMode = "total"
    @AppStorage(AppConfiguration.UserDefaultsKeys.previewLineCount) private var previewLineCount = 2
    @AppStorage(AppConfiguration.UserDefaultsKeys.showArticleThumbnails) private var showArticleThumbnails = true
    @AppStorage(AppConfiguration.UserDefaultsKeys.articleLoadLimit)
    private var articleLoadLimit = AppConfiguration.defaultArticleLoadLimit

    @AppStorage(AppConfiguration.UserDefaultsKeys.feedListScale)
    private var feedListScale = AppConfiguration.defaultFeedListScale

    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontSize)
    private var articleFontSize = AppConfiguration.defaultArticleFontSize

    @AppStorage(AppConfiguration.UserDefaultsKeys.articleFontFamily)
    private var articleFontFamily = AppConfiguration.defaultArticleFontFamily

    @AppStorage(AppConfiguration.UserDefaultsKeys.summaryLanguage)
    private var summaryLanguage = "nl"

    @AppStorage(AppConfiguration.UserDefaultsKeys.summaryLength)
    private var summaryLength = AppConfiguration.defaultSummaryLength

    @AppStorage(AppConfiguration.UserDefaultsKeys.showBiasIndicators)
    private var showBiasIndicators = true

    @AppStorage(AppConfiguration.UserDefaultsKeys.analysisTextSize)
    private var analysisTextSize = AppConfiguration.defaultAnalysisTextSize

    @AppStorage(AppConfiguration.UserDefaultsKeys.appTheme)
    private var appTheme = AppTheme.standaard.rawValue
    /// Melding als iOS het app-icoon niet kon wisselen; de accentkleur is dan wel gewijzigd.
    @State private var iconFout: String?
    /// Lopende icoonwissel; een volgende wissel wacht hierop.
    @State private var iconTask: Task<Void, Never>?

    @State private var showAPIKey = false
    @State private var showGoogleKey = false
    @State private var showMastodonSetup = false
    @State private var showingClaudeConsole = false
    @State private var opslagFout: OpslagFoutmelding?

    // MARK: - Percentage-state (uniforme tekstgrootte-regelaars)
    //
    // De sliders werken op lokale @State-percentages als bron van waarheid.
    // Direct terugrekenen vanuit de opgeslagen pt-waarde zou de slider na
    // loslaten laten verspringen (85% → 14pt → 82%); met lokale state op het
    // 5%-raster blijft de thumb staan waar de gebruiker hem zet.

    @State private var feedListPercent: Double = 100
    @State private var articlePercent: Double = 100
    @State private var analysisPercent: Double = 100

    /// Klemt een ruw percentage binnen het sliderbereik en zet het op het 5%-raster.
    private static func percentOnGrid(_ raw: Double) -> Double {
        let clamped = min(max(raw, 80), 150)
        return (clamped / 5).rounded() * 5
    }

    /// Laadt de drie percentages uit de opgeslagen waarden.
    private func loadPercentages() {
        feedListPercent = Self.percentOnGrid(feedListScale * 100)
        articlePercent = Self.percentOnGrid(
            Double(articleFontSize) / Double(AppConfiguration.defaultArticleFontSize) * 100)
        analysisPercent = Self.percentOnGrid(
            Double(analysisTextSize) / Double(AppConfiguration.defaultAnalysisTextSize) * 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                uiterlijkSection
                weergaveSection
                tekstgrootteSection
                samenvattingenSection
                bronanalyseSection
                bewaarperiodeSection
                onderwerpenSection
                mastodonSection
                overSection
            }
            .navigationTitle("Instellingen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gereed") { dismiss() }
                }
            }
        }
        .appThemeTint()
        .onAppear(perform: loadStoredValues)
        .onDisappear { claudeValidationTask?.cancel() }
        .onChange(of: feedListPercent) { persistFeedListPercent() }
        .onChange(of: articlePercent) { persistArticlePercent() }
        .onChange(of: analysisPercent) { persistAnalysisPercent() }
        .onChange(of: claudeAPIKey) {
            persistClaudeKey()
            scheduleClaudeKeyValidation(debounce: true)
        }
        .onChange(of: googleFactCheckAPIKey) { persistGoogleKey() }
        .opslagFoutmelding($opslagFout)
    }

    // MARK: - Laden & persisteren

    private func loadStoredValues() {
        claudeAPIKey =
            KeychainService.load(forKey: AppConfiguration.KeychainKeys.claudeAPIKey)
            ?? UserDefaults.standard.string(forKey: AppConfiguration.UserDefaultsKeys.claudeAPIKey)
            ?? ""
        googleFactCheckAPIKey = KeychainService.load(forKey: AppConfiguration.KeychainKeys.googleFactCheckAPIKey) ?? ""
        loadPercentages()
        scheduleClaudeKeyValidation(debounce: false)
    }

    private func persistFeedListPercent() {
        feedListScale = feedListPercent / 100
    }

    private func persistArticlePercent() {
        let pt = Double(AppConfiguration.defaultArticleFontSize) * articlePercent / 100
        articleFontSize = Int(pt.rounded())
    }

    private func persistAnalysisPercent() {
        let pt = Double(AppConfiguration.defaultAnalysisTextSize) * analysisPercent / 100
        analysisTextSize = Int(pt.rounded())
    }

    private func persistClaudeKey() {
        // De legacykopie pas weghalen als de Keychain de nieuwe waarde echt heeft; anders
        // is bij een mislukte write de sleutel op beide plekken weg (#124).
        if KeychainService.save(claudeAPIKey, forKey: AppConfiguration.KeychainKeys.claudeAPIKey) {
            UserDefaults.standard.removeObject(forKey: AppConfiguration.UserDefaultsKeys.claudeAPIKey)
        }
    }

    private func persistGoogleKey() {
        KeychainService.save(googleFactCheckAPIKey, forKey: AppConfiguration.KeychainKeys.googleFactCheckAPIKey)
    }

    // MARK: - Claude-sleutelvalidatie

    /// Start (opnieuw) een niet-blokkerende validatie van de Claude-sleutel.
    ///
    /// Cancelt een eventuele lopende taak; bij `debounce` wordt eerst kort gewacht
    /// zodat niet elke toetsaanslag een netwerkverzoek doet. Status-updates lopen
    /// via de `@MainActor`. Een lege sleutel valideert niet en toont de neutrale
    /// "lokale samenvattingen"-status.
    private func scheduleClaudeKeyValidation(debounce: Bool) {
        claudeValidationTask?.cancel()

        let key = claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            claudeKeyStatus = .noKey
            return
        }

        claudeKeyStatus = .validating
        claudeValidationTask = Task { @MainActor in
            if debounce {
                try? await Task.sleep(for: .milliseconds(600))
            }
            guard !Task.isCancelled else { return }

            let result = await ClaudeKeyValidator.validate(apiKey: key)
            guard !Task.isCancelled else { return }

            switch result {
            case .valid: claudeKeyStatus = .valid
            case .invalid: claudeKeyStatus = .invalid
            case .couldNotValidate: claudeKeyStatus = .couldNotValidate
            }
        }
    }

    // MARK: - 0. Uiterlijk

    private var uiterlijkSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    themeButton(theme)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Uiterlijk")
        } footer: {
            Text(iconFout ?? "Kies een logo als app-icoon; de accentkleur van de app past zich aan.")
        }
    }

    private func themeButton(_ theme: AppTheme) -> some View {
        let isSelected = AppTheme(storedValue: appTheme) == theme
        return Button {
            kiesThema(theme)
        } label: {
            VStack(spacing: 6) {
                FableFluxLogo(theme: theme)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 3)
                    }
                Text(theme.naam)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.naam)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func kiesThema(_ theme: AppTheme) {
        let app = UIApplication.shared
        // Ook bij hetzelfde thema opnieuw proberen als het icoon achterloopt (eerdere wissel mislukt).
        guard AppTheme(storedValue: appTheme) != theme || app.alternateIconName != theme.iconName else { return }
        appTheme = theme.rawValue
        iconFout = nil
        guard app.supportsAlternateIcons else { return }
        // Wissels na elkaar uitvoeren: iOS weigert een wissel terwijl de vorige nog loopt.
        let vorige = iconTask
        iconTask = Task {
            await vorige?.value
            // Inmiddels een ander thema gekozen: die wissel volgt, deze overslaan.
            guard AppTheme(storedValue: appTheme) == theme, app.alternateIconName != theme.iconName else { return }
            do {
                try await app.setAlternateIconName(theme.iconName)
            } catch {
                guard AppTheme(storedValue: appTheme) == theme else { return }
                iconFout =
                    "Het app-icoon kon niet worden gewijzigd; de accentkleur is wel aangepast. Tik opnieuw om het nog eens te proberen."
            }
        }
    }

    // MARK: - 1. Weergave

    private var weergaveSection: some View {
        Section {
            Toggle("Verberg gelezen artikelen", isOn: $hideReadArticles)
            Toggle("Toon miniatuurafbeeldingen", isOn: $showArticleThumbnails)
            Picker("Teller per feed", selection: $feedCountMode) {
                Text("Totaal aantal artikelen").tag("total")
                Text("Ongelezen artikelen").tag("unread")
            }
            Stepper("Regels voorvertoning: \(previewLineCount)", value: $previewLineCount, in: 1...5)
            Picker("Artikelen in de lijst", selection: $articleLoadLimit) {
                ForEach(AppConfiguration.articleLoadLimitOptions, id: \.self) { aantal in
                    Text("Hooguit \(aantal)").tag(aantal)
                }
            }
        } header: {
            Text("Weergave")
        } footer: {
            if articleLoadLimit > AppConfiguration.defaultArticleLoadLimit {
                Text("Langere lijsten kunnen minder soepel scrollen.")
            }
        }
    }

    // MARK: - 2. Tekstgrootte

    private var tekstgrootteSection: some View {
        Section {
            TextSizePercentRow(title: "Feeds-lijst", percent: $feedListPercent)
            TextSizePercentRow(title: "Artikelen", percent: $articlePercent)
            TextSizePercentRow(title: "Bronanalyse", percent: $analysisPercent)
            Picker("Lettertype artikelen", selection: $articleFontFamily) {
                Text("Charter").tag("charter")
                Text("SF Pro").tag("system")
                Text("New York").tag("newyork")
                Text("Georgia").tag("georgia")
            }
            Button("Herstel standaardwaarden") {
                feedListPercent = 100
                articlePercent = 100
                analysisPercent = 100
            }
            .foregroundStyle(.tint)
        } header: {
            Text("Tekstgrootte")
        } footer: {
            Text(
                "100% is de standaardgrootte. Alle tekst schaalt daarnaast mee met de iOS-instelling voor tekstgrootte (Dynamic Type)."
            )
        }
    }

    // MARK: - 3. Samenvattingen

    private var samenvattingenSection: some View {
        Section {
            Picker("Taal", selection: $summaryLanguage) {
                Text("Nederlands").tag("nl")
                Text("English").tag("en")
            }
            Picker("Lengte", selection: $summaryLength) {
                ForEach(AppConfiguration.SummaryLength.allCases, id: \.rawValue) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            apiKeyField(
                placeholder: "sk-ant-…",
                text: $claudeAPIKey,
                isVisible: $showAPIKey
            )
            Button("Claude API-sleutel aanvragen") {
                showingClaudeConsole = true
            }
            .foregroundStyle(.tint)
        } header: {
            Text("Samenvattingen")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Met een Claude API-sleutel worden samenvattingen door AI gegenereerd; zonder sleutel lokaal. Sleutels worden veilig opgeslagen in de Keychain en nooit gedeeld."
                )
                claudeKeyStatusLabel
                    .font(.caption)
                    .padding(.top, 2)
            }
        }
        .sheet(isPresented: $showingClaudeConsole) {
            SafariVideoPlayer(url: URL(string: "https://console.anthropic.com")!)
                .ignoresSafeArea()
        }
    }

    // MARK: - 4. Bronanalyse & Fact-check

    private var bronanalyseSection: some View {
        Section {
            Toggle("Toon bronanalyse op artikelkaarten", isOn: $showBiasIndicators)
            apiKeyField(
                placeholder: "AIzaSy…",
                text: $googleFactCheckAPIKey,
                isVisible: $showGoogleKey
            )
        } header: {
            Text("Bronanalyse & Fact-check")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "De bronanalyse toont de politieke positie en betrouwbaarheid van nieuwsbronnen (AllSides, MBFC). Een Google Fact Check API-sleutel activeert claim-verificatie per artikel."
                )
                if !googleFactCheckAPIKey.isEmpty {
                    Label("Fact-check actief", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - 5. Artikelen bewaren

    private var bewaarperiodeSection: some View {
        Section {
            Picker("Standaard bewaarperiode", selection: $defaultRetentionDays) {
                ForEach(retentionOptions, id: \.days) { opt in
                    Text(opt.label).tag(opt.days)
                }
            }
        } header: {
            Text("Artikelen bewaren")
        } footer: {
            Text(
                "Feeds zonder eigen instelling gebruiken deze periode. De instelling gaat in bij de volgende verversing."
            )
        }
    }

    // MARK: - 6. Onderwerpen

    private var onderwerpenSection: some View {
        Section("Onderwerpen") {
            NavigationLink {
                TopicsManagementView()
            } label: {
                Label("Onderwerpen beheren", systemImage: "tag")
            }
        }
    }

    // MARK: - 7. Mastodon

    private var mastodonSection: some View {
        Section("Mastodon") {
            ForEach(mastodonAccounts) { account in
                MastodonAccountRow(account: account)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let account = mastodonAccounts[index]
                    if let feed = account.feed { modelContext.delete(feed) }
                    modelContext.delete(account)
                }
                modelContext.saveOrReport("het Mastodon-account te verwijderen", melding: &opslagFout)
            }

            Button {
                showMastodonSetup = true
            } label: {
                Label("Mastodon-account toevoegen", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showMastodonSetup) {
            MastodonSetupView()
        }
    }

    // MARK: - 8. Over

    private var overSection: some View {
        Section("Over") {
            LabeledContent("App", value: "FableFlux")
            LabeledContent(
                "Versie",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
            )
        }
    }

    /// Statusregel onder de Claude-sleutel — reflecteert het echte validatieresultaat.
    @ViewBuilder
    private var claudeKeyStatusLabel: some View {
        switch claudeKeyStatus {
        case .noKey:
            Label("Lokale samenvattingen", systemImage: "iphone")
                .foregroundStyle(.secondary)
        case .validating:
            Label("Sleutel valideren…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .valid:
            Label("AI-samenvattingen actief", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Label("Sleutel ongeldig of verlopen", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .couldNotValidate:
            Label("Kon niet valideren — controleer je verbinding", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Hulpcomponenten

    /// API-sleutelveld met toon/verberg-knop — gedeeld door Claude- en Google-sleutel.
    private func apiKeyField(placeholder: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack {
            if isVisible.wrappedValue {
                TextField(placeholder, text: text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                SecureField(placeholder, text: text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Uniforme tekstgrootte-regelaar

/// Slider in procenten (80–150%, stap 5%, 100% = standaard) — identiek voor alle tekstgroottes.
private struct TextSizePercentRow: View {
    let title: String
    @Binding var percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Image(systemName: "textformat.size.smaller")
                    .foregroundStyle(.secondary)
                Slider(value: $percent, in: 80...150, step: 5)
                Image(systemName: "textformat.size.larger")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mastodon-accountrij

private struct MastodonAccountRow: View {
    let account: MastodonAccount

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: account.avatarURL)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(account.displayName)
                        .font(.body)
                    if account.needsReauth {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                Text("@\(account.username)@\(URL(string: account.instanceURL)?.host ?? account.instanceURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let last = account.lastRefreshed {
                Text(last, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
