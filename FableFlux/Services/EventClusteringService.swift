import Foundation

struct EventCluster: Identifiable {
    let id = UUID()
    let headline: String
    let items: [FeedItem]  // gesorteerd op pubDate desc

    var feedCount: Int { Set(items.compactMap { $0.feed?.id }).count }

    var biasScores: [Int] {
        Array(Set(items.compactMap { $0.feed?.biasScore })).sorted()
    }
}

final class EventClusteringService: Sendable {
    static let shared = EventClusteringService()
    private init() {}

    private static let stopWords: Set<String> = [
        // Engels
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from",
        "is", "was", "are", "were", "be", "been", "have", "has", "had", "will", "would", "could",
        "should", "may", "might", "this", "that", "these", "those", "its", "after", "before",
        "about", "into", "than", "more", "also", "not", "all", "over", "says", "said", "after",
        "new", "year", "first", "last", "two", "three", "four", "five", "their", "they", "some",
        // Nederlands
        "de", "het", "een", "en", "of", "maar", "in", "op", "aan", "te", "voor", "van", "met",
        "door", "is", "was", "zijn", "werd", "worden", "heeft", "hebben", "had", "zou", "kan",
        "dit", "dat", "deze", "die", "hij", "zij", "we", "ze", "er", "nog", "wel", "niet", "ook",
        "naar", "dan", "meer", "over", "als", "wordt", "heeft", "zich", "zijn", "haar", "zijn",
        "nog", "wel", "toen", "toch", "weer", "nu", "al", "om", "bij", "uit", "tot", "na", "zo",
    ]

    /// Trekt significante woorden uit een titel.
    func keywords(from title: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            title.lowercased()
                .components(separatedBy: separators)
                .filter { $0.count >= 4 && !Self.stopWords.contains($0) }
        )
    }

    /// Clustert items op specifieke gebeurtenissen.
    /// Alleen clusters met artikelen uit ≥2 verschillende feeds worden teruggegeven.
    func cluster(items: [FeedItem], timeWindowHours: Double = 72) -> [EventCluster] {
        guard items.count >= 2 else { return [] }

        let cutoff = Date().addingTimeInterval(-timeWindowHours * 3_600)
        let candidates = items.filter { ($0.pubDate ?? .distantPast) >= cutoff }
        guard candidates.count >= 2 else { return [] }

        // Voorbereken: keywordsets per artikel
        let keywordSets = candidates.map { keywords(from: $0.title) }
        let n = candidates.count

        // Union-Find
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        for i in 0..<n {
            let setA = keywordSets[i]
            guard !setA.isEmpty else { continue }
            for j in (i + 1)..<n {
                let setB = keywordSets[j]
                guard !setB.isEmpty else { continue }
                let shared = setA.intersection(setB).count
                guard shared > 0 else { continue }
                let minSize = min(setA.count, setB.count)
                // Overlap coëfficiënt: gedeelde woorden t.o.v. de kortste set
                if Double(shared) / Double(minSize) >= 0.4 {
                    let ra = find(i)
                    let rb = find(j)
                    if ra != rb { parent[ra] = rb }
                }
            }
        }

        // Groepeer op root
        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(i) }

        var clusters: [EventCluster] = []
        for (_, indices) in groups {
            let clusterItems = indices.map { candidates[$0] }
            let distinctFeeds = Set(clusterItems.compactMap { $0.feed?.id })
            guard distinctFeeds.count >= 2 else { continue }

            let sorted = clusterItems.sorted {
                ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast)
            }
            clusters.append(
                EventCluster(
                    headline: sorted.first?.title ?? "",
                    items: sorted
                ))
        }

        // Meest recente clusters eerst
        return clusters.sorted {
            ($0.items.first?.pubDate ?? .distantPast) > ($1.items.first?.pubDate ?? .distantPast)
        }
    }
}
