import Foundation

enum Phase: String {
    case warmup = "Warm-up"
    case run = "Run"
    case walk = "Walk"
    case cooldown = "Cool-down"
}

struct Segment {
    let phase: Phase
    let seconds: Int
}

struct WeekPlan: Identifiable {
    let week: Int          // 0 = test session, not logged
    let summary: String
    let main: [Segment]
    var warmup = true

    var id: Int { week }

    var segments: [Segment] {
        warmup
            ? [Segment(phase: .warmup, seconds: 300)] + main + [Segment(phase: .cooldown, seconds: 300)]
            : main
    }

    /// run, walk, run, walk ... run — the last walk is dropped because the cool-down follows.
    static func intervals(run: Int, walk: Int, times: Int) -> [Segment] {
        let pairs = (0..<times).flatMap { _ in
            [Segment(phase: .run, seconds: run), Segment(phase: .walk, seconds: walk)]
        }
        return Array(pairs.dropLast())
    }

    static let all: [WeekPlan] = [
        WeekPlan(week: 1, summary: "Run 1 min / walk 2 min × 8", main: intervals(run: 60, walk: 120, times: 8)),
        WeekPlan(week: 2, summary: "Run 1.5 min / walk 2 min × 7", main: intervals(run: 90, walk: 120, times: 7)),
        WeekPlan(week: 3, summary: "Run 2 min / walk 2 min × 6", main: intervals(run: 120, walk: 120, times: 6)),
        WeekPlan(week: 4, summary: "Run 3 min / walk 2 min × 5", main: intervals(run: 180, walk: 120, times: 5)),
        WeekPlan(week: 5, summary: "Run 4 min / walk 1.5 min × 4", main: intervals(run: 240, walk: 90, times: 4)),
        WeekPlan(week: 6, summary: "Run 5 min / walk 1.5 min × 4", main: intervals(run: 300, walk: 90, times: 4)),
        WeekPlan(week: 7, summary: "Run 8 min / walk 1.5 min × 3", main: intervals(run: 480, walk: 90, times: 3)),
        WeekPlan(week: 8, summary: "Run 10 min / walk 1 min × 2, then run 5",
                 main: intervals(run: 600, walk: 60, times: 2) + [Segment(phase: .walk, seconds: 60), Segment(phase: .run, seconds: 300)]),
    ]

    static let test = WeekPlan(week: 0, summary: "Test cues",
                               main: intervals(run: 10, walk: 10, times: 2), warmup: false)
}
