//
//  ColonyModels.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

enum ColonySection: String, CaseIterable, Codable, Identifiable {
    case home
    case messages
    case work
    case crm
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .messages: "Messages"
        case .work: "Tasks"
        case .crm: "CRM"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "square.grid.2x2"
        case .messages: "bubble.left.and.bubble.right"
        case .work: "checklist"
        case .crm: "person.crop.rectangle.stack"
        case .settings: "gearshape"
        }
    }

}

enum WorkspaceSettingsTab: String, CaseIterable, Codable, Identifiable {
    case appearance
    case authentication
    case security
    case members
    case hosting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .authentication: "Auth"
        case .security: "Security"
        case .members: "Members"
        case .hosting: "Hosting"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .appearance: "Appearance"
        case .authentication: "Authentication"
        case .security: "Security"
        case .members: "Members"
        case .hosting: "Self-hosting"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette"
        case .authentication: "lock.shield"
        case .security: "checkmark.shield"
        case .members: "person.2"
        case .hosting: "server.rack"
        }
    }
}

enum ColonyTheme: String, CaseIterable, Codable, Identifiable {
    case system
    case ocean
    case forest
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .graphite: "Graphite"
        }
    }

    var accentColor: Color {
        colorToken.color
    }

    var colorToken: ColonyColorToken {
        switch self {
        case .system: .blue
        case .ocean: .cyan
        case .forest: .green
        case .graphite: .gray
        }
    }
}

enum ColonyColorToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case blue
    case cyan
    case green
    case gray
    case indigo
    case orange
    case purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .cyan: .cyan
        case .green: .green
        case .gray: .gray
        case .indigo: .indigo
        case .orange: .orange
        case .purple: .purple
        }
    }
}

enum ProfileAvatarStyle: String, Codable {
    case text
    case image
}

struct ProfilePreferences: Codable, Equatable {
    var displayName: String
    var role: WorkspaceRole
    var avatarStyle: ProfileAvatarStyle
    var avatarText: String
    var avatarColor: ColonyColorToken
    var avatarImageData: Data?

    static let `default` = ProfilePreferences(
        displayName: "Yoav Peretz",
        role: .admin,
        avatarStyle: .text,
        avatarText: "YP",
        avatarColor: .blue,
        avatarImageData: nil
    )
}

enum AppearanceDensity: String, CaseIterable, Codable, Identifiable {
    case compact
    case comfortable
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        case .spacious: "Spacious"
        }
    }

    var detail: String {
        switch self {
        case .compact: "Tighter rows for dense teams and operations."
        case .comfortable: "Balanced spacing for daily workspace use."
        case .spacious: "Larger breathing room for focused review."
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .compact: 18
        case .comfortable: 24
        case .spacious: 30
        }
    }

    var contentPadding: CGFloat {
        switch self {
        case .compact: 18
        case .comfortable: 24
        case .spacious: 30
        }
    }
}

struct AppearancePreferences: Codable, Equatable {
    var density: AppearanceDensity
    var showsSidebarThemePicker: Bool
    var usesHighContrastAccents: Bool

    static let `default` = AppearancePreferences(
        density: .comfortable,
        showsSidebarThemePicker: true,
        usesHighContrastAccents: false
    )
}

enum TaskStatus: String, CaseIterable, Codable, Identifiable {
    case planned
    case active
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: "Planned"
        case .active: "Active"
        case .review: "Review"
        }
    }

    var systemImage: String {
        switch self {
        case .planned: "circle"
        case .active: "circle.lefthalf.filled"
        case .review: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .planned: .secondary
        case .active: .blue
        case .review: .green
        }
    }
}

enum WorkspaceRole: String, CaseIterable, Codable, Identifiable {
    case admin
    case member
    case guest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: "Admin"
        case .member: "Member"
        case .guest: "Guest"
        }
    }
}

enum AuthProviderKind: String, CaseIterable, Codable, Identifiable {
    case email
    case google
    case microsoft
    case github
    case oidc
    case saml
    case passkey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: "Email"
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .github: "GitHub"
        case .oidc: "OIDC"
        case .saml: "SAML"
        case .passkey: "Passkey"
        }
    }

    var systemImage: String {
        switch self {
        case .email: "envelope"
        case .google: "g.circle"
        case .microsoft: "building.2"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .oidc: "key"
        case .saml: "lock.rectangle.stack"
        case .passkey: "person.badge.key"
        }
    }
}

enum AuthProviderStatus: String, CaseIterable, Codable, Identifiable {
    case enabled
    case planned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enabled: "Enabled"
        case .planned: "Planned"
        }
    }
}

enum ColonyChannelKind: String, Codable {
    case channel
    case directMessage
}

struct ColonyChannel: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let kind: ColonyChannelKind
    var unreadCount: Int
    var messages: [ColonyMessage]

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        kind: ColonyChannelKind = .channel,
        unreadCount: Int,
        messages: [ColonyMessage]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.kind = kind
        self.unreadCount = unreadCount
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case kind
        case unreadCount
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decode(String.self, forKey: .description),
            kind: try container.decodeIfPresent(ColonyChannelKind.self, forKey: .kind) ?? .channel,
            unreadCount: try container.decode(Int.self, forKey: .unreadCount),
            messages: try container.decode([ColonyMessage].self, forKey: .messages)
        )
    }

    static func == (lhs: ColonyChannel, rhs: ColonyChannel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ColonyMessage: Codable, Identifiable, Hashable {
    let id: UUID
    let author: String
    let time: String
    let body: String
    let authorColor: ColonyColorToken

    init(
        id: UUID = UUID(),
        author: String,
        time: String,
        body: String,
        authorColor: ColonyColorToken
    ) {
        self.id = id
        self.author = author
        self.time = time
        self.body = body
        self.authorColor = authorColor
    }
}

struct ColonyTask: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let owner: String
    let priority: String
    let category: String
    let dueDate: String
    var status: TaskStatus

    init(
        id: UUID = UUID(),
        title: String,
        owner: String,
        priority: String,
        category: String = "General",
        dueDate: String = "Sep 17, 2025",
        status: TaskStatus
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.priority = priority
        self.category = category
        self.dueDate = dueDate
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case owner
        case priority
        case category
        case dueDate
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try container.decode(String.self, forKey: .title),
            owner: try container.decode(String.self, forKey: .owner),
            priority: try container.decode(String.self, forKey: .priority),
            category: try container.decodeIfPresent(String.self, forKey: .category) ?? "General",
            dueDate: try container.decodeIfPresent(String.self, forKey: .dueDate) ?? "Sep 17, 2025",
            status: try container.decode(TaskStatus.self, forKey: .status)
        )
    }
}

struct ColonyContact: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let company: String
    var stage: String
    let initials: String
    let color: ColonyColorToken

    init(
        id: UUID = UUID(),
        name: String,
        company: String,
        stage: String,
        initials: String,
        color: ColonyColorToken
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.stage = stage
        self.initials = initials
        self.color = color
    }
}

struct ColonyUpdate: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let systemImage: String
    let color: ColonyColorToken

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        systemImage: String,
        color: ColonyColorToken
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.color = color
    }
}

struct WorkspaceMember: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let email: String
    let role: WorkspaceRole
    let initials: String
    let color: ColonyColorToken

    init(
        id: UUID = UUID(),
        name: String,
        email: String,
        role: WorkspaceRole,
        initials: String,
        color: ColonyColorToken
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.initials = initials
        self.color = color
    }
}

struct PendingInvite: Codable, Equatable, Identifiable {
    let id: UUID
    let email: String
    let role: WorkspaceRole

    init(id: UUID = UUID(), email: String, role: WorkspaceRole) {
        self.id = id
        self.email = email
        self.role = role
    }
}

struct AuthProvider: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: AuthProviderKind
    var status: AuthProviderStatus
    let detail: String

    init(
        id: UUID = UUID(),
        kind: AuthProviderKind,
        status: AuthProviderStatus,
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.detail = detail
    }
}

struct SecurityPolicy: Codable, Equatable {
    var requiresTwoFactor: Bool
    var allowsPasskeys: Bool
    var allowsPersonalAccounts: Bool
    var requiresSSOForBusinessUsers: Bool

    static let recommended = SecurityPolicy(
        requiresTwoFactor: true,
        allowsPasskeys: true,
        allowsPersonalAccounts: true,
        requiresSSOForBusinessUsers: false
    )
}
