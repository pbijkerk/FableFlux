import SwiftData
import Foundation

@Model
final class MastodonAccount {
    var instanceURL: String  // e.g. "https://fosstodon.org"
    var accountID: String  // Mastodon numeriek account-ID
    var username: String  // e.g. "alice"
    var displayName: String
    var avatarURL: String
    var clientID: String
    var clientSecret: String
    var accessToken: String
    var needsReauth: Bool = false  // true na 401 fout
    var lastFetchedStatusID: String?  // cursor voor min_id paginering
    var lastRefreshed: Date?
    var createdAt: Date

    @Relationship(deleteRule: .nullify)
    var feed: Feed?

    init(
        instanceURL: String, accountID: String, username: String,
        displayName: String, avatarURL: String,
        clientID: String, clientSecret: String, accessToken: String
    ) {
        self.instanceURL = instanceURL
        self.accountID = accountID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.createdAt = Date()
    }
}
