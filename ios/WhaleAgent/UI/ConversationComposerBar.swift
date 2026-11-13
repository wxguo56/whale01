import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Bottom composer. It deliberately lives outside the horizontal pager: a
/// focused text field inside a paging `ScrollView` can make UIKit scroll the
/// whole pager to keep the field visible, which shows up as the chat jumping.
struct ConversationComposerBar: View {
    static let reservedHeight: CGFloat = 66

    @ObservedObject var model: AppModel
    @StateObject private var voice = VoiceInputController()
    @FocusState private var focused: Bool

    @State private var draft = ""
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var finishingVoice = false

    var body: some View {
        VStack(spacing: 7) {
            if let voiceError = voice.errorText {
                notice(voiceError)
            }
            if let importError {
                notice(importError)
            }
            if voice.isRecording {
                voiceStrip
            }
            composer
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoItem) { _, _ in
            Task { await ingestPhoto() }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
        .onChange(of: voice.transcript) { _, text in
            guard !text.isEmpty else { return }
            draft = text
        }
        .onChange(of: voice.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard voice.errorText == nil else { return }
            if !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focused = true
            }
        }
        .onChange(of: model.messages.isEmpty) { _, empty in
            if empty { draft = "" }
        }
        .onDisappear { voice.cancel() }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 2) {
            Menu {
                Button { showPhotoPicker = true } label: {
                    Label("从照片识别", systemImage: "photo")
                }
                Button { showFileImporter = true } label: {
                    Label("从文件识别 PDF/图片", systemImage: "doc")
                }
            } label: {
                Group {
                    if model.isExtractingDocument {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(WhaleTheme.ink)
                    }
                }
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy || model.isExtractingDocument)
            .opacity(model.isBusy || model.isExtractingDocument ? 0.4 : 1)
            .accessibilityLabel("导入照片或文件识别文字")

            TextField(model.messages.isEmpty ? "发消息，或按住说话" : "继续上次对话", text: $draft)
                .font(.system(size: 15))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(1)
                .frame(height: 24)
                .padding(.horizontal, 4)
                .focused($focused)
                .disabled(model.isBusy || voice.isFinalizing || finishingVoice)
                .submitLabel(.send)
                .onSubmit { submit() }

            if focused {
                Button {
                    focused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起键盘")
            } else {
                Button {
                    focused = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "waveform" : "mic")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(voice.isRecording ? WhaleTheme.danger : WhaleTheme.ink)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.4 : 1)
                .accessibilityLabel(voice.isRecording ? "停止语音输入" : "语音输入")
            }

            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        WhaleTheme.composerSendGradient,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .shadow(color: WhaleTheme.accent.opacity(0.24), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy || isDraftEmpty || finishingVoice)
            .opacity(model.isBusy || isDraftEmpty ? 0.5 : 1)
            .accessibilityLabel("发送")
        }
        .padding(.leading, 5)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(WhaleTheme.card.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .strokeBorder(WhaleTheme.line.opacity(0.9), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.13), radius: 18, y: 8)
        }
        .animation(.easeInOut(duration: 0.16), value: focused)
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(WhaleTheme.warm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var voiceStrip: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(WhaleTheme.danger)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(voice.transcript.isEmpty ? "正在听你说…" : voice.transcript)
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("停止") { voice.stop() }
                .font(.system(size: 13, weight: .semibold))
                .tint(WhaleTheme.danger)
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhaleTheme.danger.opacity(0.24), lineWidth: 0.8)
        }
    }

    private func submit() {
        guard !finishingVoice else { return }
        if voice.isRecording || voice.isFinalizing {
            finishingVoice = true
            Task {
                defer { finishingVoice = false }
                guard let final = await voice.finishRecognition(), !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    draft = voice.transcript
                    focused = true
                    return
                }
                focused = false
                draft = ""
                await model.send(text: final)
            }
        } else {
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            focused = false
            draft = ""
            Task { await model.send(text: text) }
        }
    }

    private func ingestPhoto() async {
        guard let item = photoItem else { return }
        photoItem = nil
        importError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importError = "没有读到照片数据，请换一张图片。"
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("whale-ocr-\(UUID().uuidString).jpg")
            try data.write(to: url, options: .atomic)
            await model.ingestDocument(url: url, label: "照片")
            try? FileManager.default.removeItem(at: url)
        } catch {
            importError = photoImportMessage(error)
        }
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            Task {
                defer {
                    if access { url.stopAccessingSecurityScopedResource() }
                }
                let label = url.pathExtension.lowercased() == "pdf" ? "PDF" : "图片"
                await model.ingestDocument(url: url, label: label)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func photoImportMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "照片读取失败：当前网络不可用。若这张照片只存在 iCloud，请先联网下载原图，或改用“从文件识别”选择本机图片。"
        }
        if ns.domain.contains("Photo") || ns.domain.contains("Cloud") {
            return "照片读取失败：\(error.localizedDescription)。请在相册中先下载到本机后重试。"
        }
        return "照片读取失败：\(error.localizedDescription)"
    }
}
