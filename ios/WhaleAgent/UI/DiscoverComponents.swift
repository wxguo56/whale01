import SwiftUI

struct DiscoverSegment: View {
    @Binding var selection: DiscoverChannel
    var onSelect: ((DiscoverChannel) -> Void)?
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DiscoverChannel.allCases) { channel in
                Button {
                    if let onSelect {
                        onSelect(channel)
                    } else {
                        withAnimation(.snappy(duration: 0.24)) { selection = channel }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: channel.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(channel.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selection == channel ? WhaleTheme.ink : WhaleTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if selection == channel {
                            Capsule()
                                .fill(WhaleTheme.card.opacity(0.92))
                                .matchedGeometryEffect(id: "discover.segment", in: animation)
                                .overlay { Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WhaleTheme.field.opacity(0.78), in: Capsule())
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
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

            Text(item.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            if !item.summary.isEmpty {
                Text(item.summary)
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
                    Image(systemName: item.channel == "ai" ? "sparkles" : "newspaper.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WhaleTheme.onAccent.opacity(0.88))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.source)
                    Circle().fill(WhaleTheme.muted.opacity(0.5)).frame(width: 3, height: 3)
                    Text(DiscoverFormat.relative(item.publishedAt))
                }
                .font(.system(size: 10))
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
                Text("行情约延迟 15 分钟 · 不构成投资建议 · 不提供交易")
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
    @State private var quote: StockQuote?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let quote {
                StockDetailView(quote: quote, discover: discover)
            } else if let errorText {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhaleBackdrop())
        .task { await load() }
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
