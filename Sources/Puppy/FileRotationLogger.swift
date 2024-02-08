@preconcurrency import Dispatch
import Foundation

public struct FileRotationLogger: FileLoggerable {
    public let label: String
    public let queue: DispatchQueue
    public let logLevel: LogLevel
    public let logFormat: LogFormattable?

    public let fileURL: URL
    public let filePermission: String

    let rotationConfig: RotationConfig
    private weak var delegate: FileRotationLoggerDelegate?

    private var dateFormat: DateFormatter

    public init(_ label: String, logLevel: LogLevel = .trace, logFormat: LogFormattable? = nil, fileURL: URL, filePermission: String = "640", rotationConfig: RotationConfig, delegate: FileRotationLoggerDelegate? = nil) throws {
        self.label = label
        self.queue = DispatchQueue(label: label)
        self.logLevel = logLevel
        self.logFormat = logFormat

        self.dateFormat = DateFormatter()
        self.dateFormat.dateFormat = "yyyyMMdd'T'HHmmssZZZZZ"
        self.dateFormat.timeZone = TimeZone(identifier: "UTC")
        self.dateFormat.locale = Locale(identifier: "en_US_POSIX")

        self.fileURL = fileURL
        puppyDebug("initialized, fileURL: \(fileURL)")
        self.filePermission = filePermission

        self.rotationConfig = rotationConfig
        self.delegate = delegate

        try validateFileURL(fileURL)
        try validateFilePermission(fileURL, filePermission: filePermission)
        try openFile()
    }

    public func log(_ level: LogLevel, string: String) {
        rotateFiles()
        append(level, string: string)
        rotateFiles()
    }

    private func fileSize(_ fileURL: URL) throws -> UInt64 {
        #if os(Windows)
        return try FileManager.default.windowsFileSize(atPath: fileURL.path)
        #else
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        // swiftlint:disable force_cast
        return attributes[.size] as! UInt64
        // swiftlint:enable force_cast
        #endif
    }

    private func rotateFiles() {
        guard let size = try? fileSize(fileURL), size > rotationConfig.maxFileSize else { return }

        // Rotates old archives.
        rotateOldArchives()

        // Archives the target file.
        archiveTargetFiles()

        // Removes extra archives.
        removeArchives(fileURL, maxArchives: rotationConfig.maxArchives)

        // Opens a new target file.
        do {
            puppyDebug("will openFile in rotateFiles")
            try openFile()
        } catch {
            print("error in openFile while rotating, error: \(error.localizedDescription)")
        }
    }

    private func archiveTargetFiles() {
        do {
            var archivesURL: URL
            switch rotationConfig.suffixExtension {
            case .numbering:
                archivesURL = fileURL.appendingPathExtension("1")
            case .date_uuid:
                // archivesURL = fileURL.appendingPathExtension(dateFormatter(Date(), dateFormat: "yyyyMMdd'T'HHmmssZZZZZ", timeZone: "UTC") + "_" + UUID().uuidString.lowercased())
                archivesURL = fileURL.appendingPathExtension(dateFormatter(Date(), withFormatter: self.dateFormat) + "_" + UUID().uuidString.lowercased())
            }
            try FileManager.default.moveItem(at: fileURL, to: archivesURL)
            delegate?.fileRotationLogger(self, didArchiveFileURL: fileURL, toFileURL: archivesURL)
        } catch {
            print("error in archiving the target file, error: \(error.localizedDescription)")
        }
    }

    private func rotateOldArchives() {
        switch rotationConfig.suffixExtension {
        case .numbering:
            do {
                let oldArchivesURLs = ascArchivesURLs(fileURL)
                for (index, oldArchivesURL) in oldArchivesURLs.enumerated() {
                    let generationNumber = oldArchivesURLs.count + 1 - index
                    let rotatedFileURL = oldArchivesURL.deletingPathExtension().appendingPathExtension("\(generationNumber)")
                    puppyDebug("generationNumber: \(generationNumber), rotatedFileURL: \(rotatedFileURL)")
                    if !FileManager.default.fileExists(atPath: rotatedFileURL.path) {
                        try FileManager.default.moveItem(at: oldArchivesURL, to: rotatedFileURL)
                    }
                }
            } catch {
                print("error in rotating old archive files, error: \(error.localizedDescription)")
            }
        case .date_uuid:
            break
        }
    }

    private func ascArchivesURLs(_ fileURL: URL) -> [URL] {
        var ascArchivesURLs: [URL] = []
        do {
            let archivesDirectoryURL: URL = fileURL.deletingLastPathComponent()
            let archivesURLs = try FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path)
                .map { archivesDirectoryURL.appendingPathComponent($0) }
                .filter { $0 != fileURL && $0.deletingPathExtension() == fileURL }

            ascArchivesURLs = try archivesURLs.sorted {
                #if os(Windows)
                let modificationTime0 = try FileManager.default.windowsModificationTime(atPath: $0.path)
                let modificationTime1 = try FileManager.default.windowsModificationTime(atPath: $1.path)
                return modificationTime0 < modificationTime1
                #else
                // swiftlint:disable force_cast
                let modificationDate0 = try FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as! Date
                let modificationDate1 = try FileManager.default.attributesOfItem(atPath: $1.path)[.modificationDate] as! Date
                // swiftlint:enable force_cast
                return modificationDate0.timeIntervalSince1970 < modificationDate1.timeIntervalSince1970
                #endif
            }
        } catch {
            print("error in ascArchivesURLs, error: \(error.localizedDescription)")
        }
        puppyDebug("ascArchivesURLs: \(ascArchivesURLs)")
        return ascArchivesURLs
    }

    private func removeArchives(_ fileURL: URL, maxArchives: UInt8) {
        do {
            let archivesURLs = ascArchivesURLs(fileURL)
            if archivesURLs.count > maxArchives {
                for index in 0 ..< archivesURLs.count - Int(maxArchives) {
                    puppyDebug("\(archivesURLs[index]) will be removed...")
                    try FileManager.default.removeItem(at: archivesURLs[index])
                    puppyDebug("\(archivesURLs[index]) has been removed")
                    delegate?.fileRotationLogger(self, didRemoveArchivesURL: archivesURLs[index])
                }
            }
        } catch {
            print("error in removing extra archives, error: \(error.localizedDescription)")
        }
    }
}

public protocol FileRotationLoggerDelegate: AnyObject, Sendable {
    func fileRotationLogger(_ fileRotationLogger: FileRotationLogger, didArchiveFileURL: URL, toFileURL: URL)
    func fileRotationLogger(_ fileRotationLogger: FileRotationLogger, didRemoveArchivesURL: URL)
}
