import AVFoundation
import Foundation

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let week: Int
    let minutes: Int
    let completed: Bool
}

/// Timing is derived from wall-clock time (start date minus paused time), so a late
/// timer tick never makes the workout drift. A silent looping track keeps the app
/// running with the screen locked; voice cues mix over whatever else is playing.
@MainActor
final class WorkoutEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var plan: WeekPlan?
    @Published private(set) var index = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isPaused = false
    @Published private(set) var finished = false
    @Published private(set) var log: [LogEntry] = []

    private var segments: [Segment] = []
    private var ends: [TimeInterval] = []        // cumulative end time of each segment
    private var startedAt = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var timer: Timer?

    private let session = AVAudioSession.sharedInstance()
    private var keepAlive: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")

    override init() {
        super.init()
        speech.delegate = self
        speech.usesApplicationAudioSession = true   // speak through our .playback session, which ignores the silent switch
        if let data = UserDefaults.standard.data(forKey: "log"),
           let saved = try? JSONDecoder().decode([LogEntry].self, from: data) {
            log = saved
        }
        // A phone call or Siri stops our audio; restart it when the interruption ends.
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                guard let self, self.plan != nil, !self.finished else { return }
                self.startAudio()
            }
        }
    }

    // MARK: - State for the UI

    var current: Segment { segments.indices.contains(index) ? segments[index] : Segment(phase: .walk, seconds: 0) }
    var next: Segment? { segments.indices.contains(index + 1) ? segments[index + 1] : nil }
    var total: TimeInterval { ends.last ?? 1 }
    var remaining: Int { finished || ends.isEmpty ? 0 : max(0, Int(ceil(ends[index] - elapsed))) }
    var totalRemaining: Int { max(0, Int(ceil(total - elapsed))) }

    var intervalLabel: String? {
        guard current.phase == .run || current.phase == .walk else { return nil }
        let runs = segments.filter { $0.phase == .run }.count
        let done = segments[...index].filter { $0.phase == .run }.count
        return "Interval \(done) of \(runs)"
    }

    // MARK: - Controls

    func start(_ p: WeekPlan) {
        plan = p
        segments = p.segments
        var t = 0.0
        ends = segments.map { t += Double($0.seconds); return t }
        startedAt = Date(); pausedAt = nil; pausedTotal = 0
        index = 0; elapsed = 0; isPaused = false; finished = false

        startAudio()
        announce()
        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func togglePause() {
        guard !finished else { return }
        if let p = pausedAt {
            pausedTotal += Date().timeIntervalSince(p)
            pausedAt = nil; isPaused = false
        } else {
            pausedAt = Date(); isPaused = true
        }
    }

    func skip() {
        guard !finished, !ends.isEmpty else { return }
        pausedTotal -= ends[index] - elapsed + 0.001   // jump the clock to the end of this segment
        tick()
    }

    /// Stops a running workout, or closes the finished screen.
    func stop() {
        if !finished { record(completed: false) }
        timer?.invalidate(); timer = nil
        plan = nil; finished = false
        speech.stopSpeaking(at: .immediate)
        stopAudio()
    }

    // MARK: - Timing

    private func tick() {
        guard plan != nil, !finished else { return }
        elapsed = (pausedAt ?? Date()).timeIntervalSince(startedAt) - pausedTotal
        guard elapsed < total else { complete(); return }
        let i = ends.firstIndex { elapsed < $0 } ?? index
        if i != index {
            index = i
            announce()
        }
    }

    private func complete() {
        elapsed = total
        finished = true
        timer?.invalidate(); timer = nil
        record(completed: true)
        speak("Done")                   // audio is released once this finishes
    }

    private func record(completed: Bool) {
        guard let plan, plan.week > 0, elapsed >= 60 else { return }
        log.append(LogEntry(date: startedAt, week: plan.week, minutes: Int(elapsed / 60), completed: completed))
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: "log")
        }
    }

    // MARK: - Cues

    /// One word per change. Warm-up and cool-down are walks, so they say "Walk".
    private func announce() {
        speak(current.phase == .run ? "Run" : "Walk")
    }

    private func speak(_ text: String) {
        if !speech.isSpeaking { setDucking(true) }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.preUtteranceDelay = 0.3          // give the podcast time to fade down first
        speech.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.speechEnded() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.speechEnded() }
    }

    private func speechEnded() {
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !speech.isSpeaking else { return }        // more cues queued
            if plan == nil || finished { stopAudio() } else { setDucking(false) }
        }
    }

    // MARK: - Audio session

    /// Cues lower the volume of whatever is playing (podcast or music); nothing is paused.
    private func configure(duck: Bool) {
        let options: AVAudioSession.CategoryOptions = duck ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
        try? session.setCategory(.playback, mode: .default, options: options)
        try? session.setActive(true)
    }

    /// Ducking only changes when the session is (re)activated, so cycle it.
    /// Deactivating with notifyOthers is what tells the podcast app to come back up.
    private func setDucking(_ on: Bool) {
        keepAlive?.pause()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        configure(duck: on)
        if plan != nil { keepAlive?.play() }
    }

    private func startAudio() {
        configure(duck: false)
        if keepAlive == nil, let url = Bundle.main.url(forResource: "silence", withExtension: "wav") {
            keepAlive = try? AVAudioPlayer(contentsOf: url)
            keepAlive?.numberOfLoops = -1
        }
        keepAlive?.play()
    }

    private func stopAudio() {
        keepAlive?.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
