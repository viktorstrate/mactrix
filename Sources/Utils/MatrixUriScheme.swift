import Foundation

public enum MatrixUriError: LocalizedError {
    case parserError(reason: LocalizedStringResource)

    public var errorDescription: String? {
        switch self {
        case .parserError(let reason):
            return "failed to parse matrix uri: \(reason)"
        }
    }
}

public struct MatrixUriScheme: Hashable, Codable {
    public let kind: Kind
    public let routingVia: [String]
    public let action: Action?
    public let event: String?

    public enum Kind: Hashable, Codable {
        case roomId(String)
        case roomAlias(String)
        case user(String)
    }

    public enum Action: Hashable, Codable {
        case join, chat
    }

    public init(parseUrl url: String) throws(MatrixUriError) {
        let urlRegex = /matrix:(?:\/\/[^\/])?(roomid|u|r)\/([^\/\?]+)(\/e\/[^\/\?]+)?(?:\?(.*))?/

        guard let match = try? urlRegex.wholeMatch(in: url) else {
            throw .parserError(reason: "did not match url structure")
        }

        let (_, kind, id, _ /* event */, query) = match.output

        switch kind {
        case "roomid":
            self.kind = .roomId("!\(id)")
        case "r":
            self.kind = .roomAlias("#\(id)")
        case "u":
            self.kind = .user("@\(id)")
        default:
            throw .parserError(reason: "invalid type \(kind)")
        }

        let queryComponents = query?.split(separator: "&") ?? []

        var routingVia = [String]()
        var action: Action? = nil

        for queryComponent in queryComponents {
            let component = queryComponent.split(separator: "=")
            guard component.count == 2 else { continue }

            switch component[0] {
            case "via":
                routingVia.append(String(component[1]))
            case "action":
                switch component[1] {
                case "join":
                    action = .join
                case "chat":
                    action = .chat
                default:
                    continue
                }
            default:
                continue
            }
        }

        // todo
        self.routingVia = routingVia
        self.action = action
        self.event = nil
    }
}
