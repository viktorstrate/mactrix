import Foundation
import MatrixRustSDK
import Models

extension Models.CreateRoomParams {
    var asMatrixRequest: MatrixRustSDK.CreateRoomParameters {
        let preset: RoomPreset = switch access {
        case .privateRoom:
            .privateChat
        case .publicRoom:
            .publicChat
        }

        let visibility: MatrixRustSDK.RoomVisibility = switch self.visibility {
        case .published:
            .public
        case .unpublished:
            .private
        }

        var topicValue: String? = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        topicValue = topicValue?.isEmpty == false ? topicValue : nil

        return CreateRoomParameters(
            name: name,
            topic: topicValue,
            isEncrypted: enableEncryption,
            visibility: visibility,
            preset: preset
        )
    }
}
