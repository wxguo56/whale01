import SwiftUI

struct RecordsView: View {
    @ObservedObject var model: AppModel

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [NativeActionRecord]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.recentActions) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: grouped[day]?.sorted { $0.createdAt > $1.createdAt } ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            Text(label(for: group.day))
                                .font(.system(size: 13))
                                .foregroundStyle(WhaleTheme.muted)
                                .padding(.top, 22)
                                .padding(.bottom, 11)
                            ForEach(group.items) { action in
                                recordCard(action)
                                    .padding(.bottom, 11)
                            }
                        }
                    }
                }
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .background(WhaleTheme.background)
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            WhaleIconTile(systemName: "clock", size: 68)
            Text("还没有记录")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("完成一次提醒、日程、地点或音乐操作后，结果会出现在这里。")
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
        .padding(.horizontal, 24)
    }

    private func recordCard(_ action: NativeActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
                Text(action.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Text(action.isSuccess ? "已完成" : "待核对")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (action.isSuccess ? WhaleTheme.success : WhaleTheme.warm).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .foregroundStyle(action.isSuccess ? WhaleTheme.success : WhaleTheme.warm)
            }
            Text(action.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            if !action.detail.isEmpty {
                Text(action.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(WhaleTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.line, lineWidth: 1)
        }
    }

    private func label(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day())
    }
}
