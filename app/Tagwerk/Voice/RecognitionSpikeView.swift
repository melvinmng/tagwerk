import AVFoundation
import Speech
import SwiftUI

/// Device check for on-device recognition: availability, language packs, permissions and a test
/// recording with both transcribers. Nothing leaves the device.
@MainActor @Observable
final class RecognitionSpikeModel {
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let value: String
    }

    private(set) var rows: [Row] = []
    private(set) var isRecording = false
    private(set) var finalText = ""
    private(set) var volatileText = ""
    private(set) var level: Float = 0
    private(set) var outcome: String?
    private(set) var elapsed: TimeInterval?
    var language: VoiceLanguage = .german
    var kind: TranscriberKind = .dictation
    private var recognizer: AppleSpeechRecognizer?
    private var startedAt: Date?
    private var firstTextAt: Date?

    func refresh() async {
        var rows: [Row] = []
        rows.append(Row(id: "speechAvailable", title: "SpeechTranscriber verfügbar", value: SpeechTranscriber.isAvailable ? "ja" : "nein"))
        for kind in TranscriberKind.allCases {
            for language in VoiceLanguage.allCases {
                let title = "\(kind == .speech ? "Speech" : "Dictation") \(language.shortName)"
                guard let module = await AppleSpeechRecognizer.module(kind, language: language) else {
                    rows.append(Row(id: title, title: title, value: "nicht unterstützt"))
                    continue
                }
                rows.append(Row(id: title, title: title, value: Self.describe(await AssetInventory.status(forModules: [module]))))
            }
        }
        rows.append(Row(id: "reserved", title: "Reservierte Sprachen",
                        value: "\(await AssetInventory.reservedLocales.map(\.identifier).joined(separator: ", ")) (max. \(AssetInventory.maximumReservedLocales))"))
        rows.append(Row(id: "mic", title: "Mikrofon", value: Self.describe(AVAudioApplication.shared.recordPermission)))
        rows.append(Row(id: "speechAuth", title: "Spracherkennung (Abfrage)", value: Self.describe(SFSpeechRecognizer.authorizationStatus())))
        self.rows = rows
    }

    func toggle() async {
        if isRecording {
            await recognizer?.stop()
            return
        }
        finalText = ""; volatileText = ""; outcome = nil; elapsed = nil; firstTextAt = nil
        let recognizer = AppleSpeechRecognizer(kind: kind)
        self.recognizer = recognizer
        isRecording = true
        startedAt = Date()
        let events = await recognizer.start(language: language)
        for await event in events {
            switch event {
            case .text(let final, let volatile):
                if firstTextAt == nil { firstTextAt = Date() }
                finalText = final; volatileText = volatile
            case .level(let value): level = value
            case .finished: outcome = "fertig"
            case .failed(let failure): outcome = "Fehler: \(failure)"
            }
        }
        if let startedAt, let firstTextAt { elapsed = firstTextAt.timeIntervalSince(startedAt) }
        isRecording = false
        level = 0
        await refresh()
    }

    private static func describe(_ status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: "nicht unterstützt"
        case .supported: "unterstützt, nicht geladen"
        case .downloading: "wird geladen"
        case .installed: "geladen"
        @unknown default: "unbekannt"
        }
    }

    private static func describe(_ permission: AVAudioApplication.recordPermission) -> String {
        switch permission {
        case .granted: "erlaubt"
        case .denied: "abgelehnt"
        case .undetermined: "noch nicht gefragt"
        @unknown default: "unbekannt"
        }
    }

    private static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: "erlaubt"
        case .denied: "abgelehnt"
        case .restricted: "eingeschränkt"
        case .notDetermined: "noch nicht gefragt"
        @unknown default: "unbekannt"
        }
    }
}

struct RecognitionSpikeSection: View {
    @State private var model = RecognitionSpikeModel()

    var body: some View {
        Section {
            Picker("Sprache", selection: $model.language) {
                ForEach(VoiceLanguage.allCases, id: \.self) { Text($0 == .german ? "Deutsch" : "English").tag($0) }
            }
            .disabled(model.isRecording)
            Picker("Erkenner", selection: $model.kind) {
                Text("Diktat").tag(TranscriberKind.dictation)
                Text("Sprache").tag(TranscriberKind.speech)
            }
            .disabled(model.isRecording)
            Button {
                Task { await model.toggle() }
            } label: {
                Label(model.isRecording ? "Aufnahme beenden" : "Probeaufnahme starten",
                      systemImage: model.isRecording ? "stop.circle.fill" : "mic.circle.fill")
            }
            if model.isRecording {
                ProgressView(value: Double(model.level)).tint(.red)
            }
            if !model.finalText.isEmpty || !model.volatileText.isEmpty {
                (Text(model.finalText) + Text(model.volatileText.isEmpty ? "" : " " + model.volatileText).foregroundStyle(.secondary))
                    .textSelection(.enabled)
            }
            if let outcome = model.outcome {
                Text(outcome + (model.elapsed.map { String(format: " · erster Text nach %.1f s", $0) } ?? ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in
                LabeledContent(row.title, value: row.value).font(.footnote)
            }
        } header: {
            Text("Erkennung auf dem iPhone")
        } footer: {
            Text("Erkennt Sprache auf dem iPhone, ohne Ton zu senden. Lädt beim ersten Mal das Sprachpaket.")
        }
        .task { await model.refresh() }
    }
}
