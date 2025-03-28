#if canImport(Logging)
@_exported import Logging

public struct PuppyLogHandler: LogHandler, Sendable {
    public var logLevel: Logger.Level = .info
    public var metadata: Logger.Metadata

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { self.metadata[key] }
        set { self.metadata[key] = newValue }
    }

    private let label: String
    private let puppy: Puppy

    public init(label: String, puppy: Puppy, metadata: Logger.Metadata = [:]) {
        self.label = label
        self.puppy = puppy
        self.metadata = metadata
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let metadata = "[\(self.mergedMetadata(metadata).sortedDescriptionWithoutQuotes)]"
        let swiftLogInfo = ["label": label, "source": source, "metadata": metadata]

        self.puppy.logMessage(level.toPuppy(), message: "\(message)", tag: "swiftlog", function: function, file: file, line: line, swiftLogInfo: swiftLogInfo)
    }

    private func mergedMetadata(_ metadata: Logger.Metadata?) -> Logger.Metadata {
        metadata.map { self.metadata.merging($0, uniquingKeysWith: { $1 }) } ?? self.metadata
    }
}

extension Logger.Level {
    func toPuppy() -> LogLevel {
        switch self {
        case .trace:    .trace
        case .debug:    .debug
        case .info:     .info
        case .notice:   .notice
        case .warning:  .warning
        case .error:    .error
        case .critical: .critical
        }
    }
}

private extension Logger.MetadataValue {
    var descriptionWithoutExcessQuotes: String {
        switch self {
        case .array(let array): "[\(array.map(\.descriptionWithoutExcessQuotes).joined(separator: ", "))]"
        case .dictionary(let dict): "[\(dict.sortedDescriptionWithoutQuotes)]"
        case .string(let str): "\"\(str)\""
        case .stringConvertible(let conv): "\"\(conv)\""
        }
    }
}

private extension Logger.Metadata {
    var sortedDescriptionWithoutQuotes: String {
        self.sorted { $0.0 < $1.0 }
            .map { "\($0): \($1.descriptionWithoutExcessQuotes)" }
            .joined(separator: ", ")
    }
}

#endif // canImport(Logging)
