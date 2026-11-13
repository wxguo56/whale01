import SwiftUI

struct HorizontalTabSwipe: ViewModifier {
    var onPrevious: () -> Void
    var onNext: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 64, abs(dy) < 56, abs(dx) > abs(dy) * 1.4 else { return }
                    if dx < 0 {
                        onNext()
                    } else {
                        onPrevious()
                    }
                }
        )
    }
}

extension View {
    func horizontalTabSwipe(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        modifier(HorizontalTabSwipe(onPrevious: onPrevious, onNext: onNext))
    }
}

struct DiscoverChannelHeader: View {
    let channel: DiscoverChannel
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: channel.icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(WhaleTheme.auroraGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text(detail ?? channel.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

struct DiscoverSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                }
            }
            Spacer()
            if let action, let onAction {
                Button(action) { onAction() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct NewsFeatureCard: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("焦点")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(WhaleTheme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhaleTheme.accent, in: Capsule())
                Text(item.source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Text(DiscoverFormat.relative(item.publishedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Text(item.displayTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            if !item.displaySummary.isEmpty {
                Text(item.displaySummary)
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 5) {
                Text("阅读详情")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WhaleTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(WhaleTheme.card.opacity(0.9))
                Circle()
                    .fill(WhaleTheme.accent.opacity(0.12))
                    .frame(width: 150, height: 150)
                    .blur(radius: 26)
                    .offset(x: 45, y: -60)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8) }
    }
}

struct NewsRowCard: View {
    let item: NewsItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(WhaleTheme.auroraGradient)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: channelIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WhaleTheme.onAccent.opacity(0.88))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.source)
                    Circle().fill(WhaleTheme.muted.opacity(0.5)).frame(width: 3, height: 3)
                    Text(DiscoverFormat.relative(item.publishedAt))
                }
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WhaleTheme.muted.opacity(0.5))
                .padding(.top, 5)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }

    private var channelIcon: String {
        switch item.channel {
        case "ai": return "sparkles"
        case "game": return "gamecontroller.fill"
        default: return "newspaper.fill"
        }
    }
}

struct NewsSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(WhaleTheme.soft)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(WhaleTheme.soft).frame(height: 13)
                        RoundedRectangle(cornerRadius: 4).fill(WhaleTheme.soft.opacity(0.7)).frame(width: 150, height: 10)
                    }
                }
                .padding(14)
                .background(WhaleTheme.card.opacity(0.52), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .opacity(1 - Double(index) * 0.12)
            }
        }
        .redacted(reason: .placeholder)
    }
}

struct DiscoverErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(WhaleTheme.muted)
            Text("暂时没有取到数据")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试", action: retry)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhaleTheme.onAccent)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(WhaleTheme.auroraGradient, in: Capsule())
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
    }
}

struct MarketIndexCard: View {
    let quote: StockQuote

    private var tint: Color {
        quote.isUp ? WhaleTheme.danger : quote.isDown ? WhaleTheme.success : WhaleTheme.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quote.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WhaleTheme.muted)
                .lineLimit(1)
            Text(DiscoverFormat.price(quote.price))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WhaleTheme.ink)
            Text(DiscoverFormat.percent(quote.changePercent))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(width: 116, alignment: .leading)
        .padding(13)
        .background(WhaleTheme.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}

struct QuoteRowCard: View {
    let quote: StockQuote
    var flow: FundFlowPoint? = nil

    private var tint: Color {
        quote.isUp ? WhaleTheme.danger : quote.isDown ? WhaleTheme.success : WhaleTheme.muted
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text(quote.displayCode)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(WhaleTheme.muted)
                if let flow {
                    HStack(spacing: 4) {
                        Text("主力")
                        Text(DiscoverFormat.signedCompactAmount(flow.mainNet))
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(flow.isInflow ? WhaleTheme.danger : WhaleTheme.success)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(DiscoverFormat.price(quote.price))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WhaleTheme.ink)
                Text(DiscoverFormat.percent(quote.changePercent))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WhaleTheme.muted.opacity(0.5))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 15)
        .background(WhaleTheme.card.opacity(0.74), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}

struct AIPaperCategoryBar: View {
    let selection: AIPaperCategory
    let onSelect: (AIPaperCategory) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(AIPaperCategory.allCases) { category in
                        Button {
                            onSelect(category)
                        } label: {
                            VStack(spacing: 1) {
                                Text(category.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(category.rawValue)
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(selection == category ? WhaleTheme.onAccent : WhaleTheme.muted)
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .background {
                                if selection == category {
                                    Capsule().fill(WhaleTheme.auroraGradient)
                                } else {
                                    Capsule().fill(WhaleTheme.card.opacity(0.78))
                                }
                            }
                            .overlay {
                                Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: selection == category ? 0 : 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(category)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, next in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(next, anchor: .center)
                }
            }
        }
    }
}

struct AIPaperCard: View {
    let paper: AIPaper

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(paper.category)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WhaleTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(WhaleTheme.accent.opacity(0.11), in: Capsule())
                if !paper.authors.isEmpty {
                    Text(paper.authors)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(DiscoverFormat.relative(paper.publishedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Text(paper.displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if !paper.displaySummary.isEmpty {
                Text(paper.displaySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            if let url = paper.url {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("阅读 arXiv 原文")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WhaleTheme.card.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
        }
    }
}

struct MarketSearchField: View {
    @Binding var text: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhaleTheme.muted)
            TextField("搜索股票名称或代码", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.ink)
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(WhaleTheme.field.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}

struct MarketDisclaimer: View {
    let source: String
    let updatedAt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("公开行情 · 延迟以来源为准 · 不构成投资建议")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(WhaleTheme.muted)
            HStack(spacing: 4) {
                if !source.isEmpty { Text(source) }
                if let updatedAt, !updatedAt.isEmpty {
                    Text("· \(DiscoverFormat.clock(updatedAt)) 更新")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(WhaleTheme.muted.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

struct StockSeedLoaderView: View {
    let result: StockSearchResult
    @ObservedObject var discover: DiscoverModel
    @Environment(\.dismiss) private var dismiss
    @State private var quote: StockQuote?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let quote {
                StockDetailView(quote: quote, discover: discover)
            } else {
                loadingShell
                    .toolbar(.hidden, for: .navigationBar)
                    .background(SwipeBackEnabler().frame(width: 1, height: 1))
                    .task { await load() }
            }
        }
    }

    private var loadingShell: some View {
        ZStack {
            WhaleBackdrop()
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(WhaleTheme.muted)
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(WhaleTheme.muted)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await load() } }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhaleTheme.accent)
                    }
                    .padding(28)
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(WhaleTheme.accent)
                        Text("正在读取 \(result.name) 的真实行情")
                            .font(.system(size: 12))
                            .foregroundStyle(WhaleTheme.muted)
                    }
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhaleBackdrop())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle(size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text(result.displayCode)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WhaleChromeBackground())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhaleTheme.line.opacity(0.55)).frame(height: 0.6)
        }
    }

    private func load() async {
        errorText = nil
        do {
            let response = try await discover.client.quotes(symbols: [result.symbol])
            guard let first = response.quotes.first else { throw DiscoverClientError.server("行情源没有返回该股票") }
            quote = first
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct GameSectionSegment: View {
    @Binding var selection: GameSection
    var onSelect: ((GameSection) -> Void)?
    @Namespace private var animation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(GameSection.allCases) { section in
                        Button {
                            if let onSelect {
                                onSelect(section)
                            } else {
                                withAnimation(.snappy(duration: 0.22)) { selection = section }
                            }
                        } label: {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selection == section ? WhaleTheme.ink : WhaleTheme.muted)
                                .padding(.horizontal, 13)
                                .frame(height: 30)
                                .background {
                                    if selection == section {
                                        Capsule()
                                            .fill(WhaleTheme.card.opacity(0.92))
                                            .matchedGeometryEffect(id: "game.section", in: animation)
                                            .overlay { Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(section)
                    }
                }
                .padding(3)
                .background(WhaleTheme.field.opacity(0.6), in: Capsule())
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, next in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(next, anchor: .center)
                }
            }
        }
    }
}

struct GameRankHeader: View {
    let title: String
    let source: String
    let updatedAt: String?
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WhaleTheme.auroraGradient)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(WhaleTheme.onAccent.opacity(0.92))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("App Store 中国区 · \(title)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text("来源：\(source.isEmpty ? "Apple App Store 公开榜单" : source)")
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
                if let updatedAt {
                    Text("更新于 \(DiscoverFormat.relative(updatedAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.8))
                }
            }

            Spacer(minLength: 4)

            Text("\(count) 款")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WhaleTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(WhaleTheme.accent.opacity(0.1), in: Capsule())
        }
        .padding(13)
        .background(WhaleTheme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}

struct GameRankRowCard: View {
    let item: GameRankItem

    var body: some View {
        HStack(spacing: 11) {
            Text("\(item.rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(item.rank <= 3 ? WhaleTheme.onAccent : WhaleTheme.muted)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(item.rank <= 3 ? WhaleTheme.accent : WhaleTheme.soft.opacity(0.7))
                )

            AsyncImage(url: item.iconURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(WhaleTheme.soft)
                        .overlay {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(WhaleTheme.muted.opacity(0.6))
                        }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.6) }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.category.isEmpty ? "游戏" : item.category)
                    if !item.releaseText.isEmpty {
                        Circle().fill(WhaleTheme.muted.opacity(0.5)).frame(width: 3, height: 3)
                        Text("上架 \(item.releaseText)")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(WhaleTheme.muted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WhaleTheme.muted.opacity(0.55))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}

struct WeiboHotHeader: View {
    let board: HotBoard
    let source: String
    let updatedAt: String?
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(board == .weibo ? WhaleTheme.weiboGradient : WhaleTheme.heroGradient)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: board.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(board.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text("来源：\(source.isEmpty ? (board == .weibo ? "微博公开热搜接口" : "知乎公开热榜接口") : source)")
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
                if let updatedAt {
                    Text("更新于 \(DiscoverFormat.relative(updatedAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.8))
                }
            }

            Spacer(minLength: 4)

            Text("\(count) 条")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(board == .weibo ? WhaleTheme.danger : WhaleTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((board == .weibo ? WhaleTheme.danger : WhaleTheme.accent).opacity(0.1), in: Capsule())
        }
        .padding(13)
        .background(WhaleTheme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}

struct WeiboHotRowCard: View {
    let item: WeiboHotItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(item.rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(item.rank <= 3 ? Color.white : WhaleTheme.muted)
                .frame(width: 27, height: 27)
                .background(
                    Circle().fill(item.rank <= 3 ? WhaleTheme.danger : WhaleTheme.soft.opacity(0.7))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.word)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.note.isEmpty && item.note != item.word {
                    Text(item.note)
                        .font(.system(size: 10))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if !item.tag.isEmpty {
                        Text(item.tag)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WhaleTheme.danger, in: Capsule())
                    }
                    if !item.category.isEmpty {
                        Text(item.category)
                    }
                    if !item.hotText.isEmpty {
                        Text("热度 \(item.hotText)")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(WhaleTheme.muted)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WhaleTheme.muted.opacity(0.55))
                .padding(.top, 5)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
    }
}
