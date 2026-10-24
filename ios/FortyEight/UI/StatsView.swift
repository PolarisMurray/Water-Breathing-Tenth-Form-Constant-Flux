import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: PlanStore
    @Binding var date: String
    @Binding var tab: AppTab
    @State private var pickedDay: String?

    private struct Row: Identifiable { let id: String; let label: String; let doc: DayDoc; let m: Metrics }

    var body: some View {
        let rows: [Row] = (0..<14).reversed().map { k in
            let ds = Dates.add(date, -k), d = store.day(ds)
            return Row(id: ds, label: "\(Dates.cal.component(.day, from: Dates.date(ds)))", doc: d, m: Metrics(d, elapsed: TimeCtx.of(ds).elapsed))
        }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Dates.label(rows.first!.id)) – \(Dates.label(date))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("执行与强度").font(.system(size: 32, weight: .black, design: .rounded))
                        Text("强度 = Σ(负荷 × 格数) ÷ 清醒格数 × 50。40 以下轻松，60 以上高压，80 以上冲刺。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    ExpCard(points: Exp.series(store.days))
                    tiles(rows)
                    intensityChart(rows)
                    matchChart(rows)
                    categoryCard(rows.last!)
                    deviationCard(rows.last!)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background { SkyBackground() }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pickedDay) { _, d in
                if let d, let r = rows.first(where: { $0.label == d }) { date = r.id; tab = .today; pickedDay = nil }
            }
        }
    }

    private func tiles(_ rows: [Row]) -> some View {
        let rec = rows.filter { $0.m.recorded >= 8 }
        func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        let aMatch = avg(rec.compactMap { $0.m.match }), aInt = avg(rec.compactMap { $0.m.actIntensity.map(Double.init) })
        let aSleep = avg(rec.filter { $0.m.actSleep > 0 }.map { Double($0.m.actSleep) })
        let doneT = rows.reduce(0) { acc, r in acc + r.doc.tasks.filter { r.doc.done[$0.id] == true }.count }
        let allT = rows.reduce(0) { $0 + $1.doc.tasks.count }
        let items: [(String, String, String)] = [
            ("平均吻合度", aMatch.map { "\(Int($0 * 100))%" } ?? "—", "\(rec.count) 天有记录"),
            ("平均实际强度", aInt.map { "\(Int($0))" } ?? "—", aInt.flatMap { Level.of(Int($0))?.name } ?? "记录后显示"),
            ("平均睡眠", aSleep.map { Dates.hours($0) } ?? "—", "目标 7.5h"),
            ("实际工作", Dates.hours(rows.reduce(0) { $0 + $1.m.actWork }), "\(rows.filter { $0.m.planWork > 0 }.count) 天有计划"),
            ("任务完成", allT > 0 ? "\(doneT)/\(allT)" : "—", allT > 0 ? "\(doneT * 100 / allT)%" : "还没有任务"),
            ("摸鱼", Dates.hours(rows.reduce(0) { $0 + $1.m.slack }), "14 天合计"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
            ForEach(items, id: \.0) { k, v, s in
                VStack(alignment: .leading, spacing: 3) {
                    Text(k).font(.caption).foregroundStyle(.secondary)
                    Text(v).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private func intensityChart(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每日强度").sectionTitle()
            Chart {
                ForEach(rows) { r in
                    if r.m.planWork > 0 {
                        BarMark(x: .value("日", r.label), y: .value("强度", r.m.planIntensity), width: .ratio(0.32))
                            .foregroundStyle(by: .value("类型", "计划")).position(by: .value("类型", "计划"))
                            .cornerRadius(4)
                    }
                    if let a = r.m.actIntensity {
                        BarMark(x: .value("日", r.label), y: .value("强度", a), width: .ratio(0.32))
                            .foregroundStyle(by: .value("类型", "实际")).position(by: .value("类型", "实际"))
                            .cornerRadius(4)
                    }
                }
                RuleMark(y: .value("冲刺线", 80)).foregroundStyle(Theme.bad.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartForegroundStyleScale(["计划": Color.secondary.opacity(0.5), "实际": Theme.accent])
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 40, 60, 80, 100]) }
            .chartXSelection(value: $pickedDay)
            .frame(height: 190)
            Text("点某一天跳到那天。虚线 = 冲刺线 80。").font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func matchChart(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("计划吻合度").sectionTitle()
                Spacer()
                Text("同任务记 1，同类记 0.5").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(rows) { r in
                    if let v = r.m.match {
                        LineMark(x: .value("日", r.label), y: .value("吻合度", v * 100))
                            .foregroundStyle(Theme.accent2).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("日", r.label), y: .value("吻合度", v * 100))
                            .foregroundStyle(Theme.accent2).symbolSize(60)
                    }
                }
            }
            .chartXScale(domain: rows.map(\.label))
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") }
                }
            }
            .chartXSelection(value: $pickedDay)
            .frame(height: 150)
        }
        .glassCard()
    }

    private func categoryCard(_ r: Row) -> some View {
        let cats = Cat.allCases.filter { (r.m.planCat[$0] ?? 0) + (r.m.actCat[$0] ?? 0) > 0 }
        let mx = max(1, cats.map { max(r.m.planCat[$0] ?? 0, r.m.actCat[$0] ?? 0) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("类别占比 · \(Dates.label(r.id))").sectionTitle()
                Spacer()
                Text("淡 = 计划，实 = 实际").font(.caption).foregroundStyle(.secondary)
            }
            if cats.isEmpty { Text("这一天没有数据。").foregroundStyle(.secondary) }
            ForEach(cats, id: \.self) { c in
                let p = r.m.planCat[c] ?? 0, a = r.m.actCat[c] ?? 0
                HStack(spacing: 10) {
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(c.color).frame(width: 10, height: 10); Text(c.name) }
                        .font(.footnote).frame(width: 64, alignment: .leading)
                    GeometryReader { g in
                        VStack(alignment: .leading, spacing: 3) {
                            UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4).fill(c.color.opacity(0.35)).frame(width: max(2, g.size.width * CGFloat(p) / CGFloat(mx)))
                            UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4).fill(c.color).frame(width: max(2, g.size.width * CGFloat(a) / CGFloat(mx)))
                        }
                    }
                    .frame(height: 17)
                    Text("\(p) → \(a) 格").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                }
            }
        }
        .glassCard()
    }

    private func deviationCard(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("任务偏差").sectionTitle()
            if r.doc.tasks.isEmpty { Text("这一天没有任务。").foregroundStyle(.secondary) }
            else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("任务"); Text("计划").gridColumnAlignment(.trailing); Text("实际").gridColumnAlignment(.trailing); Text("偏差").gridColumnAlignment(.trailing)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(r.doc.tasks) { t in
                        let pt = r.m.perTask[t.id] ?? (0, 0), dv = pt.act - pt.plan
                        GridRow {
                            HStack(spacing: 4) {
                                if r.doc.done[t.id] == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good) }
                                Text(t.title).lineLimit(1)
                            }
                            Text("\(pt.plan)"); Text("\(pt.act)")
                            Text(dv > 0 ? "+\(dv)" : "\(dv)").foregroundStyle(dv > 0 ? Theme.bad : dv < 0 ? Theme.accent2 : .secondary)
                        }
                        .font(.footnote).monospacedDigit()
                    }
                }
            }
        }
        .glassCard()
    }
}

/// Deflating EXP balance (curve) over the last 30 days, with each day's gain as bars underneath.
struct ExpCard: View {
    let points: [Exp.Point]
    @State private var picked: Date?

    private func r(_ v: Double) -> Int { Int(v.rounded()) }
    private static func axisLabel(_ v: AxisValue) -> some View {
        Text((v.as(Double.self) ?? 0).formatted(.number.precision(.fractionLength(0))))
            .frame(width: 42, alignment: .leading)
    }

    var body: some View {
        let shown = Array(points.suffix(30))
        let xDomain = shown.isEmpty ? Date()...Date() : Dates.date(shown.first!.date)...Dates.date(Dates.add(shown.last!.date, 1))
        let sel = picked.flatMap { p in shown.first { Dates.cal.isDate(Dates.date($0.date), inSameDayAs: p) } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("经验曲线").sectionTitle()
                Spacer()
                Text("完成任务得经验 · 每晚 ×0.95").font(.caption).foregroundStyle(.secondary)
            }
            if let last = points.last {
                let lv = Exp.level(last.total)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Lv.\(lv.n)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing))
                    Text("\(r(last.total)) EXP").font(.title3.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text("最高 \(r(points.map(\.total).max() ?? 0))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                LevelBar(progress: lv.progress)
                Text("距 Lv.\(lv.n + 1) 还差 \(r(lv.hi - last.total)) · \(Dates.label(last.date)) +\(last.gain) · 下一天开始前蒸发 −\(r(last.total * Exp.rate))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Chart {
                    ForEach(shown) { p in
                        AreaMark(x: .value("日期", Dates.date(p.date), unit: .day), y: .value("累计经验", p.total))
                            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.4), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("日期", Dates.date(p.date), unit: .day), y: .value("累计经验", p.total))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                    if let s = sel {
                        RuleMark(x: .value("日期", Dates.date(s.date), unit: .day))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Dates.label(s.date)).font(.caption.weight(.semibold))
                                    Text("获得 +\(s.gain)").foregroundStyle(Theme.accent2)
                                    Text("蒸发 −\(r(s.decay))").foregroundStyle(.secondary)
                                    Text("累计 \(r(s.total))")
                                }
                                .font(.caption2).monospacedDigit()
                                .padding(8)
                                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                            }
                    } else if let p = shown.last {
                        PointMark(x: .value("日期", Dates.date(p.date), unit: .day), y: .value("累计经验", p.total))
                            .foregroundStyle(Theme.accent).symbolSize(70)
                    }
                }
                .chartXSelection(value: $picked)
                .chartXScale(domain: xDomain)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day()) } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in AxisGridLine(); AxisValueLabel { Self.axisLabel(v) } } }
                .frame(height: 180)
                Text("当日获得").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Chart(shown) { p in
                    BarMark(x: .value("日期", Dates.date(p.date), unit: .day), y: .value("获得", Double(p.gain)))
                        .foregroundStyle(Theme.accent2)
                        .cornerRadius(3)
                }
                .chartXScale(domain: xDomain)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { v in AxisGridLine(); AxisValueLabel { Self.axisLabel(v) } } }
                .frame(height: 60)
                Text("按住曲线拖动可以看每天的获得、蒸发和累计。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("完成第一个任务后，这里开始画经验曲线。").foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }
}

struct LevelBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: 8)
        .animation(.spring(duration: 0.6), value: progress)
    }
}
