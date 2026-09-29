import Testing

@testable import Utils

struct MatrixUriSchemeTests {
    @Test func parseSimpleRoomAlias() throws {
        let url = "matrix:r/somewhere:example.org"
        
        let parsed = try Utils.MatrixUriScheme(parseUrl: url)
        
        #expect(parsed.kind == .roomAlias("#somewhere:example.org"))
    }
    
    @Test func parseSimpleRoomId() throws {
        let url = "matrix:roomid/somewhere:example.org?via=elsewhere.ca"
        
        let parsed = try Utils.MatrixUriScheme(parseUrl: url)
        
        #expect(parsed.kind == .roomId("!somewhere:example.org"))
        #expect(parsed.routingVia == ["elsewhere.ca"])
    }
    
    @Test func parseUserChat() throws {
        let url = "matrix:u/alice:example.org?action=chat"
        
        let parsed = try Utils.MatrixUriScheme(parseUrl: url)
        
        #expect(parsed.kind == .user("@alice:example.org"))
        #expect(parsed.action == .chat)
    }
}
