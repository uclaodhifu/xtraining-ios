import ActivityKit
import Foundation

// 组间休息的实时活动（锁屏 + 灵动岛），App 和小组件共用
struct RestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var exercise: String
        var bpm: Int? = nil      // 实时心率（有耳机/手表/手环时）
        var line: Int? = nil     // 恢复线
    }
}
