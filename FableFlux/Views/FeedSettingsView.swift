import SwiftUI
import SwiftData

private let feedRetentionOptions: [(label: String, days: Int?)] = [
    ("Gebruik standaard", nil),
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

struct FeedSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultRetentionDays") private var defaultRetentionDays = 30

    let feed: Feed

    /// Lokale kopie van retentionDays voor de Picker (Int? werkt niet direct als Picker-selection).
    @State private var selectedDays: Int? = nil
    @State private var includedInSummary = true
    @State private var opslagFout: OpslagFoutmelding?

    /// Draait een nieuwe clustering-ronde zodat het effect van de schakelaar direct
    /// zichtbaar is op Vandaag.
    var onSummaryInclusionChanged: (() async -> Void)? = nil

    private var effectiveLabel: String {
        feedRetentionOptions.first(where: { $0.days == defaultRetentionDays })?.label
            ?? "\(defaultRetentionDays) dagen"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Feed") {
                        Text(feed.title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    LabeledContent("URL") {
                        Text(feed.url)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }

                Section {
                    Toggle("Meenemen in samenvatting", isOn: $includedInSummary)
                } footer: {
                    Text(
                        includedInSummary
                            ? "Artikelen van deze feed tellen mee in de samenvatting op Vandaag."
                            : "Artikelen van deze feed tellen niet mee in de samenvatting op Vandaag. Ze blijven wel gewoon zichtbaar in Artikelen en Bewaard."
                    )
                    .font(.caption)
                }

                Section {
                    Picker("Bewaarperiode", selection: $selectedDays) {
                        ForEach(feedRetentionOptions, id: \.days.debugDescription) { opt in
                            if let d = opt.days {
                                Text(opt.label).tag(Optional(d))
                            } else {
                                Text("Gebruik standaard (\(effectiveLabel))")
                                    .tag(Optional<Int>.none)
                            }
                        }
                    }
                } header: {
                    Text("Bewaarperiode artikelen")
                } footer: {
                    if selectedDays == nil {
                        Text(
                            "De globale standaard (\(effectiveLabel)) is van toepassing. Wijzig de standaard via Instellingen."
                        )
                        .font(.caption)
                    } else if selectedDays == 0 {
                        Text("Artikelen van deze feed worden nooit automatisch verwijderd.")
                            .font(.caption)
                    } else if let d = selectedDays {
                        Text("Artikelen ouder dan \(d) dagen worden verwijderd bij de volgende verversing.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(feed.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
            }
            .onAppear {
                selectedDays = feed.retentionDays
                includedInSummary = feed.includedInSummary
            }
            .opslagFoutmelding($opslagFout)
        }
    }

    private func save() {
        let inclusionChanged = feed.includedInSummary != includedInSummary

        feed.retentionDays = selectedDays
        feed.includedInSummary = includedInSummary
        // Onmiddellijk opruimen als een kortere periode is ingesteld
        FeedRefreshService.pruneOldItems(feed: feed, context: modelContext)
        guard modelContext.saveOrReport("de feedinstellingen te bewaren", melding: &opslagFout) else { return }
        dismiss()

        // Pas na het opslaan: de samenvatting hoort de nieuwe instelling te weerspiegelen.
        if inclusionChanged, let onSummaryInclusionChanged {
            Task { await onSummaryInclusionChanged() }
        }
    }
}
