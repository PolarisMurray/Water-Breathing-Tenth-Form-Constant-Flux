import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var bridge: ArtifactBridge
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("长期记忆").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Claude 记得的你").font(.system(size: 32, weight: .black, design: .rounded))
                        Text("每次排程，Claude 都会先读这里和最近 7 天的执行记录。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    list("关于你", store.profile.about, empty: "还没有记录")
                    list("排程规则", store.profile.rules, empty: "还没有规则")
                    list("目标", store.profile.goals, empty: "还没有目标")
                    notes
                    sync
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { SkyBackground() }
            .navigationTitle("记忆")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func list(_ title: String, _ items: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionTitle()
            if items.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(items, id: \.self) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent2).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    Text(s).font(.subheadline).foregroundStyle(.primary.opacity(0.85))
                }
            }
        }
        .glassCard()
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("告诉 Claude 的事").sectionTitle()
            Text("比如：周三下午有课 / 晚上 11 点后效率很低").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("写一条", text: $draft)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.05)))
                Button("记住", action: add).buttonStyle(.glassProminent).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(store.profile.notes.reversed(), id: \.self) { n in
                HStack(alignment: .top) {
                    Text(n.text).font(.subheadline)
                    Spacer()
                    if let at = n.at, let d = ISO8601DateFormatter().date(from: at) {
                        Text("\(Dates.cal.component(.month, from: d))/\(Dates.cal.component(.day, from: d))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Menu {
                        Button("删除", systemImage: "trash", role: .destructive) { store.deleteMemoryNote(n) }
                    } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                    .tint(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.05)))
            }
        }
        .glassCard()
    }

    private func add() {
        let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        store.addMemoryNote(v); draft = ""; store.toast = "记住了"
    }

    private var sync: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("同步").sectionTitle()
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.subheadline)
            }
            if let t = store.lastSync { Text("上次同步 \(t.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            if store.pendingCount > 0 { Text("\(store.pendingCount) 条修改等待上传").font(.caption).foregroundStyle(Theme.warn) }
            Text("数据存在 claude.ai 的 Artifact 数据库里，网页版和手机 App 共用。App 通过内置的 claude.ai 网页读写它，所以需要在 App 里登录一次。")
                .font(.caption).foregroundStyle(.secondary)
            Text(bridge.artifactURL.absoluteString).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
            HStack {
                Button("打开网页版") { bridge.showWeb = true }.buttonStyle(.glass)
                Button("重新连接") { bridge.reload() }.buttonStyle(.glass)
            }
        }
        .glassCard()
    }

    private var statusText: String {
        switch bridge.state {
        case .ready: return "已连接"
        case .connecting: return "连接中…"
        case .needsSignIn: return "需要登录 claude.ai"
        case .stalled(let why): return why
        }
    }
    private var statusColor: Color {
        switch bridge.state {
        case .ready: return Theme.good
        case .connecting: return Theme.warn
        default: return Theme.bad
        }
    }
}
