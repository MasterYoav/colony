//
//  AppleServices.swift
//  Colony
//
//  Colony uses Apple's own frameworks instead of third-party integrations:
//  - Contacts: import people from Apple Contacts into the CRM.
//  - EventKit: mirror tasks into Apple Reminders so due dates notify on every device.
//

import Contacts
import EventKit
import Foundation
import Observation

struct AppleContactCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let company: String
    let jobTitle: String
    let email: String
    let phone: String
    let imageData: Data?
}

@MainActor
@Observable
final class ContactsService {
    private(set) var authorization: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

    var canRead: Bool {
        #if os(iOS)
        authorization == .authorized || authorization == .limited
        #else
        authorization == .authorized
        #endif
    }

    var statusTitle: String {
        switch authorization {
        case .authorized: return "Connected"
        case .denied, .restricted: return "Access denied"
        case .notDetermined: return "Not connected"
        default: return "Limited access"
        }
    }

    var needsPrompt: Bool { authorization == .notDetermined }

    func requestAccess() async -> Bool {
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        authorization = CNContactStore.authorizationStatus(for: .contacts)
        return granted
    }

    func fetchAll() async -> [AppleContactCandidate] {
        guard canRead else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var results: [AppleContactCandidate] = []
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
                guard !name.isEmpty else { return }
                results.append(AppleContactCandidate(
                    id: contact.identifier,
                    name: name,
                    company: contact.organizationName,
                    jobTitle: contact.jobTitle,
                    email: (contact.emailAddresses.first?.value as String?) ?? "",
                    phone: contact.phoneNumbers.first?.value.stringValue ?? "",
                    imageData: contact.thumbnailImageData
                ))
            }
            return results
        }.value
    }
}

@MainActor
@Observable
final class RemindersService {
    private let store = EKEventStore()
    private(set) var authorization: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    private(set) var lastError: String?

    var canWrite: Bool { authorization == .fullAccess }

    var statusTitle: String {
        switch authorization {
        case .fullAccess: "Connected"
        case .denied, .restricted: "Access denied"
        case .writeOnly: "Write-only access"
        default: "Not connected"
        }
    }
    var needsPrompt: Bool { authorization == .notDetermined }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        authorization = EKEventStore.authorizationStatus(for: .reminder)
        return granted
    }

    /// Creates or updates the Apple Reminder that mirrors `task`, and stores its identifier on the task.
    @discardableResult
    func mirror(_ task: TaskItem) -> Bool {
        guard canWrite else { return false }
        let reminder: EKReminder
        if let identifier = task.reminderIdentifier, let existing = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: store)
            guard let calendar = store.defaultCalendarForNewReminders() else {
                lastError = "No default Reminders list is set."
                return false
            }
            reminder.calendar = calendar
        }

        reminder.title = task.title
        var notes = task.notes
        if let project = task.project?.name { notes = notes.isEmpty ? "Colony · \(project)" : "\(notes)\n\nColony · \(project)" }
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.isCompleted = task.isDone
        reminder.priority = switch task.priority {
        case .urgent: 1
        case .high: 3
        case .medium: 5
        case .low: 9
        }
        if let due = task.dueDate {
            // Date-only tasks become all-day reminders, as if made in Reminders.
            reminder.dueDateComponents = Calendar.current.dateComponents(task.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: due)
        } else {
            reminder.dueDateComponents = nil
        }

        do {
            try store.save(reminder, commit: true)
            task.reminderIdentifier = reminder.calendarItemIdentifier
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func removeMirror(for task: TaskItem) {
        guard canWrite, let identifier = task.reminderIdentifier,
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try? store.remove(reminder, commit: true)
        task.reminderIdentifier = nil
    }
}
