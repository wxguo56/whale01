import Combine
import Contacts
import CoreLocation
import EventKit
import HealthKit
import MessageUI
import MusicKit

@MainActor
final class PermissionCenter: ObservableObject {
    static let labels: [String: String] = [
        "reminder": "提醒事项",
        "calendarRead": "日历读取",
        "calendarWrite": "日历写入",
        "music": "音乐库",
        "location": "定位",
        "activityRead": "运动数据",
        "contacts": "通讯录",
        "messages": "信息"
    ]

    static let toolPermissions: [String: [String]] = [
        "create_reminder": ["reminder"],
        "list_calendar_events": ["calendarRead"],
        "create_calendar_event": ["calendarWrite"],
        "get_weather": ["location"],
        "search_places": ["location"],
        "open_navigation": ["location"],
        "get_activity_summary": ["activityRead"],
        "search_music_library": ["music"],
        "play_music": ["music"],
        "pause_music": ["music"],
        "resume_music": ["music"],
        "skip_music_track": ["music"],
        "get_playback_state": ["music"],
        "prepare_message": ["contacts", "messages"]
    ]

    @Published private(set) var statuses: [String: String] = [:]

    private let eventStore = EKEventStore()
    private let healthStore = HKHealthStore()
    private let contactStore = CNContactStore()
    private let locationManager = CLLocationManager()

    init() {
        refresh()
    }

    static func label(_ key: String) -> String {
        labels[key] ?? key
    }

    func snapshot() -> [String: String] {
        statuses
    }

    func refresh() {
        var next: [String: String] = [:]

        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        next["calendarRead"] = mapEventStatus(eventStatus, readRequired: true)
        next["calendarWrite"] = mapEventStatus(eventStatus, readRequired: false)

        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        next["reminder"] = mapEventStatus(reminderStatus, readRequired: true)
        #if FREE_SIGNING
        next["activityRead"] = "unavailable"
        #else
        next["activityRead"] = "unknown"
        #endif

        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            next["contacts"] = "granted"
        case .denied, .restricted:
            next["contacts"] = "denied"
        case .notDetermined:
            next["contacts"] = "unknown"
        default:
            next["contacts"] = "granted"
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            next["location"] = "granted"
        case .denied, .restricted:
            next["location"] = "denied"
        case .notDetermined:
            next["location"] = "unknown"
        @unknown default:
            next["location"] = "unknown"
        }

        switch MusicAuthorization.currentStatus {
        case .authorized:
            next["music"] = "granted"
        case .denied, .restricted:
            next["music"] = "denied"
        case .notDetermined:
            next["music"] = "unknown"
        @unknown default:
            next["music"] = "unknown"
        }

        next["messages"] = MFMessageComposeViewController.canSendText() ? "granted" : "denied"
        statuses = next
    }

    func ensure(tool: String, arguments: [String: JSONValue] = [:]) async -> String? {
        let required: [String]
        if tool == "search_places" {
            let mode = arguments.optionalString("locationMode")
            let hasRegion = !(arguments.optionalString("region") ?? "").isEmpty
            let hasNear = arguments.optionalObject("near") != nil
            let needsLocation = mode == "current" || (mode == nil && !hasRegion && !hasNear)
            required = needsLocation ? ["location"] : []
        } else if tool == "open_navigation" {
            required = []
        } else if tool == "search_music_library" {
            required = []
        } else if tool == "play_music", (arguments.optionalString("trackId") ?? "").hasPrefix("local:") {
            required = []
        } else if ["pause_music", "resume_music", "skip_music_track", "get_playback_state"].contains(tool),
                  LocalMusicLibrary.shared.hasActivePlayback {
            required = []
        } else {
            required = Self.toolPermissions[tool] ?? []
        }
        for permission in required {
            if !(await ensurePermission(permission)) {
                return permission
            }
        }
        return nil
    }

    func request(_ permission: String) async -> Bool {
        await ensurePermission(permission)
    }

    private func ensurePermission(_ permission: String) async -> Bool {
        switch permission {
        case "reminder":
            return await ensureReminder()
        case "calendarRead":
            return await ensureCalendar(readRequired: true)
        case "calendarWrite":
            return await ensureCalendar(readRequired: false)
        case "activityRead":
            #if FREE_SIGNING
            statuses["activityRead"] = "unavailable"
            return false
            #else
            return await ensureHealth()
            #endif
        case "contacts":
            return await ensureContacts()
        case "location":
            return await ensureLocation()
        case "music":
            return await ensureMusic()
        case "messages":
            let available = MFMessageComposeViewController.canSendText()
            statuses["messages"] = available ? "granted" : "denied"
            return available
        default:
            return true
        }
    }

    private func ensureReminder() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            statuses["reminder"] = "granted"
            return true
        case .denied, .restricted:
            statuses["reminder"] = "denied"
            return false
        default:
            break
        }

        do {
            let granted = try await requestFullAccessToReminders()
            statuses["reminder"] = granted ? "granted" : "denied"
            return granted
        } catch {
            statuses["reminder"] = "denied"
            return false
        }
    }

    private func ensureCalendar(readRequired: Bool) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            statuses["calendarRead"] = "granted"
            statuses["calendarWrite"] = "granted"
            return true
        }
        if status == .writeOnly && !readRequired {
            statuses["calendarWrite"] = "granted"
            return true
        }
        if status == .denied || status == .restricted {
            statuses[readRequired ? "calendarRead" : "calendarWrite"] = "denied"
            return false
        }

        do {
            let granted = try await requestFullAccessToEvents()
            statuses["calendarRead"] = granted ? "granted" : "denied"
            statuses["calendarWrite"] = granted ? "granted" : "denied"
            return granted
        } catch {
            statuses[readRequired ? "calendarRead" : "calendarWrite"] = "denied"
            return false
        }
    }

    private func ensureHealth() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            statuses["activityRead"] = "denied"
            return false
        }
        do {
            try await healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: healthReadTypes())
            statuses["activityRead"] = "granted"
            return true
        } catch {
            statuses["activityRead"] = "denied"
            return false
        }
    }

    private func ensureContacts() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            statuses["contacts"] = "granted"
            return true
        case .denied, .restricted:
            statuses["contacts"] = "denied"
            return false
        case .notDetermined:
            break
        default:
            statuses["contacts"] = "granted"
            return true
        }

        do {
            let granted = try await requestContactsAccess()
            statuses["contacts"] = granted ? "granted" : "denied"
            return granted
        } catch {
            statuses["contacts"] = "denied"
            return false
        }
    }

    private func ensureLocation() async -> Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            statuses["location"] = "granted"
            return true
        case .denied, .restricted:
            statuses["location"] = "denied"
            return false
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            locationManager.requestWhenInUseAuthorization()
        }

        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let current = locationManager.authorizationStatus
            if current == .authorizedAlways || current == .authorizedWhenInUse {
                statuses["location"] = "granted"
                return true
            }
            if current == .denied || current == .restricted {
                statuses["location"] = "denied"
                return false
            }
        }
        statuses["location"] = "unknown"
        return false
    }

    private func ensureMusic() async -> Bool {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            statuses["music"] = "granted"
            return true
        case .denied, .restricted:
            statuses["music"] = "denied"
            return false
        case .notDetermined:
            break
        @unknown default:
            break
        }

        let result = await MusicAuthorization.request()
        let granted: Bool
        if case .authorized = result {
            granted = true
        } else {
            granted = false
        }
        statuses["music"] = granted ? "granted" : "denied"
        return granted
    }

    private func healthReadTypes() -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .distanceWalkingRunning
        ]
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    private func requestFullAccessToEvents() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestFullAccessToReminders() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestContactsAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func mapEventStatus(_ status: EKAuthorizationStatus, readRequired: Bool) -> String {
        switch status {
        case .fullAccess:
            return "granted"
        case .writeOnly:
            return readRequired ? "denied" : "granted"
        case .denied, .restricted:
            return "denied"
        case .notDetermined:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}
