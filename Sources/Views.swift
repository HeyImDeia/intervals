import SwiftUI

@main
struct IntervalsApp: App {
    @StateObject private var engine = WorkoutEngine()

    var body: some Scene {
        WindowGroup {
            Group {
                if engine.plan != nil { WorkoutView() } else { HomeView() }
            }
            .environmentObject(engine)
        }
    }
}

private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

private func color(_ p: Phase) -> Color {
    switch p {
    case .run: return .orange
    case .walk: return .green
    case .warmup, .cooldown: return .blue
    }
}

struct HomeView: View {
    @EnvironmentObject var engine: WorkoutEngine

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WeekPlan.all) { plan in
                        Button { engine.start(plan) } label: { row(plan) }
                    }
                } footer: {
                    Text("Every session adds a 5 min warm-up walk and a 5 min cool-down. Start your podcast first, then tap a week and lock the phone.")
                }

                Section {
                    Button("Test cues (30 s)") { engine.start(.test) }
                } footer: {
                    Text("During a cue, your podcast or music gets quieter, then returns to full volume.")
                }

                if !engine.log.isEmpty {
                    Section("History") {
                        ForEach(engine.log.reversed()) { e in
                            HStack {
                                Text(e.date, format: .dateTime.weekday().day().month().hour().minute())
                                Spacer()
                                Text("W\(e.week) · \(e.minutes) min\(e.completed ? "" : " · stopped")")
                                    .foregroundStyle(e.completed ? Color.secondary : Color.red)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Walk / Run")
        }
    }

    private func row(_ p: WeekPlan) -> some View {
        let done = engine.log.filter { $0.week == p.week && $0.completed }.count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week \(p.week)").font(.headline).foregroundStyle(.primary)
                Text(p.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(min(done, 3))/3")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(done >= 3 ? .green : .secondary)
        }
    }
}

struct WorkoutView: View {
    @EnvironmentObject var engine: WorkoutEngine
    @State private var confirmStop = false

    var body: some View {
        let seg = engine.current
        VStack(spacing: 20) {
            Spacer()
            if engine.finished {
                Text("Done").font(.system(size: 56, weight: .heavy))
                Text("\(Int(engine.total / 60)) minutes. Report it to Claude.").foregroundStyle(.secondary)
            } else {
                Text(engine.isPaused ? "Paused" : seg.phase.rawValue)
                    .font(.system(size: 52, weight: .heavy))
                Text(clock(engine.remaining))
                    .font(.system(size: 104, weight: .bold, design: .rounded).monospacedDigit())
                if let label = engine.intervalLabel { Text(label).font(.title3.weight(.semibold)) }
                if let next = engine.next {
                    Text("Next: \(next.phase.rawValue) \(clock(next.seconds))").foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                ProgressView(value: min(engine.elapsed, engine.total), total: engine.total)
                    .tint(color(seg.phase))
                Text("\(clock(engine.totalRemaining)) left").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            controls
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color(seg.phase).opacity(engine.finished ? 0 : 0.22).ignoresSafeArea())
        .animation(.easeInOut, value: engine.index)
    }

    @ViewBuilder private var controls: some View {
        if engine.finished {
            Button("Back") { engine.stop() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            HStack(spacing: 16) {
                Button { confirmStop = true } label: { Image(systemName: "stop.fill").frame(width: 56, height: 44) }
                    .buttonStyle(.bordered)
                Button { engine.togglePause() } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                Button { engine.skip() } label: { Image(systemName: "forward.end.fill").frame(width: 56, height: 44) }
                    .buttonStyle(.bordered)
            }
            .font(.title2)
            .controlSize(.large)
            .confirmationDialog("End this workout?", isPresented: $confirmStop) {
                Button("End workout", role: .destructive) { engine.stop() }
            }
        }
    }
}
