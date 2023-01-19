@preconcurrency import Dispatch
import Foundation

public struct FileRotationDailyLogger: FileLoggerable {
    private var uintPermission: UInt16 {
			return UInt16(filePermission, radix: 8)!
    }

    private var currentDate: Date? = nil
    public let label: String
    public let queue: DispatchQueue
    public let logLevel: LogLevel
    public let logFormat: LogFormattable?

    public let fileURL: URL
    public let filePermission: String

    let rotationConfig: RotationConfig
    private weak var delegate: FileRotationDailyLoggerDelegate?

    public init(_ label: String, logLevel: LogLevel = .trace, logFormat: LogFormattable? = nil, fileURL: URL, filePermission: String = "640", rotationConfig: RotationConfig, delegate: FileRotationDailyLoggerDelegate? = nil) throws {
        self.label = label
        self.queue = DispatchQueue(label: label)
        self.logLevel = logLevel
        self.logFormat = logFormat

        self.fileURL = fileURL
        puppyDebug("initialized, fileURL: \(fileURL)")
        self.filePermission = filePermission

        self.rotationConfig = rotationConfig
        self.delegate = delegate

        try validateFolderURL(fileURL)
        try validateFolderPermission(fileURL, folderPermission: filePermission)
        try self.openDailyFile(rotationConfig.rotationType == .dailyinsubfolder)
				self.currentDate = Calendar.current.startOfDay(for: Date())
    }

    public func log(_ level: LogLevel, string: String) {
        rotateFiles()
        append(level, string: string)
        rotateFiles()
    }

    private func rotateFiles() {
      if currentDate != nil && self.currentDate == Calendar.current.startOfDay(for: Date()) {
        return;
      }

			// Removes extra archives.
			removeArchives(fileURL, maxArchives: rotationConfig.maxArchives)

			// Opens a new target file.
			do {
				puppyDebug("will openFile in rotateFiles")
				try openDailyFile()
			} catch {
				print("error in openFile while rotating, error: \(error.localizedDescription)")
			}
    }
		mutating func openDailyFile() throws {
			try openDailyFile(self.rotationConfig.rotationType == .dailyinsubfolder)
			self.currentDate = Calendar.current.startOfDay(for: Date())
		}
    private func ascArchivesURLs(_ fileURL: URL) -> [URL] {
        var ascArchivesURLs: [URL] = []
        do {
            let archivesDirectoryURL: URL = fileURL
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
                    delegate?.fileRotationDailyLogger(self, didRemoveArchivesURL: archivesURLs[index])
                }
            }
        } catch {
            print("error in removing extra archives, error: \(error.localizedDescription)")
        }
    }
}

public protocol FileRotationDailyLoggerDelegate: AnyObject, Sendable {
    func fileRotationDailyLogger(_ fileRotationDailyLogger: FileRotationDailyLogger, didArchiveFileURL: URL, toFileURL: URL)
    func fileRotationDailyLogger(_ fileRotationDailyLogger: FileRotationDailyLogger, didRemoveArchivesURL: URL)
}
