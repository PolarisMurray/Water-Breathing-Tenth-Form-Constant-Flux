import SwiftUI

@main
struct FortyEightApp: App {
    @StateObject private var store = PlanStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.bridge)
        }
    }
}

enum AppTab: Hashable { case today, stats, memory }

struct RootView: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var bridge: ArtifactBridge
    @Environment(\.scenePhase) private var phase
    @State private var tab: AppTab = .today
    @State private var date = Dates.today
    @State private var userNav = false
    /// Cold-launch cut-in; starts true so the very first frame is already covered.
    @State private var intro = !UIAccessibility.isReduceMotionEnabled

    var body: some View {
        TabView(selection: $tab) {
            Tab("今日", systemImage: "circle.dashed.inset.filled", value: AppTab.today) {
                TodayView(date: $date, userNav: $userNav)
            }
            Tab("统计", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                StatsView(date: $date, tab: $tab)
            }
            Tab("记忆", systemImage: "brain.head.profile", value: AppTab.memory) {
                MemoryView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NowAccessory(date: $date, tab: $tab) }
        .background {
            // Keeps the bridge web view alive (and laid out) behind everything.
            WebHost(bridge: bridge, active: !bridge.showWeb)
                .opacity(0.011)
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $bridge.showWeb) { WebSheet() }
        .overlay { BurstOverlay() }
        .overlay(alignment: .top) { ToastView() }
        .overlay {
            if intro {
                LaunchIntro { withAnimation(.easeOut(duration: 0.2)) { intro = false } }
                    .transition(.opacity)
            }
        }
        .statusBarHidden(intro)
        .onChange(of: store.lastSync) {
            // Like the web app: at night, open tomorrow if today has no plan yet.
            let t = Dates.today, tm = Dates.add(t, 1)
            if !userNav, date == t, store.days[t] == nil, store.days[tm] != nil { date = tm }
        }
        .onChange(of: phase) { _, p in
            guard p == .active else { return }
            if bridge.state != .ready { bridge.reload() }
            if !userNav { date = Dates.today }
        }
    }
}

/// Floats above the tab bar: what this half hour is for, with one-tap "done as planned".
struct NowAccessory: View {
    @EnvironmentObject private var store: PlanStore
    @Binding var date: String
    @Binding var tab: AppTab

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { tl in
            let today = Dates.today, d = store.day(today), ctx = TimeCtx.of(today, at: tl.date)
            let p = d.info(d.plan[ctx.now]), recorded = d.actual[ctx.now] != nil
            HStack(spacing: 10) {
                Circle().fill(p?.color ?? .secondary).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p?.title ?? "空闲").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(Slot.range(ctx.now)) · 余 \(30 - ctx.minutes % 30) 分").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    var a = d.actual
                    a[ctx.now] = recorded ? nil : d.plan[ctx.now]
                    store.setActual(today, a)
                } label: {
                    Image(systemName: recorded ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(recorded ? Theme.good : .primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(p == nil)
                .accessibilityLabel(recorded ? "取消这一格的记录" : "这一格按计划完成")
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
            .onTapGesture { date = today; tab = .today }
        }
    }
}

struct WebSheet: View {
    @EnvironmentObject private var bridge: ArtifactBridge
    var body: some View {
        NavigationStack {
            WebHost(bridge: bridge, active: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(bridge.state == .needsSignIn ? "登录 claude.ai" : "四十八格 · 网页版")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { bridge.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("重新载入")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { bridge.showWeb = false }
                    }
                }
        }
    }
}

/// Honkai-style cut-in over the whole app on a cold launch. It follows the dark launch screen already covered,
/// thunder strikes, the title band syncs, then the bars fly off to reveal today. Tap to skip.
struct LaunchIntro: View {
    @EnvironmentObject private var store: PlanStore
    var done: () -> Void

    var body: some View {
        let today = Dates.today, d = store.day(today)
        let lv = Exp.level(Exp.series(store.days).last?.total ?? 0).n
        ZStack {
            AxisCutIn(kind: .launch, title: "四十八格", dateLine: TimeAxisScreen.stamp(today),
                      subtitle: d.title.isEmpty ? "新的一天" : d.title,
                      stats: "Lv.\(lv) · PLAN \(d.plan.compactMap { $0 }.count)",
                      kicker: "WELCOME BACK, CAPTAIN") { cue in
                if cue == .strike { Haptics.impact(.rigid) }
                if cue == .done { done() }
            }
            Color.clear.contentShape(.rect).ignoresSafeArea()
                .onTapGesture(perform: done)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("跳过开场动画")
        }
    }
}

/// "完成！" with manga focus lines when a task is ticked off.
struct BurstOverlay: View {
    @EnvironmentObject private var store: PlanStore
    @State private var show = false
    @State private var task: PlanTask?

    var body: some View {
        ZStack {
            if show, let task {
                SpeedLines()
                    .opacity(0.9)
                    .scaleEffect(show ? 1 : 1.8)
                    .transition(.opacity.combined(with: .scale(scale: 1.6)))
                VStack(spacing: 10) {
                    Text("完成！")
                        .font(.system(size: 76, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(.white)
                        .shadow(color: Theme.accent, radius: 0, x: 4, y: 4)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 24)
                    Text("\(task.title) · EXP +\(max(1, task.tokens) * Exp.perToken(task.load))")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                }
                .transition(.scale(scale: 2.2).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .sensoryFeedback(.success, trigger: task?.id)
        .onChange(of: store.burst?.id) {
            guard let t = store.burst else { return }
            task = t
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { show = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.3)) { show = false }
                store.burst = nil
            }
        }
    }
}

struct ToastView: View {
    @EnvironmentObject private var store: PlanStore
    var body: some View {
        Group {
            if let msg = store.toast {
                Text(msg)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation { store.toast = nil }
                    }
            }
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.4), value: store.toast)
    }
}
