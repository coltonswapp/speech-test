import Foundation

enum SecretsPlist {
    private static let cache: [String: String]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else { return nil }
        return dict
    }()

    static func value(for key: String) -> String? {
        guard let value = cache?[key], !value.isEmpty else { return nil }
        return value
    }
}
