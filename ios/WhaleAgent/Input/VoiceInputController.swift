import AVFoundation
import Speech

/// Live dictation for the chat composer.
///
/// Uses the system Speech framework (`SFSpeechRecognizer`, zh-CN) with the
/// microphone stream from `AVAudioEngine`. Failures are reported honestly:
/// missing permission or an unavailable recognizer surfaces as an explicit
/// error instead of a fabricated transcript.
@MainActor
final class VoiceInputController: ObservableObject {
    enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorText: String?
    @Published private(set) var permission: PermissionState = .unknown
    struct FinalResult: Equatable { let sessionId: UUID; let text: String }
    @Published private(set) var finalResult: FinalResult?
    @Published private(set) var isFinalizing = false

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var xfyun: XfyunASRClient?
    let engineName: String = XfyunConfig.isConfigured ? "讯飞语音" : "系统听写"
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioLease: UUID?
    private var isStopping = false
    private var sessionId = UUID()
    private var finalTimeout: Task<Void, Never>?

    var isSupported: Bool { recognizer != nil }

    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard !isRecording, !isFinalizing else { return }
        cancel()
        let token = sessionId
        NotificationCenter.default.post(name: .whaleInterruptSpeech, object: nil)
        errorText = nil
        transcript = ""
        finalResult = nil

        if XfyunConfig.isConfigured {
            await startXfyun()
            return
        }

        guard await ensurePermissions() else {
            permission = .denied
            errorText = "语音输入需要麦克风与语音识别权限，请到 设置 → Whale Agent 中开启后再试。"
            return
        }
        guard sessionId == token else { return }
        permission = .granted

        guard let recognizer else {
            errorText = "这台设备没有可用的中文语音识别，请直接用键盘输入。"
            return
        }
        guard recognizer.isAvailable else {
            errorText = "系统语音识别暂时不可用，请稍后重试或直接用键盘输入。"
            return
        }

        do {
            audioLease = try AudioSessionCoordinator.shared.acquire(.recording) { [weak self] in
                self?.errorText = "语音被电话、音频路由或其他录音打断，已保留草稿。"
                self?.cancel()
            }
        } catch {
            errorText = "无法启用麦克风：\(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            errorText = "没有检测到可用的麦克风输入。"
            deactivateSession()
            self.request = nil
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.request = nil
            deactivateSession()
            errorText = "麦克风启动失败：\(error.localizedDescription)"
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard self?.sessionId == token else { return }
                self?.handle(result: result, error: error)
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isFinalizing = true
        isRecording = false
        let token = sessionId
        finalTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self, self.sessionId == token, self.isFinalizing else { return }
            self.errorText = "没有收到最终识别结果，已保留草稿；请检查后手动提交。"
            self.cancel()
        }
        if let xfyun {
            xfyun.stop()
            return
        }
        isStopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        deactivateSession()
    }

    func finishRecognition() async -> String? {
        let token = sessionId
        stop()
        while sessionId == token && isFinalizing {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { cancel(); return nil }
        }
        guard finalResult?.sessionId == token else { return nil }
        return finalResult?.text
    }

    func cancel() {
        sessionId = UUID() // invalidates every late callback, including permission requests
        finalTimeout?.cancel()
        finalTimeout = nil
        xfyun?.cancel()
        xfyun = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        isFinalizing = false
        isStopping = false
        deactivateSession()
    }

    func reset() {
        cancel()
        transcript = ""
        errorText = nil
        finalResult = nil
    }

    private func startXfyun() async {
        let token = sessionId
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard sessionId == token else { return }
        guard microphoneGranted else {
            permission = .denied
            errorText = "语音输入需要麦克风权限，请到 设置 → Whale Agent 中开启后再试。"
            return
        }
        permission = .granted

        guard let client = XfyunASRClient() else {
            errorText = "讯飞语音配置不完整，请检查 XFYUN_APP_ID / API_KEY / API_SECRET。"
            return
        }
        client.onPartial = { [weak self] text in
            guard self?.sessionId == token else { return }
            self?.transcript = text
        }
        client.onFinal = { [weak self] text in
            guard let self, self.sessionId == token else { return }
            self.complete(text)
        }
        client.onError = { [weak self] message in
            guard self?.sessionId == token else { return }
            self?.errorText = message
            self?.cancel()
        }
        do {
            try client.start()
            xfyun = client
            isRecording = true
        } catch {
            client.cancel()
            errorText = "讯飞语音启动失败：\(error.localizedDescription)"
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if !text.isEmpty { transcript = text }
            if result.isFinal { complete(text); return }
        }
        if let error {
            errorText = "语音识别中断：\(error.localizedDescription)"
            cancel()
        }
    }

    private func complete(_ text: String) {
        let token = sessionId
        transcript = text
        cancel()
        finalResult = FinalResult(sessionId: token, text: text)
    }

    private func ensurePermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }

        return await AVAudioApplication.requestRecordPermission()
    }

    private func deactivateSession() {
        AudioSessionCoordinator.shared.release(audioLease)
        audioLease = nil
    }
}
