import Foundation
import AVFoundation
import Speech

/// Dictation (ported as-is from Mavis final launch, App/Sources/Dictation.swift): the microphone feeds speech recognition (on this Mac when its speech model is installed,
/// otherwise Apple's dictation service, like the system's own dictation). Words arrive as you speak and a rolling
/// set of levels drives the voice glow. When you stop, it waits for the recognizer's final words — they trail the
/// voice by up to a second — before handing them over. After a pause the recognizer starts a new utterance whose
/// results hold only the new words, so finished utterances are kept and the whole sentence is handed over.
/// Permission is asked the first time; if it's refused, the box says so plainly. Every step is written to
/// ~/Library/Logs/Agent Lab/talk.log.
@MainActor final class Dictation: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var listening = false
    /// macOS is still asking for microphone or speech permission.
    @Published private(set) var awaitingPermission = false
    /// The last moment the microphone heard something louder than the room (for hands-free ending).
    private(set) var lastVoice = Date.distantPast
    /// Since when the microphone has been clearly loud without a break (above −34 dBFS, after echo cancellation): a
    /// voice in the room, not the residue of the speakers (which stays under about −39). Nil when it's quiet.
    private(set) var loudSince: Date?
    /// After you stop: the last words are still being recognised.
    @Published private(set) var finishing = false
    @Published private(set) var transcript = ""
    /// Words from utterances the recognizer has finished in this listen (it starts afresh after a pause).
    private var kept = ""
    /// The last utterance kept: the final result can restate it, which must not add it twice.
    private var ended = ""
    /// The latest words of the utterance in progress.
    private var utterance = ""
    @Published private(set) var levels: [Float] = Array(repeating: 0.05, count: 18)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var failure: String?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var clock: Timer?
    private var started = Date()
    private var onDevice = true
    private var waiting: ((String) -> Void)?
    private var waitTimeout: Task<Void, Never>?
    private var session = 0
    /// The system said Siri and Dictation are disabled.
    private var dictationOff = false
    /// The request audio goes to, as the audio thread sees it. Set through `current`, which takes the feed lock, since
    /// the microphone stays open across turns in voice mode and the main thread swaps it while audio keeps arriving.
    nonisolated(unsafe) private var _current: SFSpeechAudioBufferRecognitionRequest?
    private var current: SFSpeechAudioBufferRecognitionRequest? {
        get { feedLock.lock(); defer { feedLock.unlock() }; return _current }
        set { feedLock.lock(); _current = newValue; feedLock.unlock() }
    }
    /// Test runs only (`--test-voice`): the next listen hears this audio file instead of the microphone, at speaking pace.
    static var testAudio: URL?
    /// Voice mode: the microphone stays open from turn to turn (the engine keeps running; each turn is its own
    /// recognition request and recording), so nothing restarts between your sentences. The Mac's own audio is never
    /// touched: no voice processing, no playing through the engine — both change the system's sound (voice
    /// processing lowers everything else, like a call) and were tried and taken out.
    static var continuous = false
    /// A microphone that hands over more than one channel: the recognizer gets the first. Set when
    /// the tap is installed, read on the audio thread.
    nonisolated(unsafe) private var mono: AVAudioFormat?
    private var testFeed: Task<Void, Never>?

    /// Echo cancellation: macOS's voice processing takes whatever the speakers play out of the microphone — Mavis's
    /// voice, music, a video, any app (measured on this Mac with `--probe-echo`: about 30 dB of each removed) — so only
    /// you are heard, and Mavis never hears herself. Its ducking of other audio is turned down to the minimum, so the
    /// Mac's sound isn't lowered like a call (the muffle stays the one thing that changes it). Once per engine.
    /// Off: macOS reconfigures the audio devices when it starts and stops, which knocks out the muffle's own device
    /// mid-glide (measured with `--probe-muffle-level --with-listen`: a dropout going under, a jump back to full
    /// volume coming out). The muffle comes first; echo cancellation returns once it can run beside it.
    static var echoCancellation = false
    private var echoCancelled = false
    private func cancelEcho() {
        guard Self.echoCancellation, !echoCancelled else { return }
        do { try engine.inputNode.setVoiceProcessingEnabled(true) } catch { log("echo cancellation unavailable: \(error.localizedDescription)"); return }
        if #available(macOS 14.0, *) {
            engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        echoCancelled = true
        log("echo cancellation on")
    }

    func start() {
        guard !active else { log("start ignored: already active"); return }
        dictationOff = false
        session += 1
        active = true; listening = false; finishing = false; transcript = ""; kept = ""; ended = ""; utterance = ""; failure = nil; elapsed = 0
        levels = Array(repeating: 0.05, count: levels.count)
        let id = session
        log("start #\(id)")
        awaitingPermission = true
        Task {
            let (speech, mic) = await Self.authorize()
            awaitingPermission = false
            log("permissions: speech=\(speech) mic=\(mic)")
            guard self.session == id, self.active else { return }
            guard speech, mic else {
                failure = "Allow Microphone and Speech Recognition for Agent Lab in System Settings › Privacy & Security."
                return
            }
            do { try begin(onDevice: true) } catch {
                log("engine start failed: \(error.localizedDescription)")
                failure = "Couldn't start the microphone. Check that one is connected, then try again."
                stopAudio()
            }
        }
    }

    /// Stops listening and, once the final words are in (or 1.5 s pass), hands them over.
    func finish(_ done: @escaping (String) -> Void) {
        guard active else { done(transcript); return }
        log("finish requested; words so far: \"\(transcript)\"")
        if task == nil {                       // never got going (permissions, no mic): nothing to wait for
            stopAudio(); active = false; done(transcript); return
        }
        finishing = true
        waiting = done
        testFeed?.cancel(); testFeed = nil
        clock?.invalidate(); clock = nil
        current = nil                           // the tap feeds nothing until the next listen
        if !Self.continuous { if engine.isRunning { engine.stop() }; removeTap() }
        request?.endAudio()                     // the recognizer now delivers its final result
        listening = false
        waitTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.log("final result timed out")
            self?.deliver()
        }
    }

    /// Immediately: stop and return the words so far (used where waiting isn't wanted).
    func finish() -> String {
        let words = transcript
        stopAudio()
        active = false
        return words
    }

    func cancel() {
        log("cancel")
        waitTimeout?.cancel(); waiting = nil
        stopAudio()
        transcript = ""; kept = ""; ended = ""; utterance = ""
        finishing = false
        active = false
    }

    private func deliver() {
        guard let done = waiting else { return }
        waiting = nil
        waitTimeout?.cancel()
        let words = transcript
        log("deliver: \"\(words)\"")
        stopAudio()
        finishing = false
        active = false
        done(words)
    }

    private func begin(onDevice wantOnDevice: Bool) throws {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            log("recognizer unavailable for \(Locale.current.identifier)")
            failure = "Dictation isn't available. Check your internet connection, then try again."; return
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        onDevice = wantOnDevice && recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
        self.request = request
        current = request
        log("recognizer \(recognizer.locale.identifier) onDevice=\(onDevice)")

        if let file = Self.testAudio, testFeed == nil {
            Self.testAudio = nil
            // Test runs: the file stands in for the microphone, so a running engine (voice mode) steps aside.
            if engine.isRunning { engine.stop(); removeTap() }
            try startTestFeed(file)
        } else if testFeed == nil {
            // The engine runs once per listen — or, in voice mode, stays running from turn to turn (so Mavis's
            // voice through it isn't cut off, and nothing restarts between your sentences); the tap feeds whichever
            // request is current.
            let input = engine.inputNode
            if !engine.isRunning {
                cancelEcho()
                let format = input.outputFormat(forBus: 0)
                log("input format: \(format.sampleRate) Hz, \(format.channelCount) ch")
                input.removeTap(onBus: 0)
                mono = format.channelCount > 1 ? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false) : nil
                tapped = true
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    self?.feed(buffer)
                    let level = Self.level(buffer)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, self.active, self.listening else { return }
                            self.levels.removeFirst()
                            self.levels.append(level)
                            if level > 0.3 { self.lastVoice = Date() }
                            if level > 0.4 { if self.loudSince == nil { self.loudSince = Date() } } else { self.loudSince = nil }
                        }
                    }
                }
                engine.prepare()
                try engine.start()
            }
            listening = true
            started = Date()
            clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; self.elapsed = Date().timeIntervalSince(self.started) }
            }
        }
        let id = session
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let message = error.map { ($0 as NSError).domain + " " + String(($0 as NSError).code) + " " + $0.localizedDescription }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.session == id, self.active else { return }
                    if let result {
                        self.log("result\(final ? " final" : ""): \"\(text ?? "")\" segments=\(result.bestTranscription.segments.count)"
                                 + (result.speechRecognitionMetadata != nil ? " +end of utterance" : ""))
                    }
                    // The final result often restates the utterance that just ended (same words, end-of-utterance again)
                    // with nothing heard in between: that's not new speech.
                    let restated = result?.speechRecognitionMetadata != nil && self.utterance.isEmpty && text == self.ended
                    if let text, !text.isEmpty, !restated {
                        self.utterance = text
                        self.transcript = Self.join(self.kept, text)
                    }
                    // End of an utterance: keep its words, since the next result starts with only what follows.
                    if result?.speechRecognitionMetadata != nil, !self.utterance.isEmpty {
                        self.kept = Self.join(self.kept, self.utterance)
                        self.ended = self.utterance
                        self.utterance = ""
                        self.log("utterance ended; kept: \"\(self.kept)\"")
                    }
                    if let message {
                        self.log("recognition error: \(message)")
                        // macOS Dictation is switched off: nothing can be understood until it's on.
                        if message.contains(" 201 ") { self.dictationOff = true }
                        if self.dictationOff, message.contains(" 1110 ") {
                            self.failure = "Dictation is off on this Mac. Turn it on in System Settings › Keyboard › Dictation, then hold fn + control again."
                        }
                        // No on-device speech model: carry on with Apple's dictation service, like system dictation.
                        if self.onDevice, self.transcript.isEmpty, self.waiting == nil {
                            self.task?.cancel(); self.task = nil
                            try? self.begin(onDevice: false)
                            return
                        }
                    }
                    if final || message != nil, self.waiting != nil { self.deliver() }
                }
            }
        }
    }

    /// Test runs only: plays a sound file into the recognizer in 0.1 s steps, as a microphone would deliver it.
    private func startTestFeed(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        log("test audio (simulated): \(url.lastPathComponent), \(String(format: "%.1f", Double(file.length) / format.sampleRate)) s")
        listening = true
        started = Date()
        clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.elapsed = Date().timeIntervalSince(self.started) }
        }
        let id = session
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        testFeed = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.session == id, self.listening,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
                      (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0 else { break }
                self.feed(buffer)
                let level = Self.level(buffer)
                self.levels.removeFirst()
                self.levels.append(level)
                if level > 0.3 { self.lastVoice = Date() }
                            if level > 0.4 { if self.loudSince == nil { self.loudSince = Date() } } else { self.loudSince = nil }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            self?.log("test audio ended")
        }
    }

    /// Audio goes to whichever request is current (a fallback swaps it mid-way).
    /// The audio thread and the main thread share the request and the recording: with the microphone staying open
    /// across turns (voice mode), the main thread swaps them while audio keeps arriving, so every touch takes this.
    nonisolated private let feedLock = NSLock()

    nonisolated private func feed(_ buffer: AVAudioPCMBuffer) {
        let one = mono.flatMap { Self.firstChannel(of: buffer, as: $0) } ?? buffer
        feedLock.lock(); defer { feedLock.unlock() }
        _current?.append(one)
    }

    /// The first channel of a multi-channel buffer as a mono buffer of the same length.
    nonisolated private static func firstChannel(of buffer: AVAudioPCMBuffer, as format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let src = buffer.floatChannelData, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let dst = out.floatChannelData else { return nil }
        out.frameLength = buffer.frameLength
        dst[0].update(from: src[0], count: Int(buffer.frameLength))
        return out
    }

    /// Only touch the input node once it was set up: asking for it while macOS is still showing the microphone
    /// prompt blocks the main thread until the prompt is answered (the whole app froze on Stop).
    private var tapped = false
    private func removeTap() {
        guard tapped else { return }
        tapped = false
        engine.inputNode.removeTap(onBus: 0)
    }

    private func stopAudio() {
        testFeed?.cancel(); testFeed = nil
        clock?.invalidate(); clock = nil
        current = nil
        if !Self.continuous { if engine.isRunning { engine.stop() }; removeTap() }
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil; current = nil
        listening = false
    }


    private static func join(_ kept: String, _ next: String) -> String {
        kept.isEmpty ? next : next.isEmpty ? kept : kept + " " + next
    }

    /// The microphone's latest loudness in dBFS, unclamped (the dock's print sizes itself with it).
    nonisolated(unsafe) static var decibels: Float = -100

    nonisolated private static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0.05 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0.05 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        // Speech sits around −40…−10 dBFS; map that to 0.05…1.
        let db = 20 * log10(max(rms, 1e-6))
        decibels = db
        return min(1, max(0.05, (db + 50) / 40))
    }

    private static func authorize() async -> (Bool, Bool) {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return (speech, mic)
    }

    // MARK: log

    private static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Agent Lab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("talk.log")
    }()
    func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: Self.logURL)
        }
    }
}
