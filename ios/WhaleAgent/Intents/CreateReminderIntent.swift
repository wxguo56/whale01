import AppIntents
import EventKit
import Foundation

enum WhaleIntentError: LocalizedError {
    case reminderAccessDenied
    case noReminderList

    var errorDescription: String? {
        switch self {
        case .reminderAccessDenied:
            return "没有提醒事项权限，请先在设置中允许鲸鱼访问提醒事项。"
        case .noReminderList:
            return "设备上没有可写入的提醒事项列表。"
        }
    }
}

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "创建提醒"
    static var description = IntentDescription("把一件事写入系统提醒事项，并在指定时间提醒你。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "事项", requestValueDialog: "要提醒你做什么？")
    var title: String

    @Parameter(title: "提醒时间")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("提醒我 \(\.$title)") {
            \.$dueDate
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw WhaleIntentError.reminderAccessDenied }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw WhaleIntentError.noReminderList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        try store.save(reminder, commit: true)

        if let dueDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 HH:mm"
            return .result(dialog: "已创建提醒：\(title)，\(formatter.string(from: dueDate))")
        }
        return .result(dialog: "已创建提醒：\(title)")
    }
}

struct WhaleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "用\(.applicationName)提醒我",
                "让\(.applicationName)记一件事"
            ],
            shortTitle: "创建提醒",
            systemImageName: "bell.badge"
        )
    }
}