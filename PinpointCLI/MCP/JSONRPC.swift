import Foundation

/// The wire format under MCP: JSON-RPC 2.0, one message per line (#57).
///
/// Hand-rolled on `JSONSerialization` rather than `Codable`, for the same
/// reason `Arguments` is hand-rolled rather than pulled from
/// swift-argument-parser: this code is compiled into the `pinpoint` tool, which
/// ships inside the app bundle and is signed and notarized with it. Every
/// dependency added here is one more thing to sign and one more reason the app
/// itself fails to build — and the protocol surface we answer is eight methods
/// wide.
///
/// `Codable` would also fight the shape of the data. A JSON-RPC `id` is "string
/// or number", a tool's arguments are an arbitrary object, and `capture.json`
/// travels through here verbatim as the untyped dictionary `Handoff.raw`
/// already holds. Dictionaries all the way down is what those three want.
enum JSONRPC {
    static let version = "2.0"

    // MARK: - Errors

    /// The subset of JSON-RPC error codes this server can produce.
    ///
    /// Deliberately small, and deliberately *not* where tool failures go: a
    /// capture that timed out is a result the model has to see and can act on,
    /// so it comes back as a normal tool result carrying `isError`. These codes
    /// are for the protocol itself — a message that didn't parse, a method that
    /// doesn't exist. See `MCPTools.result(for:)`.
    enum ErrorCode: Int {
        case parseError = -32700
        case invalidRequest = -32600
        case methodNotFound = -32601
        case invalidParams = -32602
        case internalError = -32603
    }

    // MARK: - Identity

    /// A request id, carried back out exactly as it came in.
    ///
    /// JSON-RPC lets a client number its requests or name them, and a response
    /// has to echo the id it answers *in the same type* — a client that sent
    /// `"id": 7` and reads back `"id": "7"` has an unanswered request and a
    /// reply it can't place. So the original value is kept as-is rather than
    /// parsed into a Swift type and re-encoded from it.
    struct RequestID: Hashable {
        /// The value to write back into the response, untouched.
        let json: Any
        /// A typed spelling of that value, so two ids compare (and hash) the way
        /// JSON-RPC says they do: `1` and `"1"` are different requests.
        private let key: String

        init?(_ value: Any?) {
            switch value {
            case let string as String:
                json = string
                key = "s:\(string)"
            case let number as NSNumber:
                // `NSNumber` is what JSONSerialization hands back for every
                // numeric id. Kept as the same object so an integer stays an
                // integer and a float — legal, if odd — stays a float.
                json = number
                key = "n:\(number.stringValue)"
            default:
                // Includes `nil` and `NSNull`: a request without an id is a
                // notification, which is answered with silence, not with an
                // error addressed to nobody.
                return nil
            }
        }

        static func == (lhs: RequestID, rhs: RequestID) -> Bool { lhs.key == rhs.key }
        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    // MARK: - Messages

    /// One inbound message, already sorted into "expects an answer" or not.
    struct Message {
        let id: RequestID?
        let method: String
        let params: [String: Any]

        /// A message with no id. Notifications are never answered — not even to
        /// say the method is unknown.
        var isNotification: Bool { id == nil }

        /// Parses one line of stdin.
        ///
        /// Returns nil for anything that isn't a request or a notification we
        /// could act on. The caller turns that into a parse error only when it
        /// can address one, which is the honest reading of a line that may have
        /// had no id to begin with.
        static func parse(_ line: String) -> Message? {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  let method = dictionary["method"] as? String else { return nil }
            return Message(
                id: RequestID(dictionary["id"]),
                method: method,
                params: dictionary["params"] as? [String: Any] ?? [:]
            )
        }
    }

    // MARK: - Responses

    static func response(id: RequestID, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": version, "id": id.json, "result": result]
    }

    static func response(id: RequestID, error code: ErrorCode, message: String) -> [String: Any] {
        ["jsonrpc": version, "id": id.json,
         "error": ["code": code.rawValue, "message": message]]
    }
}
