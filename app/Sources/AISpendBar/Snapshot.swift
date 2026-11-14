import AppKit
import SwiftUI

/// `AISpendBar --snapshot <dir>` renders the panel under a menu bar strip, with sample data,
/// to <dir>/panel-light.png and <dir>/panel-dark.png (for the README and demo video), then exits.
@MainActor
enum Snapshot {
    static func run(to dir: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let model = UsageModel(sample: sampleCosts())
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = SnapshotScene(label: model.menuLabel).environmentObject(model)
            write(render(view, appearance: appearance), to: dir.appendingPathComponent("panel-\(name).png"))
        }
    }

    /// 35 days of plausible spend for three tools, rising toward today.
    static func sampleCosts() -> [String: [String: Double]] {
        let today = Calendar.current.startOfDay(for: Date())
        let lastWeek: [[Double]] = [  // oldest -> today: claude, codex, gemini
            [18.40, 4.10, 0.00], [26.75, 6.30, 1.20], [22.10, 3.90, 0.80], [31.60, 7.45, 2.10],
            [12.30, 2.20, 0.00], [38.90, 8.15, 2.75], [41.27, 9.80, 3.12],
        ]
        var out: [String: [String: Double]] = [:]
        for back in 0..<35 {
            let day = UsageModel.dayKey(Calendar.current.date(byAdding: .day, value: -back, to: today)!)
            let v = back < 7 ? lastWeek[6 - back] : [20 + Double((back * 7) % 13), 5 + Double((back * 3) % 5), Double(back % 3)]
            out[day] = ["claude": v[0], "codex": v[1], "gemini": v[2]].filter { $0.value > 0 }
        }
        return out
    }

    /// Lays the view out in an offscreen window so native controls (switches, segmented picker) draw for real.
    static func render<V: View>(_ view: V, appearance: NSAppearance.Name) -> NSBitmapImageRep {
        // Draw controls as if the window were active (blue switches, not gray).
        let host = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 800), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        // Lay out twice so anything that changes on appear has settled before measuring.
        for _ in 0..<2 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            window.setContentSize(host.fittingSize)
        }
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print(url.path)
    }
}

/// A slice of the macOS menu bar with our item, and the panel hanging below it.
private struct SnapshotScene: View {
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 18) {
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(label).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Text("Sat 9:41")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16).frame(width: 520, height: 26, alignment: .trailing)
            .background(.bar)

            PanelView()
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
                .padding(.trailing, 60).padding(.bottom, 24)
        }
        .frame(width: 520)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
