//
//  ColonyLinks.swift
//  Colony
//
//  Public pages the app links to. They're served by GitHub Pages from `docs/` on main,
//  and the same URLs go into App Store Connect (Privacy Policy URL, Support URL).
//

import Foundation

enum ColonyLinks {
    static let site = URL(string: "https://masteryoav.github.io/colony/")!
    static let privacy = URL(string: "https://masteryoav.github.io/colony/privacy/")!
    static let accessibility = URL(string: "https://masteryoav.github.io/colony/accessibility/")!
    static let support = URL(string: "https://masteryoav.github.io/colony/support/")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
