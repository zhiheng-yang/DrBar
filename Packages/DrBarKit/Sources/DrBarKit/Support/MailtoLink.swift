import Foundation

/// A `mailto:` link that opens a new email in whatever mail app the user has chosen (RFC 6068).
public enum MailtoLink {
    public static func url(to addresses: [String], subject: String, body: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = addresses.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
        parts.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            // Line breaks in a mailto body are CRLF.
            URLQueryItem(
                name: "body",
                value: body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")),
        ]
        // URLComponents leaves "+" alone, which some mail apps would read as a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}
