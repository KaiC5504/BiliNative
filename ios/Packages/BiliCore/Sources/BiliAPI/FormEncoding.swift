import Foundation

/// application/x-www-form-urlencoded with percent-escapes for everything outside RFC 3986's unreserved set,
/// so a space is %20 (not +) and a literal + or & in a comment cannot be misread by the server.
enum FormEncoding {
    static func encode(_ fields: [String: String]) -> Data {
        Data(WBI.encodeQuery(fields).utf8)
    }
}
