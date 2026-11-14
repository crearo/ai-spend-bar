import AIUsageCore
import Charts
import ServiceManagement
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var model: UsageModel
    @State private var selectedDay: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only ask about start at login when it isn't set up yet; it's the next thing to do, so it goes first.
            if model.loginStatus != .enabled {
                loginWarning
            }

            if let v = model.updateAvailable {
                Label("Update available (\(Version.display(v))) — run npx ai-usage-bar", systemImage: "arrow.down.circle")
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
                        .foregroundStyle(model.isCounted(tool) ? .primary : .secondary)
                    // No switch for a lone tool: turning it off would just show $0.
                    if model.tools.count > 1 {
                        Toggle("", isOn: Binding(
                            get: { model.isCounted(tool) },
                            set: { on in if on { model.excluded.remove(tool) } else { model.excluded.insert(tool) } }
                        )).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            .disabled(!model.canToggle(tool))
                            .help(model.canToggle(tool) ? "Count in total" : "At least one tool has to count")
                    }
                }
                .font(.callout)
            }
        }
    }

    private var chart: some View {
        let week = model.lastWeek
        let today = UsageModel.dayKey(Date())
        let focusKey = selectedDay ?? today
        let focus = week.first { $0.key == focusKey }
        return VStack(alignment: .leading, spacing: 4) {
            // Hover or click a bar to see that day; defaults to today.
            if let f = focus {
                Text("\(f.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(money(f.cost))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart(week, id: \.key) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Cost", d.cost))
                    .foregroundStyle(d.key == focusKey ? Color.accentColor : Color.secondary.opacity(0.45))
                    .cornerRadius(3)
                    .annotation(position: .top, spacing: 2) {
                        if d.cost >= 0.5 {
                            Text("$\(Int(d.cost.rounded()))").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p): selectedDay = dayKey(at: p, proxy: proxy, geo: geo)
                            case .ended: selectedDay = nil
                            }
                        }
                        .gesture(SpatialTapGesture().onEnded { selectedDay = dayKey(at: $0.location, proxy: proxy, geo: geo) })
                }
            }
            .frame(height: 100)
        }
    }

    private func dayKey(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> String? {
        let x = point.x - geo[proxy.plotAreaFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        let key = UsageModel.dayKey(date)
        return model.lastWeek.contains { $0.key == key } ? key : nil
    }

    // The whole card is the button: clicking it is the fix.
    private var loginWarning: some View {
        let needsApproval = model.loginStatus == .requiresApproval
        return Button {
            if needsApproval { SMAppService.openSystemSettingsLoginItems() } else { model.setStartAtLogin(true) }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(needsApproval ? "Tap to approve in Login Items" : "Tap to start after restart")
                        .font(.callout.weight(.semibold))
                    Text(needsApproval
                         ? "macOS needs your OK before it can start at login."
                         : "So it's always in your menu bar, even after a reboot.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.35)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
