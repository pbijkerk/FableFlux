import Foundation
import Observation
import SwiftData
import OSLog

@MainActor
@Observable
class FeedRefreshService {
    var isRefreshing = false
    var lastError: String?

    /// De lopende volledige refresh, zodat een tweede aanroep erop kan wachten
    /// in plaats van een eigen ronde te starten.
    private var activeRefresh: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: AppConfiguration.LogSubsystem.main,
        category: AppConfiguration.LogSubsystem.Category.feed
    )

    /// Een tweede aanroep start geen tweede ronde maar wacht op de lopende. Twee rondes
    /// zouden dezelfde feeds parallel schrijven; vroegtijdig terugkeren zou de aanroeper
    /// laten clusteren op data die nog binnenkomt.
    func refreshAll(feeds: [Feed], context: ModelContext) async {
        if let activeRefresh {
            Self.logger.info("Refresh already in progress, awaiting the running one")
            await activeRefresh.value
            return
        }

        let task = Task { await performRefreshAll(feeds: feeds, context: context) }
        activeRefresh = task
        await task.value
        activeRefresh = nil
    }

    // Each refresh gets its own parser instance — no shared mutable state
    private func performRefreshAll(feeds: [Feed], context: ModelContext) async {
        isRefreshing = true
        lastError = nil

        Self.logger.info("Starting refresh of \(feeds.count) feeds")

        // Parallel refresh voor betere performance, met limiet
        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0

            for feed in feeds {
                // Wacht als we de limiet hebben bereikt
                if activeCount >= AppConfiguration.maxParallelRefreshes {
                    await group.next()
                    activeCount -= 1
                }

                group.addTask { @MainActor in
                    await self.refresh(feed: feed, context: context)
                }
                activeCount += 1
            }

            // Wacht tot alle tasks klaar zijn
            await group.waitForAll()
        }

        // Mastodon accounts ook vernieuwen (sequentieel om rate limiting te respecteren)
        let mastodonDescriptor = FetchDescriptor<MastodonAccount>()
        let accounts = (try? context.fetch(mastodonDescriptor)) ?? []

        Self.logger.info("Refreshing \(accounts.count) Mastodon accounts")

        var allErrors: [String] = []
        for account in accounts {
            guard let feed = account.feed else { continue }
            do {
                try await MastodonService.shared.refreshFeed(account: account, feed: feed, context: context)
            } catch let e as MastodonError {
                Self.logger.error("Mastodon refresh failed: \(e.localizedDescription ?? "Unknown error")")
                if case .httpError(let code, _) = e, code == 401 {
                    account.needsReauth = true
                    try? context.save()
                }
                allErrors.append(e.errorDescription ?? "Onbekende fout")
            } catch {
                Self.logger.error("Mastodon refresh failed: \(error.localizedDescription)")
                allErrors.append("Mastodon: \(error.localizedDescription)")
            }
        }
        lastError = allErrors.isEmpty ? nil : allErrors.joined(separator: "; ")

        Self.logger.info("Refresh completed")
        isRefreshing = false
    }

    func refresh(feed: Feed, context: ModelContext) async {
        if feed.isMastodonFeed {
            await refreshMastodonFeed(feed, context: context)
            return
        }
        guard let url = URL(string: feed.url) else {
            Self.logger.warning("Invalid feed URL: \(feed.url)")
            return
        }

        do {
            Self.logger.debug("Fetching feed: \(feed.title)")
            let (data, _) = try await URLSession.shared.data(from: url)

            // Parse on a background thread with a fresh parser, return plain structs
            let parsed: ParsedFeed = try await Task.detached(priority: .utility) {
                RSSParser().parse(data: data)
            }.value

            // All model mutations back on MainActor (we already are, but explicit for clarity)
            applyParsedFeed(parsed, to: feed, context: context)
            try context.save()

            Self.logger.info("Successfully refreshed feed: \(feed.title)")

        } catch {
            Self.logger.error("Failed to refresh \(feed.title): \(error.localizedDescription)")
            lastError = "Failed to refresh \(feed.title): \(error.localizedDescription)"
        }
    }

    /// All writes to SwiftData happen here, synchronously on MainActor.
    func applyParsedFeed(_ parsed: ParsedFeed, to feed: Feed, context: ModelContext) {
        if feed.title == "New Feed" || feed.title.isEmpty, !parsed.title.isEmpty {
            feed.title = parsed.title
        }
        if feed.feedDescription == nil || feed.feedDescription?.isEmpty == true,
            !parsed.description.isEmpty
        {
            feed.feedDescription = parsed.description
        }

        let existing = Self.existingKeys(of: feed, context: context)
        var existingGuids = Set(existing.compactMap { $0.guid.map(Self.guidKey) })
        var existingLinks = Set(existing.compactMap { $0.link })
        var existingTitles = Set(existing.map { $0.title })

        var newItems: [FeedItem] = []
        for parsedItem in parsed.items {
            // De sets groeien mee, zodat een artikel dat twee keer in dezelfde feed staat
            // ook binnen één verversing maar één keer binnenkomt (#135).
            let isNew: Bool
            if !parsedItem.guid.isEmpty {
                isNew = existingGuids.insert(Self.guidKey(parsedItem.guid)).inserted
            } else if !parsedItem.link.isEmpty {
                isNew = existingLinks.insert(parsedItem.link).inserted
            } else {
                isNew = existingTitles.insert(parsedItem.title).inserted
            }

            guard isNew else { continue }

            let item = FeedItem(
                title: parsedItem.title,
                link: parsedItem.link.isEmpty ? nil : parsedItem.link,
                itemDescription: parsedItem.description.isEmpty ? nil : parsedItem.description,
                pubDate: parsedItem.pubDate,
                guid: parsedItem.guid.isEmpty ? nil : parsedItem.guid,
                enclosureURL: parsedItem.enclosureURL,
                enclosureMIMEType: parsedItem.enclosureMIMEType,
                imageURL: parsedItem.imageURL
            )
            item.feed = feed
            context.insert(item)
            newItems.append(item)
        }
        // Eén append voor alle nieuwe artikelen, zodat de relatie één keer wijzigt en
        // waarnemers van `feed.items` bijwerken.
        if !newItems.isEmpty {
            feed.items.append(contentsOf: newItems)
        }

        // Rijen die vóór deze controle zijn opgeslagen dragen hun onwaarschijnlijke datum
        // nog; zonder deze stap blijven ze bovenaan staan tot de gebruiker de feed verwijdert.
        Self.clearImplausibleDates(feed: feed, context: context)

        // Verwijder artikelen die ouder zijn dan de bewaarperiode
        Self.pruneOldItems(feed: feed, context: context)

        feed.lastRefreshed = Date()

        // Pas bronbeoordeling toe als nog niet beoordeeld of ouder dan 30 dagen
        let ratingAge = feed.biasRatedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if ratingAge > 30 * 24 * 3_600 {
            SourceRatingService.shared.applyRating(to: feed)
        }

        // Auto-assign to system folder if not already in a folder
        if feed.folder == nil {
            detectAndAssignFolder(feed: feed, parsed: parsed, context: context)
        }
    }

    /// De vergelijkingssleutel voor een `guid`: bij een http(s)-URL zonder het fragment na
    /// `#`. De BBC zet hetzelfde artikel meermaals in de feed als `…/cwywld5v28jo#1` en
    /// `…#9`, en dat getal wisselt in de loop van de dag (#135). Bewust niet op `link`
    /// ontdubbelen: veel podcastfeeds geven elk item dezelfde link (de homepage), en dan
    /// zou elke nieuwe aflevering als dubbel worden weggegooid. De opgeslagen `guid`
    /// zelf blijft ongewijzigd.
    static func guidKey(_ guid: String) -> String {
        let lower = guid.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://"),
            let hash = guid.firstIndex(of: "#")
        else { return guid }
        return String(guid[..<hash])
    }

    /// De bestaande artikelen van een feed in één query (#119). Via `feed.items` werd elk
    /// artikel afzonderlijk uit SQLite gehaald: bij 57 feeds duizenden losse queries per
    /// verversing. Bewust volledige rijen, geen `propertiesToFetch`: de `append` op
    /// `feed.items` hieronder laadt anders alsnog elk artikel apart. Die append is nodig,
    /// want alleen een wijziging via `feed.items` laat schermen die de relatie tonen
    /// (zoals `FeedItemsView`) opnieuw tekenen.
    /// Mislukt de fetch, dan valt dit terug op `feed.items`: liever traag dan dat elk
    /// bestaand artikel als nieuw wordt gezien en dubbel binnenkomt.
    static func existingKeys(of feed: Feed, context: ModelContext) -> [FeedItem] {
        let feedID = feed.id
        let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.feed?.id == feedID })
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Fetch van bestaande artikelen mislukt voor \(feed.title): \(error.localizedDescription)")
            return feed.items
        }
    }

    /// Wist een publicatiedatum die ver in de toekomst ligt. De parser weert zulke datums
    /// sinds #103, maar artikelen die er al mee in de database staan komen anders bij elke
    /// verversing terug: ze sorteren bovenaan en de bewaarperiode raakt ze nooit.
    /// Het artikel zelf blijft staan en valt terug op `fetchedAt`.
    /// Haalt alleen de betrokken artikelen op in plaats van de hele feed te doorlopen (#119);
    /// de grens is dezelfde als in `RSSParser.isPlausiblePublicationDate`.
    static func clearImplausibleDates(feed: Feed, context: ModelContext, now: Date = Date()) {
        let feedID = feed.id
        let limit = now.addingTimeInterval(AppConfiguration.maxFutureDateSkew)
        let distantPast = Date.distantPast
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { item in
                item.feed?.id == feedID && (item.pubDate ?? distantPast) > limit
            }
        )
        let items: [FeedItem]
        do {
            items = try context.fetch(descriptor)
        } catch {
            Self.logger.error(
                "Fetch van onwaarschijnlijke datums mislukt voor \(feed.title): \(error.localizedDescription)")
            return
        }
        for item in items {
            guard let date = item.pubDate,
                !RSSParser.isPlausiblePublicationDate(date, now: now)
            else { continue }
            Self.logger.warning("Onwaarschijnlijke publicatiedatum gewist: \(item.title, privacy: .public)")
            item.pubDate = nil
            if item.fetchedAt == nil { item.fetchedAt = now }
        }
    }

    /// Verwijdert artikelen ouder dan de effectieve bewaarperiode (feed-instelling of globale standaard).
    /// Static, zodat `MastodonService` dezelfde logica kan aanroepen zonder een eigen
    /// instantie te maken: die houdt `isRefreshing`/`lastError` bij en hoort bij een scherm.
    /// `now` is injecteerbaar zodat het opruimen toetsbaar is zonder van de echte klok
    /// af te hangen; in de app blijft het gewoon "nu".
    static func pruneOldItems(feed: Feed, context: ModelContext, now: Date = Date()) {
        let globalDefault =
            UserDefaults.standard.object(
                forKey: AppConfiguration.UserDefaultsKeys.retentionDays
            ) as? Int ?? AppConfiguration.defaultRetentionDays

        let effective = feed.retentionDays ?? globalDefault
        guard effective > 0 else { return }

        guard let cutoff = Calendar.current.date(byAdding: .day, value: -effective, to: now) else {
            Self.logger.warning("Failed to calculate cutoff date for pruning")
            return
        }

        // `effectiveDate` valt terug op `fetchedAt`, zodat een artikel zonder publicatie-
        // datum ook opruimbaar is. Rijen van vóór #89 hebben geen van beide; die blijven
        // staan (`.distantFuture`), zodat er niets onverwachts verdwijnt.
        // Het predicaat is `effectiveDate` uitgeschreven, zodat alleen de te verwijderen
        // artikelen worden opgehaald in plaats van de hele feed (#119).
        let feedID = feed.id
        let distantFuture = Date.distantFuture
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { item in
                item.feed?.id == feedID && !item.isSaved
                    && (item.pubDate ?? item.fetchedAt ?? distantFuture) < cutoff
            }
        )
        // De cascade naar factchecks laadt anders per verwijderd artikel een eigen query.
        descriptor.relationshipKeyPathsForPrefetching = [\.factCheckResults]
        let toDelete: [FeedItem]
        do {
            toDelete = try context.fetch(descriptor)
        } catch {
            Self.logger.error("Fetch voor opruimen mislukt voor \(feed.title): \(error.localizedDescription)")
            return
        }

        if !toDelete.isEmpty {
            Self.logger.debug("Pruning \(toDelete.count) old items from \(feed.title)")
        }

        // Vergelijken op `persistentModelID`: dat kent SwiftData zonder de rij te laden.
        // Bij verversen zijn de artikelen al geladen door `existingKeys`; de `removeAll`
        // is nodig zodat schermen die `feed.items` tonen bijwerken.
        let deletedIDs = Set(toDelete.map(\.persistentModelID))
        for item in toDelete {
            context.delete(item)
        }
        if !deletedIDs.isEmpty {
            feed.items.removeAll { deletedIDs.contains($0.persistentModelID) }
        }
    }

    private func detectAndAssignFolder(feed: Feed, parsed: ParsedFeed, context: ModelContext) {
        let mediaType = detectMediaType(url: feed.url, parsed: parsed)
        guard mediaType != .unknown else { return }
        let folderName = mediaType == .video ? "Video" : "Audio"
        feed.folder = getOrCreateSystemFolder(name: folderName, context: context)
    }

    private func detectMediaType(url: String, parsed: ParsedFeed) -> FeedMediaType {
        let lower = url.lowercased()
        let videoPatterns = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com"]
        let audioPatterns = [
            "anchor.fm", "buzzsprout.com", "libsyn.com", "transistor.fm",
            "podbean.com", "spreaker.com", "simplecast.com", "megaphone.fm",
        ]
        if videoPatterns.contains(where: { lower.contains($0) }) { return .video }
        if audioPatterns.contains(where: { lower.contains($0) }) { return .audio }
        return parsed.detectedMediaType
    }

    private func getOrCreateSystemFolder(name: String, context: ModelContext) -> FeedFolder {
        let descriptor = FetchDescriptor<FeedFolder>(
            predicate: #Predicate { $0.name == name && $0.isSystem == true }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let allDescriptor = FetchDescriptor<FeedFolder>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? context.fetch(allDescriptor).first?.sortOrder) ?? -1
        let folder = FeedFolder(name: name, sortOrder: maxOrder + 1, isSystem: true)
        context.insert(folder)
        return folder
    }

    private func refreshMastodonFeed(_ feed: Feed, context: ModelContext) async {
        // Fetch all Mastodon accounts en filter in-memory
        // (Predicates met optional relationships zijn complex in SwiftData)
        let descriptor = FetchDescriptor<MastodonAccount>()

        guard let accounts = try? context.fetch(descriptor),
            let account = accounts.first(where: { $0.feed?.url == feed.url })
        else {
            Self.logger.warning("No Mastodon account found for feed: \(feed.url)")
            return
        }

        do {
            try await MastodonService.shared.refreshFeed(account: account, feed: feed, context: context)
        } catch let e as MastodonError {
            Self.logger.error("Mastodon feed refresh failed: \(e.localizedDescription ?? "Unknown")")
            if case .httpError(let code, _) = e, code == 401 {
                account.needsReauth = true
                try? context.save()
            }
            lastError = e.errorDescription
        } catch {
            Self.logger.error("Mastodon feed refresh failed: \(error.localizedDescription)")
            lastError = "Mastodon: \(error.localizedDescription)"
        }
    }

    func fetchFeedTitle(url: String) async throws -> String {
        guard let feedURL = URL(string: url) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parsed = try await Task.detached(priority: .utility) {
            RSSParser().parse(data: data)
        }.value
        return parsed.title.isEmpty ? url : parsed.title
    }
}
