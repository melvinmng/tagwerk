import Testing
@testable import Tagwerk

struct VoiceAudioSessionTests {
    @Test func conversation_keepsSessionForRecordingAndSpeaking() {
        #expect(!SystemVoiceAudioSession.reconfigures(requested: .recording, current: .conversation))
        #expect(!SystemVoiceAudioSession.reconfigures(requested: .speakingExplicit, current: .conversation))
        #expect(!SystemVoiceAudioSession.reconfigures(requested: .speakingAutomatic, current: .conversation))
    }

    @Test func otherwise_eachModeConfiguresTheSession() {
        #expect(SystemVoiceAudioSession.reconfigures(requested: .recording, current: nil))
        #expect(SystemVoiceAudioSession.reconfigures(requested: .speakingExplicit, current: .recording))
        #expect(SystemVoiceAudioSession.reconfigures(requested: .conversation, current: .speakingAutomatic))
        #expect(SystemVoiceAudioSession.reconfigures(requested: .conversation, current: nil))
    }
}
