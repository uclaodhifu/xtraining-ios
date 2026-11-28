import ActivityKit
import SwiftUI
import WidgetKit

@main
struct XTrainingWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivity() }
}

struct RestLiveActivity: Widget {
    private let accent = Color(red: 0.07, green: 0.72, blue: 0.53)   // 和 App 里的休息卡一样的绿色

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { ctx in
            // 锁屏
            let s = ctx.state
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2.bold()).foregroundStyle(accent)
                    .frame(width: 44, height: 44).background(accent.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.exercise.isEmpty ? "组间休息" : "组间休息 · \(s.exercise)")
                        .font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                    ProgressView(timerInterval: s.start...s.end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(accent)
                    if let b = s.bpm {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill").foregroundStyle(.red)
                            Text("\(b)").font(.subheadline.bold()).monospacedDigit().foregroundStyle(.white)
                            if let l = s.line { Text("降到 \(l) 就响").font(.caption).foregroundStyle(.white.opacity(0.6)) }
                        }
                    }
                }
                Text(timerInterval: s.start...s.end, countsDown: true)
                    .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).multilineTextAlignment(.trailing).frame(width: 96)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("休息", systemImage: "timer").font(.headline).foregroundStyle(accent).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: s.start...s.end, countsDown: true)
                        .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.trailing).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if !s.exercise.isEmpty { Text("下一组：\(s.exercise)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if let b = s.bpm {
                                Label("\(b)" + (s.line.map { " → \($0)" } ?? ""), systemImage: "heart.fill")
                                    .font(.caption.bold()).monospacedDigit().foregroundStyle(.red)
                            }
                        }
                        ProgressView(timerInterval: s.start...s.end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(accent)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if let b = s.bpm {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").foregroundStyle(.red)
                        Text("\(b)").font(.caption.bold()).monospacedDigit()
                    }
                } else {
                    Image(systemName: "timer").foregroundStyle(accent)
                }
            } compactTrailing: {
                Text(timerInterval: s.start...s.end, countsDown: true)
                    .monospacedDigit().font(.caption.bold()).frame(width: 40).foregroundStyle(accent)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
        }
    }
}
