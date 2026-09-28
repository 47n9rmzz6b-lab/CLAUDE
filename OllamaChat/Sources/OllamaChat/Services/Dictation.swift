import AVFoundation
import Foundation
import Observation
import Speech

/// Dictée : le micro est transcrit en texte (sur le Mac quand la langue le permet)
/// et le texte arrive dans la zone de saisie au fur et à mesure.
@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var onText: ((String) -> Void)?

    var isActive: Bool { state == .recording || state == .starting }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Hors du bundle .app (« swift run »), macOS refuserait l’accès au micro sans description d’usage.
    static var isAvailableInThisBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
    }

    func toggle(onText: @escaping (String) -> Void) {
        if isActive {
            stop()
        } else {
            Task { await start(onText: onText) }
        }
    }

    func dismissError() {
        if case .failed = state { state = .idle }
    }

    func start(onText: @escaping (String) -> Void) async {
        guard Self.isAvailableInThisBuild else {
            state = .failed("La dictée n’est disponible que dans l’application compilée (Ollama Chat.app).")
            return
        }
        self.onText = onText
        state = .starting

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            state = .failed("Autorisez la reconnaissance vocale dans Réglages Système › Confidentialité et sécurité.")
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .failed("Autorisez l’accès au micro dans Réglages Système › Confidentialité et sécurité › Micro.")
            return
        }

        let localeIdentifier = UserDefaults.standard.string(forKey: SettingsKey.dictationLocale) ?? "fr-FR"
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            state = .failed("La reconnaissance vocale n’est pas disponible pour cette langue.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .failed("Aucun micro n’est disponible.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            state = .failed("Impossible de démarrer le micro : \(error.localizedDescription)")
            return
        }

        self.engine = engine
        self.request = request
        state = .recording
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil && result == nil
            guard let controller = self else { return }
            Task { @MainActor in
                controller.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        onText = nil
        if isActive { state = .idle }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty { onText?(text) }
        if isFinal || failed { stop() }
    }
}
