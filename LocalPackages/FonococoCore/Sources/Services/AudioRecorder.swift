import AVFoundation
import Combine
import Foundation

@MainActor public final class ReactionAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public private(set) var isRecording = false
    @Published public private(set) var lastError: String?
    private var recorder: AVAudioRecorder?
    private var interruptionObserver: NSObjectProtocol?
    public override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    public func start() async throws {
        guard !isRecording else { return }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { throw ServiceError.permissionDenied }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
            recorder.delegate = self
            guard recorder.record() else { throw ServiceError.recordingFailed }
            self.recorder = recorder; isRecording = true; lastError = nil
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            lastError = error.localizedDescription
            throw error
        }
    }
    public func stop() throws -> URL {
        guard let recorder else { throw ServiceError.recordingFailed }
        recorder.stop(); isRecording = false
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        self.recorder = nil
        return recorder.url
    }
    public func cancel() {
        recorder?.stop(); recorder?.deleteRecording(); recorder = nil; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isRecording = false
            if !flag { self?.lastError = ServiceError.recordingFailed.localizedDescription }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    deinit {
        recorder?.stop()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }
}
