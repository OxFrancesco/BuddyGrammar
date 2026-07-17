import Foundation

/// The URL contract shared by the keyboard extension and the containing app.
/// The main app owns microphone capture; the keyboard only initiates the
/// handoff and later inserts the completed transcript.
public enum KeyboardDictationHandoff {
    public static let scheme = "buddygrammar"
    public static let host = "dictation"

    public static func url(for sessionID: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "source", value: "keyboard"),
            URLQueryItem(name: "session", value: sessionID.uuidString),
        ]
        return components.url
    }

    public static func sessionID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ),
              components.queryItems?.first(where: { $0.name == "source" })?.value
                  == "keyboard",
              let rawSessionID = components.queryItems?
                  .first(where: { $0.name == "session" })?
                  .value else {
            return nil
        }
        return UUID(uuidString: rawSessionID)
    }
}
