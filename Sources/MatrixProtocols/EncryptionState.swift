
@MainActor
public enum EncryptionState {
    /**
     * The room is encrypted.
     */
    case encrypted
    /**
     * The room is not encrypted.
     */
    case notEncrypted
    /**
     * The state of the room encryption is unknown, probably because the
     * `/sync` did not provide all data needed to decide.
     */
    case unknown
}
