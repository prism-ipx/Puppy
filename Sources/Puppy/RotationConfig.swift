public struct RotationConfig: Sendable {
    public enum RotationType: Sendable {
        case filesize
        case daily
        case dailyinsubfolder
    }

    public enum SuffixExtension: Sendable {
        case numbering
        case date_uuid
    }
    public var suffixExtension: SuffixExtension
    public var rotationType: RotationType

    public typealias ByteCount = UInt64
    public var maxFileSize: ByteCount
    public var maxArchives: UInt8

    public init(rotationType: RotationType = .filesize, suffixExtension: SuffixExtension = .numbering, maxFileSize: ByteCount = 10 * 1024 * 1024, maxArchives: UInt8 = 5) {
        self.suffixExtension = suffixExtension
        self.maxFileSize = maxFileSize
        self.maxArchives = maxArchives
        self.rotationType = .filesize
    }
}