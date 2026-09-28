//
//  SampleData.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

enum SampleData {
    static let channels = [
        ColonyChannel(
            name: "founders",
            description: "Strategy, product direction, and decisions",
            unreadCount: 3,
            messages: [
                ColonyMessage(author: "Maya", time: "09:14", body: "I linked the first CRM objects to the launch board so every account has a next step.", authorColor: .indigo),
                ColonyMessage(author: "Yoav", time: "09:18", body: "Good. The MVP should prove chat plus execution before we widen the surface.", authorColor: .blue),
                ColonyMessage(author: "Ari", time: "09:31", body: "I will draft the self-hosting checklist around Docker Compose, backups, and SSO.", authorColor: .green)
            ]
        ),
        ColonyChannel(
            name: "product",
            description: "Design, roadmap, research, and feedback",
            unreadCount: 0,
            messages: [
                ColonyMessage(author: "Nina", time: "10:05", body: "The theme controls should feel like system preferences, not a web admin panel.", authorColor: .orange),
                ColonyMessage(author: "Maya", time: "10:11", body: "Agreed. Token-based themes first, advanced customization later.", authorColor: .indigo)
            ]
        ),
        ColonyChannel(
            name: "sales",
            description: "Pipeline, customers, renewals, and handoffs",
            unreadCount: 8,
            messages: [
                ColonyMessage(author: "Ari", time: "11:42", body: "Northstar asked for Microsoft Entra ID, SAML, and enforced passkeys.", authorColor: .green),
                ColonyMessage(author: "Yoav", time: "11:45", body: "That belongs in the business identity milestone. Let's keep the adapter shape ready now.", authorColor: .blue)
            ]
        ),
        ColonyChannel(
            name: "Maya Chen",
            description: "Direct message with Maya",
            kind: .directMessage,
            unreadCount: 1,
            messages: [
                ColonyMessage(author: "Maya", time: "12:08", body: "Can you review the task board spacing before we add more CRM workflow?", authorColor: .indigo),
                ColonyMessage(author: "Yoav", time: "12:12", body: "Yes. I want the board to feel closer to Monday and Plane, less like a split inspector.", authorColor: .blue)
            ]
        ),
        ColonyChannel(
            name: "Ari Levy",
            description: "Direct message with Ari",
            kind: .directMessage,
            unreadCount: 0,
            messages: [
                ColonyMessage(author: "Ari", time: "12:22", body: "I added notes for the Docker Compose deployment path.", authorColor: .green)
            ]
        )
    ]

    static let tasks = [
        ColonyTask(title: "POC", owner: "Yoav", priority: "High", category: "SharePoint", dueDate: "Sep 17, 2025", status: .active),
        ColonyTask(title: "Providers comparison sheet", owner: "Yoav", priority: "High", category: "AI Tools Integration & Research", dueDate: "Sep 17, 2025", status: .review),
        ColonyTask(title: "Tafnit Master Skill for Claude", owner: "Maya", priority: "Medium", category: "AI Tools Integration & Research", dueDate: "Sep 17, 2025", status: .planned),
        ColonyTask(title: "Data pulling from sources", owner: "Ari", priority: "Medium", category: "AI Tools Integration & Research", dueDate: "Sep 17, 2025", status: .planned),
        ColonyTask(title: "Create Docker Compose outline", owner: "Ari", priority: "Medium", category: "Infrastructure", dueDate: "Sep 20, 2025", status: .active)
    ]

    static let contacts = [
        ColonyContact(name: "Leah Cohen", company: "Northstar Labs", stage: "Security review", initials: "LC", color: .blue),
        ColonyContact(name: "Omer Bar", company: "Fieldnote Studio", stage: "Pilot", initials: "OB", color: .green),
        ColonyContact(name: "Dana Reed", company: "Atlas Works", stage: "Proposal", initials: "DR", color: .purple),
        ColonyContact(name: "Sam Wright", company: "Harbor Systems", stage: "Discovery", initials: "SW", color: .orange)
    ]

    static let updates = [
        ColonyUpdate(title: "Architecture docs created", detail: "The first platform docs now cover product, auth, theming, hosting, and roadmap.", systemImage: "doc.text", color: .blue),
        ColonyUpdate(title: "SSO marked as core", detail: "Business identity will support Google Workspace, Microsoft Entra ID, OIDC, and SAML.", systemImage: "lock.shield", color: .purple),
        ColonyUpdate(title: "MVP scope narrowed", detail: "The first build focuses on workspace, auth, channels, messages, contacts, tasks, and themes.", systemImage: "scope", color: .green)
    ]

    static let members = [
        WorkspaceMember(name: "Yoav Peretz", email: "yoav@colony.local", role: .admin, initials: "YP", color: .blue),
        WorkspaceMember(name: "Maya Chen", email: "maya@colony.local", role: .member, initials: "MC", color: .indigo),
        WorkspaceMember(name: "Ari Levy", email: "ari@colony.local", role: .member, initials: "AL", color: .green)
    ]

    static let pendingInvites = [
        PendingInvite(email: "security@northstar.example", role: .guest)
    ]

    static let authProviders = [
        AuthProvider(kind: .email, status: .enabled, detail: "Email sign-in for personal users."),
        AuthProvider(kind: .google, status: .enabled, detail: "Google sign-in and future Workspace SSO."),
        AuthProvider(kind: .github, status: .enabled, detail: "GitHub sign-in for technical users."),
        AuthProvider(kind: .microsoft, status: .planned, detail: "Microsoft Entra ID business SSO."),
        AuthProvider(kind: .passkey, status: .planned, detail: "Passwordless sign-in using platform passkeys."),
        AuthProvider(kind: .saml, status: .planned, detail: "Enterprise SAML for larger self-hosted teams.")
    ]
}
