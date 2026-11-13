import Charts
import SwiftUI

struct StockDetailView: View {
    @ObservedObject var discover: DiscoverModel
    @StateObject private var model: StockDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var chartMode: StockChartMode = .intraday
    @State private var chartRange: Int = 60

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
                        keyMetricsStrip
                        if case .failed(let message) = model.state {
                            errorBanner(message)
                        }
                        chartCard
                        rangeCard
                        profileCard
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
        .task {
            await model.load()
#if DEBUG
            if ProcessInfo.processInfo.environment["WHALE_DEMO_STOCK_DAY"] == "1" {
                chartMode = .day
            }
#endif
            if model.intraday.isEmpty && !model.kline.isEmpty {
                chartMode = .day
            }
        }
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

    private var keyMetricsStrip: some View {
        HStack(spacing: 8) {
            metric("今开", DiscoverFormat.price(quote.open))
            metric("最高", DiscoverFormat.price(quote.high))
            metric("最低", DiscoverFormat.price(quote.low))
            metric("换手", quote.turnoverPercent.map { String(format: "%.2f%%", $0) } ?? "—")
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WhaleTheme.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(WhaleTheme.card.opacity(0.66), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
        }
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

            if chartMode == .day {
                HStack(spacing: 6) {
                    ForEach([20, 60, 120], id: \.self) { range in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { chartRange = range }
                        } label: {
                            Text("\(range)日")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(chartRange == range ? WhaleTheme.accentDeep : WhaleTheme.muted)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(chartRange == range ? WhaleTheme.accent.opacity(0.12) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Text("前复权 · 红涨绿跌")
                        .font(.system(size: 9))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.8))
                }
            }

            switch model.chartState {
            case .loading, .idle:
                RoundedRectangle(cornerRadius: 10)
                    .fill(WhaleTheme.soft)
                    .frame(height: 180)
                    .redacted(reason: .placeholder)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .loaded:
                StockChart(
                    mode: chartMode,
                    intraday: model.intraday,
                    kline: model.kline,
                    previousClose: quote.previousClose,
                    tint: tint,
                    dayRange: chartRange
                )
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

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("区间表现")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Spacer()
                Text("按前复权日线计算")
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.muted)
            }
            if model.kline.count < 2 {
                Text("日线数据不足，暂时无法计算区间表现。")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    stat("5日涨跌", rangeChange(5))
                    stat("20日涨跌", rangeChange(20))
                    stat("60日涨跌", rangeChange(60))
                    stat("60日均量", averageVolumeText)
                    stat("60日最高", DiscoverFormat.price(rangeHigh))
                    stat("60日最低", DiscoverFormat.price(rangeLow))
                }
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("证券资料")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Spacer()
                Text("东方财富公开资料")
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.muted)
            }

            if let profile = model.profile {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    stat("所属行业", profile.industry ?? "—")
                    stat("地区板块", profile.region ?? "—")
                    stat("市净率", profile.priceBook.map { String(format: "%.2f", $0) } ?? "—")
                    stat("量比", profile.volumeRatio.map { String(format: "%.2f", $0) } ?? "—")
                    stat("总股本", sharesText(profile.totalShares))
                    stat("流通股本", sharesText(profile.floatShares))
                    stat("52周最高", DiscoverFormat.price(profile.week52High))
                    stat("52周最低", DiscoverFormat.price(profile.week52Low))
                    if let roe = profile.roe {
                        stat("ROE", String(format: "%.2f%%", roe))
                    }
                }
                Text("资料来自东方财富公开接口；股本、估值与 52 周区间会随行情变化。")
                    .font(.system(size: 9))
                    .foregroundStyle(WhaleTheme.muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                switch model.profileState {
                case .loading, .idle:
                    RoundedRectangle(cornerRadius: 10)
                        .fill(WhaleTheme.soft)
                        .frame(height: 92)
                        .redacted(reason: .placeholder)
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                case .loaded:
                    Text("证券资料暂时为空。")
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private func rangeChange(_ days: Int) -> String {
        guard model.kline.count > days,
              let last = model.kline.last?.close,
              let base = model.kline[model.kline.count - 1 - days].close,
              base > 0 else { return "—" }
        return String(format: "%+.2f%%", (last - base) / base * 100)
    }

    private var rangeHigh: Double? {
        model.kline.suffix(60).compactMap(\.high).max()
    }

    private var rangeLow: Double? {
        model.kline.suffix(60).compactMap(\.low).min()
    }

    private var averageVolumeText: String {
        let volumes = model.kline.suffix(60).compactMap(\.volume)
        guard !volumes.isEmpty else { return "—" }
        return sharesText(volumes.reduce(0, +) / Double(volumes.count))
    }

    private func sharesText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        if value >= 100_000_000 { return String(format: "%.2f 亿股", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f 万股", value / 10_000) }
        return String(format: "%.0f 股", value)
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
    let dayRange: Int

    private var dayPoints: [KlinePoint] {
        Array(kline.suffix(max(dayRange, 5)))
    }

    private var values: [Double] {
        switch mode {
        case .intraday:
            return intraday.compactMap(\.price).filter { $0.isFinite && $0 > 0 }
        case .day:
            return dayPoints
                .flatMap { [$0.low, $0.high, $0.open, $0.close] }
                .compactMap { $0 }
                .filter { $0.isFinite && $0 > 0 }
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

    private var candleWidth: CGFloat {
        switch dayPoints.count {
        case 0...25: return 7
        case 26...70: return 4.2
        default: return 2.4
        }
    }

    private var volumeWidth: CGFloat {
        mode == .intraday ? 1.2 : candleWidth
    }

    private var volumeItems: [(value: Double, up: Bool)] {
        switch mode {
        case .intraday:
            let base = previousClose ?? intraday.compactMap(\.price).first ?? 0
            return intraday.compactMap { point in
                guard let volume = point.volumeLots, volume > 0 else { return nil }
                return (volume, (point.price ?? base) >= base)
            }
        case .day:
            return dayPoints.compactMap { point in
                let volume = point.volumeLots ?? point.volume.map { $0 / 100 }
                guard let volume, volume > 0 else { return nil }
                return (volume, (point.close ?? 0) >= (point.open ?? 0))
            }
        }
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
                    ForEach(Array(dayPoints.enumerated()), id: \.offset) { index, point in
                        if let open = point.open, let close = point.close,
                           let high = point.high, let low = point.low {
                            let color = close >= open ? WhaleTheme.danger : WhaleTheme.success
                            BarMark(
                                x: .value("序号", index),
                                yStart: .value("最低", low),
                                yEnd: .value("最高", high),
                                width: .fixed(1)
                            )
                            .foregroundStyle(color)
                            BarMark(
                                x: .value("序号", index),
                                yStart: .value("开盘", min(open, close)),
                                yEnd: .value("收盘", max(open, close)),
                                width: .fixed(candleWidth)
                            )
                            .foregroundStyle(color)
                        }
                    }
                }
                if mode == .intraday, let previousClose, !values.isEmpty {
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
            .frame(height: 148)
            .clipped()
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.2), value: dayRange)

            volumeChart

            HStack {
                Text(axisStart)
                Spacer()
                Text(axisEnd)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(WhaleTheme.muted)
        }
    }

    private var volumeChart: some View {
        Chart {
            ForEach(Array(volumeItems.enumerated()), id: \.offset) { index, item in
                BarMark(
                    x: .value("序号", index),
                    y: .value("成交量", item.value),
                    width: .fixed(volumeWidth)
                )
                .foregroundStyle(item.up ? WhaleTheme.danger.opacity(0.55) : WhaleTheme.success.opacity(0.55))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 34)
        .clipped()
        .padding(.horizontal, 2)
        .overlay(alignment: .topLeading) {
            Text("成交量")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(WhaleTheme.muted.opacity(0.75))
                .padding(.leading, 2)
        }
    }

    private var axisStart: String {
        if mode == .intraday { return intraday.first?.time ?? "" }
        return dayPoints.first?.date ?? kline.first?.date ?? ""
    }

    private var axisEnd: String {
        if mode == .intraday { return intraday.last?.time ?? "" }
        return dayPoints.last?.date ?? kline.last?.date ?? ""
    }
}
