import Charts
import SwiftUI

struct StockDetailView: View {
    @ObservedObject var discover: DiscoverModel
    @StateObject private var model: StockDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var chartMode: StockChartMode = .intraday

    init(quote: StockQuote, discover: DiscoverModel) {
        self.discover = discover
        _model = StateObject(wrappedValue: StockDetailModel(quote: quote))
    }

    private var quote: StockQuote { model.current }

    private var tint: Color {
        quote.isUp ? WhaleTheme.danger : quote.isDown ? WhaleTheme.success : WhaleTheme.muted
    }

    var body: some View {
        ZStack {
            WhaleBackdrop()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        priceHeader
                        if case .failed(let message) = model.state {
                            errorBanner(message)
                        }
                        chartCard
                        statsCard
                        fundFlowCard
                        actionCard
                        MarketDisclaimer(source: model.source.isEmpty ? (quote.source ?? "") : model.source, updatedAt: model.updatedAt ?? quote.timestamp)
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.load() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler().frame(width: 1, height: 1))
        .task { await model.load() }
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
                Text(quote.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text(quote.displayCode)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
            Button {
                if discover.isWatched(quote.symbol) {
                    discover.removeFromWatchlist(quote.symbol)
                } else {
                    discover.addToWatchlist(quote.symbol)
                }
            } label: {
                Image(systemName: discover.isWatched(quote.symbol) ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(discover.isWatched(quote.symbol) ? WhaleTheme.warm : WhaleTheme.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(discover.isWatched(quote.symbol) ? "从自选移除" : "加自选")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WhaleChromeBackground())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhaleTheme.line.opacity(0.55)).frame(height: 0.6)
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(DiscoverFormat.price(quote.price))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WhaleTheme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(spacing: 10) {
                Text(DiscoverFormat.signedPrice(quote.change))
                Text(DiscoverFormat.percent(quote.changePercent))
            }
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                Text("最近成交 \(DiscoverFormat.clock(quote.timestamp)) · 约延迟 15 分钟")
            }
            .font(.system(size: 10))
            .foregroundStyle(WhaleTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.warm)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Button("重试") { Task { await model.load() } }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WhaleTheme.accent)
        }
        .padding(12)
        .background(WhaleTheme.warm.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("走势")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(StockChartMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { chartMode = mode }
                        } label: {
                            Text(mode.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(chartMode == mode ? WhaleTheme.ink : WhaleTheme.muted)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(chartMode == mode ? WhaleTheme.card : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(WhaleTheme.field.opacity(0.72), in: Capsule())
            }

            switch model.chartState {
            case .loading, .idle:
                RoundedRectangle(cornerRadius: 10)
                    .fill(WhaleTheme.soft)
                    .frame(height: 190)
                    .redacted(reason: .placeholder)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .loaded:
                StockChart(mode: chartMode, intraday: model.intraday, kline: model.kline, previousClose: quote.previousClose, tint: tint)
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8) }
        .horizontalTabSwipe(
            onPrevious: { stepChartMode(-1) },
            onNext: { stepChartMode(1) }
        )
    }

    private func stepChartMode(_ delta: Int) {
        let all = StockChartMode.allCases
        guard let index = all.firstIndex(of: chartMode) else { return }
        let next = min(max(index + delta, 0), all.count - 1)
        guard next != index else { return }
        withAnimation(.easeInOut(duration: 0.18)) { chartMode = all[next] }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日统计")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WhaleTheme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                stat("今开", DiscoverFormat.price(quote.open))
                stat("昨收", DiscoverFormat.price(quote.previousClose))
                stat("最高", DiscoverFormat.price(quote.high))
                stat("最低", DiscoverFormat.price(quote.low))
                stat("成交量", volumeText)
                stat("成交额", DiscoverFormat.compactAmount(quote.amount))
                stat("换手率", quote.turnoverPercent == nil ? "—" : "\(String(format: "%.2f", quote.turnoverPercent!))%")
                stat("市盈率", quote.pe == nil ? "—" : String(format: "%.2f", quote.pe!))
                stat("总市值", DiscoverFormat.compactAmount(quote.marketCap))
                stat("流通市值", DiscoverFormat.compactAmount(quote.floatMarketCap))
                stat("振幅", amplitudeText)
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8) }
    }

    private var volumeText: String {
        guard let volume = quote.volume else { return "—" }
        if volume >= 100_000_000 { return String(format: "%.2f 亿股", volume / 100_000_000) }
        if volume >= 10_000 { return String(format: "%.1f 万股", volume / 10_000) }
        return String(format: "%.0f 股", volume)
    }

    private var amplitudeText: String {
        guard let high = quote.high, let low = quote.low, let previous = quote.previousClose, previous > 0 else {
            return "—"
        }
        return String(format: "%.2f%%", (high - low) / previous * 100)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WhaleTheme.ink)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(WhaleTheme.field.opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var fundFlowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("资金动向")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Spacer()
                Text("近 6 个交易日 · 东方财富")
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.muted)
            }

            switch model.fundFlowState {
            case .loading, .idle:
                RoundedRectangle(cornerRadius: 10)
                    .fill(WhaleTheme.soft)
                    .frame(height: 120)
                    .redacted(reason: .placeholder)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            case .loaded:
                FundFlowChart(points: model.fundFlow)
                if let latest = model.fundFlow.last {
                    HStack {
                        Text(latest.date)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(WhaleTheme.muted)
                        Spacer()
                        Text("主力 \(DiscoverFormat.signedCompactAmount(latest.mainNet))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(latest.isInflow ? WhaleTheme.danger : WhaleTheme.success)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        flowStat("超大单", latest.superLargeNet)
                        flowStat("大单", latest.largeNet)
                        flowStat("中单", latest.mediumNet)
                        flowStat("小单", latest.smallNet)
                    }
                }
                Text("红柱为主力净流入，绿柱为净流出；单位：亿元。数据来自东方财富公开资金流，不构成投资建议。")
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private func flowStat(_ label: String, _ value: Double?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
            Spacer()
            Text(DiscoverFormat.signedCompactAmount(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle((value ?? 0) >= 0 ? WhaleTheme.danger : WhaleTheme.success)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(WhaleTheme.field.opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var actionCard: some View {
        HStack(spacing: 10) {
            Button {
                if discover.isWatched(quote.symbol) {
                    discover.removeFromWatchlist(quote.symbol)
                } else {
                    discover.addToWatchlist(quote.symbol)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: discover.isWatched(quote.symbol) ? "star.slash" : "star.fill")
                    Text(discover.isWatched(quote.symbol) ? "从自选移除" : "加自选")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(discover.isWatched(quote.symbol) ? WhaleTheme.ink : WhaleTheme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    if discover.isWatched(quote.symbol) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WhaleTheme.card.opacity(0.9))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WhaleTheme.auroraGradient)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct FundFlowChart: View {
    let points: [FundFlowPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("日期", String(point.date.suffix(5))),
                y: .value("主力净流入", (point.mainNet ?? 0) / 100_000_000)
            )
            .foregroundStyle((point.mainNet ?? 0) >= 0 ? WhaleTheme.danger : WhaleTheme.success)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(WhaleTheme.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(WhaleTheme.line.opacity(0.45))
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(WhaleTheme.muted)
            }
        }
        .frame(height: 120)
    }
}

enum StockChartMode: String, CaseIterable, Identifiable {
    case intraday
    case day

    var id: String { rawValue }
    var title: String { self == .intraday ? "分时" : "日 K" }
}

struct StockChart: View {
    let mode: StockChartMode
    let intraday: [IntradayPoint]
    let kline: [KlinePoint]
    let previousClose: Double?
    let tint: Color

    private var values: [Double] {
        switch mode {
        case .intraday:
            return intraday.compactMap(\.price).filter { $0.isFinite && $0 > 0 }
        case .day:
            return kline.map(\.chartValue).filter { $0.isFinite && $0 > 0 }
        }
    }

    private var domain: ClosedRange<Double> {
        var lower = values.min() ?? 0
        var upper = values.max() ?? 1
        if let previousClose {
            lower = min(lower, previousClose)
            upper = max(upper, previousClose)
        }
        let span = max(upper - lower, max(upper * 0.004, 0.01))
        lower -= span * 0.12
        upper += span * 0.12
        return lower...upper
    }

    var body: some View {
        VStack(spacing: 7) {
            Chart {
                if mode == .intraday {
                    ForEach(Array(intraday.enumerated()), id: \.offset) { index, point in
                        if let price = point.price {
                            AreaMark(x: .value("序号", index), y: .value("价格", price))
                                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("序号", index), y: .value("价格", price))
                                .foregroundStyle(tint)
                                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                } else {
                    ForEach(Array(kline.enumerated()), id: \.offset) { index, point in
                        AreaMark(x: .value("序号", index), y: .value("收盘", point.chartValue))
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("序号", index), y: .value("收盘", point.chartValue))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                }
                if let previousClose, values.contains(where: { $0 > 0 }) {
                    RuleMark(y: .value("昨收", previousClose))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(WhaleTheme.line.opacity(0.45))
                    AxisValueLabel()
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(WhaleTheme.muted)
                }
            }
            .chartYScale(domain: domain)
            .frame(height: 190)

            HStack {
                Text(axisStart)
                Spacer()
                Text(axisEnd)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(WhaleTheme.muted)
        }
    }

    private var axisStart: String {
        if mode == .intraday { return intraday.first?.time ?? "" }
        return kline.first?.date ?? ""
    }

    private var axisEnd: String {
        if mode == .intraday { return intraday.last?.time ?? "" }
        return kline.last?.date ?? ""
    }
}
