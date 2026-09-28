import AppKit
import MatrixRustSDK

/// Content retained by a message row across NSTableView reuse.
protocol MessageContentRowView: NSView {
    var onSelectRequest: (() -> Void)? { get set }
    var onArrowKey: ((TimelineSelectionDirection) -> Void)? { get set }
    func configure(content: MatrixRustSDK.MsgLikeContent, matrixClient: MatrixClient?)
    func height(for content: MatrixRustSDK.MsgLikeContent, width: CGFloat) -> CGFloat
}

/// Determines the reusable row and its retained content view for a message.
@MainActor enum MessageContentKind: Hashable {
    case text
    case image
    case video
    case file

    init(content: MatrixRustSDK.MsgLikeContent) {
        if MessageImageContentView.supports(content: content) {
            self = .image
        } else if MessageVideoContentView.supports(content: content) {
            self = .video
        } else if MessageFileContentView.supports(content: content) {
            self = .file
        } else {
            self = .text
        }
    }

    var reuseIdentifier: NSUserInterfaceItemIdentifier {
        switch self {
        case .text: .init("message.text")
        case .image: .init("message.image")
        case .video: .init("message.video")
        case .file: .init("message.file")
        }
    }

    func makeRowView() -> MessageRowView {
        let contentView: any MessageContentRowView
        switch self {
        case .text: contentView = MessageTextContentView()
        case .image: contentView = MessageImageContentView()
        case .video: contentView = MessageVideoContentView()
        case .file: contentView = MessageFileContentView()
        }
        return MessageRowView(contentKind: self, contentView: contentView)
    }
}
