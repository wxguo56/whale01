import AVFoundation
import CryptoKit
import Foundation

/// iFlytek real-time dictation (iat) over WebSocket.
/// The client is only usable when XFYUN_APP_ID / API_KEY / API_SECRET are
/// injected into Info.plist; otherwise the app falls back to system dictation.
@MainActor
final class XfyunASRClient {
    private struct XFResponse: Decodable {
        let code: Int
        let message: String?
        let data: XFData?
    }

    private struct XFData: Decodable {
        let status: Int?
        let result: XFResult?
    }

    private struct XFResult: Decodable {
        let sn: Int?
        let pgs: String?
        let ws: [XFWord]?
    }

    private struct XFWord: Decodable {
        let cw: [XFCandidate]?
    }

    private struct XFCandidate: Decodable {
        let w: String?
    }

    private let config: XfyunConfig
    private let host = "iat-api.xfyun.cn"
    private let audioEngine = AVAudioEngine()
    private var socket: URLSessionWebSocketTask?
    private var converter: AVAudioConverter?
    private var segments: [Int: String] = [:]
    private var audioLease: UUID?
    private var isRunning = false
    private var stopping = false
    private var stopTimeout: Task<Void, Never>?

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    init?(config: XfyunConfig? = XfyunConfig.current) {
        guard let config else { return nil }
        self.config = config
    }

    var currentText: String {
        segments.keys.sorted().compactMap { segments[$0] }.joined()
    }

    func start() throws {
        guard !isRunning else { return }
        segments = [:]
        stopping = false

        audioLease = try AudioSessionCoordinator.shared.acquire(.recording) { [weak self] in
            self?.fail("讯飞录音被打断，已保留草稿。")
        }
        defer {
            if !isRunning { AudioSessionCoordinator.shared.release(audioLease); audioLease = nil }
        }

        guard let url = authorizationURL() else {
            throw NSError(domain: "XfyunASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法生成讯飞鉴权地址"])
        }

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        isRunning = true
        receiveLoop()
        sendConfigFrame()

        let input = audioEngine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "XfyunASR", code: -2, userInfo: [NSLocalizedDescriptionKey: "没有检测到可用的麦克风输入"])
        }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            throw NSError(domain: "XfyunASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法创建 16k 音频格式"])
        }
        converter = AVAudioConverter(from: inputFormat, to: target)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { [weak self] buffer, _ in
            guard let copy = Self.copy(buffer) else { return }
            Task { @MainActor [weak self] in
                self?.convertAndSend(copy, target: target)
            }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        guard isRunning, !stopping else { return }
        stopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        sendDataFrame(status: 2, audio: "")
        stopTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.fail("讯飞没有返回最终识别结果，已保留草稿。")
        }
    }

    func cancel() {
        finish(final: false)
    }

    private func sendConfigFrame() {
        let payload: [String: Any] = [
            "common": ["app_id": config.appId],
            "business": [
                "language": "zh_cn",
                "domain": "iat",
                "accent": "mandarin",
                "vad_eos": 3000
            ],
            "data": [
                "status": 0,
                "format": "audio/L16;rate=16000",
                "encoding": "raw",
                "audio": ""
            ]
        ]
        send(payload)
    }

    private func sendDataFrame(status: Int, audio: String) {
        let payload: [String: Any] = [
            "data": [
                "status": status,
                "format": "audio/L16;rate=16000",
                "encoding": "raw",
                "audio": audio
            ]
        ]
        send(payload)
    }

    private func send(_ payload: [String: Any]) {
        guard
            let socket,
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else { return }
        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.fail("讯飞发送失败：\(error.localizedDescription)")
            }
        }
    }

    private func receiveLoop() {
        socket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                switch result {
                case .failure(let error):
                    if !self.stopping {
                        self.fail("讯飞连接中断：\(error.localizedDescription)")
                    }
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                    @unknown default:
                        break
                    }
                    if self.isRunning { self.receiveLoop() }
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let response = try? JSONDecoder().decode(XFResponse.self, from: data)
        else { return }

        if response.code != 0 {
            fail("讯飞识别失败（\(response.code)）：\(response.message ?? "未知错误")")
            return
        }

        if let result = response.data?.result {
            apply(result)
            onPartial?(currentText)
        }

        if response.data?.status == 2 {
            finish(final: true)
        }
    }

    private func apply(_ result: XFResult) {
        let sn = result.sn ?? ((segments.keys.max() ?? 0) + 1)
        let chunk = (result.ws ?? [])
            .compactMap { $0.cw?.compactMap { $0.w }.joined() }
            .joined()
        if result.pgs == "rpl" {
            for key in segments.keys where key >= sn {
                segments.removeValue(forKey: key)
            }
        }
        segments[sn] = chunk
    }

    private func finish(final: Bool) {
        guard isRunning else { return }
        isRunning = false
        stopping = false
        stopTimeout?.cancel()
        stopTimeout = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        AudioSessionCoordinator.shared.release(audioLease)
        audioLease = nil
        let text = currentText
        if final, !text.isEmpty {
            onFinal?(text)
        }
    }

    private func fail(_ message: String) {
        finish(final: false)
        onError?(message)
    }

    private func convertAndSend(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard isRunning, !stopping, let converter else { return }
        let ratio = 16000.0 / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let channel = output.int16ChannelData?[0] else { return }
        let byteCount = Int(output.frameLength) * 2
        let data = Data(bytes: channel, count: byteCount)
        sendDataFrame(status: 1, audio: data.base64EncodedString())
    }

    private func authorizationURL() -> URL? {
        let date = Self.rfc1123(Date())
        let origin = "host: \(host)\ndate: \(date)\nGET /v2/iat HTTP/1.1"
        let key = SymmetricKey(data: Data(config.apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(origin.utf8), using: key)
        let signatureBase64 = Data(signature).base64EncodedString()
        let authorization = "api_key=\"\(config.apiKey)\", algorithm=\"hmac-sha256\", headers=\"host date request-line\", signature=\"\(signatureBase64)\""
        let encodedAuth = Data(authorization.utf8).base64EncodedString()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = "/v2/iat"
        components.queryItems = [
            URLQueryItem(name: "authorization", value: encodedAuth),
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "host", value: host)
        ]
        return components.url
    }

    private static func rfc1123(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    nonisolated private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(source.count, destination.count) {
            guard let sourceData = source[index].mData, let destinationData = destination[index].mData else { continue }
            memcpy(destinationData, sourceData, Int(source[index].mDataByteSize))
            destination[index].mDataByteSize = source[index].mDataByteSize
        }
        return copy
    }
}
