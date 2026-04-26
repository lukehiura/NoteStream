import Foundation

public struct LocalLLMModel: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }

    public var name: String
    public var displayName: String
    public var sizeBytes: Int64?

    public init(
        name: String,
        displayName: String? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.sizeBytes = sizeBytes
    }
}
