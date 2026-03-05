import MatrixRustSDK

protocol MessageContent {
    var filename: String { get }
    var caption: String? { get }
    var formattedCaption: FormattedBody? { get }
    var source: MediaSource { get }
}

extension FileMessageContent: MessageContent {}
extension AudioMessageContent: MessageContent {}
extension VideoMessageContent: MessageContent {}
extension ImageMessageContent: MessageContent {}
