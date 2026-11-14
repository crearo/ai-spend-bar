import AIUsageCore
import Charts
import ServiceManagement
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let v = model.updateAvailable {
                Label("Update available (\(v)) — run npx ai-usage-bar", systemImage: "arrow.down.circle")
                    .font(.caption).padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            Picker("", selection: $model.range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if model.hasData {
                VStack(alignment: .leading, spacing: 2) {
                    Text(money(model.total(model.range)))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("API value · estimated by ccusage").font(.caption).foregroundStyle(.secondary)
                }
                toolRows
                chart
            } else if let e = model.error {
                Label(e, systemImage: "exclamationmark.triangle").font(.callout)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Loading usage…").foregroundStyle(.secondary) }
            }

            if model.hasData, let e = model.error {
                Text("Last refresh failed: \(e)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }

            Divider()
            loginToggle
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refreshLoginStatus() }
    }

    private var toolRows: some View {
        VStack(spacing: 6) {
            ForEach(model.tools, id: \.self) { tool in
                HStack {
                    Text(Tools.name(tool))
                    Spacer()
                    Text(money(model.cost(tool: tool, range: model.range))).monospacedDigit()
                        .foregroundStyle(model.excluded.contains(tool) ? .secondary : .primary)
                    Toggle("", isOn: Binding(
                        get: { !model.excluded.contains(tool) },
                        set: { on in if on { model.excluded.remove(tool) } else { model.excluded.insert(tool) } }
                    )).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
                .font(.callout)
            }
        }
    }

    private var chart: some View {
        let today = UsageModel.dayKey(Date())
        return Chart(model.lastWeek, id: \.key) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Cost", d.cost))
                .foregroundStyle(d.key == today ? Color.accentColor : Color.secondary.opacity(0.45))
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine()
                AxisValueLabel { if let c = v.as(Double.self) { Text("$\(Int(c))") } }
            }
        }
        .frame(height: 90)
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Start at login", isOn: Binding(
                get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                set: { model.setStartAtLogin($0) }
            ))
            if model.loginStatus == .requiresApproval {
                HStack {
                    Text("Needs approval in Login Items.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Settings") { SMAppService.openSystemSettingsLoginItems() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.isRefreshing {
                Text("Refreshing…")
            } else if let t = model.lastUpdated {
                TimelineView(.periodic(from: .now, by: 5)) { ctx in Text("Updated \(ago(t, ctx.date))") }
            }
            Spacer()
            Button("Refresh") { model.refresh() }.disabled(model.isRefreshing)
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.caption).foregroundStyle(.secondary).controlSize(.small)
    }

    private func money(_ v: Double) -> String { String(format: "$%.2f", v) }

    private func ago(_ t: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(t)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }
}
