import MatrixRustSDK

protocol MessageContent {
    var body: String { get }
    var formatted: FormattedBody? { get }
}

protocol MediaMessageContent {
    var filename: String { get }
    var caption: String? { get }
    var formattedCaption: FormattedBody? { get }
    var source: MediaSource { get }
}

extension FileMessageContent: MediaMessageContent {}
extension AudioMessageContent: MediaMessageContent {}
extension VideoMessageContent: MediaMessageContent {}
extension ImageMessageContent: MediaMessageContent {}

extension EmoteMessageContent: MessageContent {}
extension NoticeMessageContent: MessageContent {}
extension TextMessageContent: MessageContent {}
