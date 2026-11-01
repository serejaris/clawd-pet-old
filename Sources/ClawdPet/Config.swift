import Foundation

public struct PetFeatures: Codable {
    public var eyeTracking: Bool?
    public var claudeWatch: Bool?
    public var codexWatch: Bool?

    public init(eyeTracking: Bool? = true, claudeWatch: Bool? = true, codexWatch: Bool? = true) {
        self.eyeTracking = eyeTracking
        self.claudeWatch = claudeWatch
        self.codexWatch = codexWatch
    }

    enum CodingKeys: String, CodingKey {
        case eyeTracking
        case claudeWatch
        case codexWatch
    }
}

public struct PetConfig: Codable {
    public var size: Double?
    public var walkSpeed: Double?
    public var gravity: Double?
    public var idleSecondsMin: Double?
    public var idleSecondsMax: Double?
    public var blinkSecondsMin: Double?
    public var blinkSecondsMax: Double?
    public var features: PetFeatures?

    public init(
        size: Double? = 80.0,
        walkSpeed: Double? = 1.2,
        gravity: Double? = 1.0,
        idleSecondsMin: Double? = 5.0,
        idleSecondsMax: Double? = 10.0,
        blinkSecondsMin: Double? = 2.5,
        blinkSecondsMax: Double? = 5.5,
        features: PetFeatures? = PetFeatures()
    ) {
        self.size = size
        self.walkSpeed = walkSpeed
        self.gravity = gravity
        self.idleSecondsMin = idleSecondsMin
        self.idleSecondsMax = idleSecondsMax
        self.blinkSecondsMin = blinkSecondsMin
        self.blinkSecondsMax = blinkSecondsMax
        self.features = features
    }

    public static let `default` = PetConfig()

    public static func load() -> PetConfig {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("clawd.json"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("clawd.json"),
            Bundle.main.url(forResource: "clawd", withExtension: "json"),
            URL(fileURLWithPath: NSString(string: "~/Documents/GitHub/clawd-pet/clawd.json").expandingTildeInPath)
        ]

        for url in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let config = try? JSONDecoder().decode(PetConfig.self, from: data) {
                return config
            }
        }

        return .default
    }
}
