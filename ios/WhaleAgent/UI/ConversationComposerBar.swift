import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Bottom composer. It deliberately lives outside the horizontal pager: a
/// focused text field inside a paging `ScrollView` can make UIKit scroll the
/// whole pager to keep the field visible, which shows up as the chat jumping.
struct ConversationComposerBar: View {
    static let reservedHeight: CGFloat = 76

    @ObservedObject var model: AppModel
    @StateObject private var voice = VoiceInputController()
    @FocusState private var focused: Bool

    @State private var draft = ""
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            if voice.isRecording {
                voiceStrip
            }

            HStack(alignment: .bottom, spacing: 9) {
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
                            Image(systemName: "paperclip")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(WhaleTheme.ink)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || model.isExtractingDocument)
                .opacity(model.isBusy || model.isExtractingDocument ? 0.45 : 1)
                .accessibilityLabel("导入照片或文件识别文字")

                Button {
                    focused = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "waveform" : "mic")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(voice.isRecording ? WhaleTheme.danger : WhaleTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.45 : 1)
                .accessibilityLabel(voice.isRecording ? "停止语音输入" : "语音输入")

                TextField("告诉鲸鱼你想做什么", text: $draft)
                    .lineLimit(1)
                    .frame(height: 22)
                    .focused($focused)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(WhaleTheme.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(WhaleTheme.line, lineWidth: 0.8)
                    }
                    .disabled(model.isBusy)
                    .submitLabel(.send)
                    .onSubmit { submit() }

                Button {
                    focused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(focused)
                .accessibilityHidden(!focused)
                .accessibilityLabel("收起键盘")

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WhaleTheme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(WhaleTheme.auroraGradient, in: Circle())
                        .shadow(color: WhaleTheme.accent.opacity(0.22), radius: 8, y: 3)
                }
                .disabled(model.isBusy || isDraftEmpty)
                .opacity(model.isBusy || isDraftEmpty ? 0.45 : 1)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 10)

            if let voiceError = voice.errorText {
                Text(voiceError)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.warm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if let importError {
                Text(importError)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.warm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background {
            WhaleChromeBackground()
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WhaleTheme.line.opacity(0.7))
                .frame(height: 0.5)
        }
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
                .foregroundStyle(WhaleTheme.muted)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("停止") { voice.stop() }
                .font(.system(size: 13, weight: .semibold))
                .tint(WhaleTheme.danger)
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WhaleTheme.danger.opacity(0.07))
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if voice.isRecording {
            voice.stop()
        }
        focused = false
        draft = ""
        Task { await model.send(text: text) }
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
