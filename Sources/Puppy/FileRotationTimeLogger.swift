@preconcurrency import Dispatch
import Foundation

@unchecked public class FileRotationTimeLogger: FileLoggerable  {
  private var uintPermission: UInt16 {
  	return UInt16(filePermission, radix: 8)!
  }

  public let label: String
  public let queue: DispatchQueue
  public let logLevel: LogLevel
  public let logFormat: LogFormattable?
  public let folderURL: URL
  public let folderDateFormat: String
  public let filePermission: String
  public let rotationTime: Double

  private var currentDate: Date? = nil
  public var fileURL: URL

  let rotationConfig: RotationConfig
  private weak var delegate: FileRotationTimeLoggerDelegate?

  public init(_ label: String, logLevel: LogLevel = .trace, logFormat: LogFormattable? = nil, folderURL: URL, filePermission: String = "640", rotationConfig: RotationConfig, delegate: FileRotationTimeLoggerDelegate? = nil, folderDateFormat: String = "yyyy-MM-dd", RotationTime: Double = 60 * 24 * 24) throws {
    self.label = label
    self.queue = DispatchQueue(label: label)
    self.logLevel = logLevel
    self.logFormat = logFormat
	  self.folderURL = folderURL
    self.fileURL = folderURL
    self.filePermission = filePermission

    self.rotationConfig = rotationConfig
    self.delegate = delegate
    self.folderDateFormat = folderDateFormat
    self.rotationTime = RotationTime
    puppyDebug("Initialized, base logging folder: \(folderURL)")

    try validateFolderURL(folderURL)
    try validateFolderPermission(folderURL, folderPermission: filePermission)
    try self.openDailyFile()
  }

  public func log(_ level: LogLevel, string: String) {
    rotateFiles()
    append(level, string: string)
    rotateFiles()
  }

  private func rotateFiles() {
    if currentDate != nil && Date().timeIntervalSince(self.currentDate!) > self.rotationTime {
	    return;
    }
    puppyDebug("Checking rotation...")

  	// Removes extra archives.
  	removeArchives(folderURL, maxArchives: rotationConfig.maxArchives)

  	// Opens a new target file.
  	do {
    	puppyDebug("will openFile in rotateFiles")
    	try self.openDailyFile()
  	} catch {
    	print("error in openFile while rotating, error: \(error.localizedDescription)")
  	}
  }

  private func openDailyFile() throws {
		self.currentDate = Date()
  	var directoryURL = folderURL

    let folderFormatter = DateFormatter()
    folderFormatter.dateFormat = self.folderDateFormat
    directoryURL.appendPathComponent(folderFormatter.string(from: self.currentDate!), isDirectory: true)
  	do {
			try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
			puppyDebug("created directoryURL, directoryURL: \(directoryURL)")
  	} catch {
	    throw FileError.creatingDirectoryFailed(at: directoryURL)
  	}

  	let fileFormatter = DateFormatter()
  	fileFormatter.dateFormat = "yyyyMMdd_HHmmss"
  	self.fileURL = directoryURL.appendingPathComponent("swift_\(fileFormatter.string(from: self.currentDate!)).log")

  	if !FileManager.default.fileExists(atPath: fileURL.path) {
    	let successful = FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: [FileAttributeKey.posixPermissions: uintPermission])
    	if successful {
    		puppyDebug("succeeded in creating filePath")
    	} else {
    		throw FileError.creatingFileFailed(at: fileURL)
    	}
  	} else {
    	puppyDebug("filePath exists, filePath: \(fileURL.path)")
  	}

  	var handle: FileHandle!
  	do {
			defer {
				try? handle?.synchronize()
				try? handle?.close()
			}
			handle = try FileHandle(forWritingTo: fileURL)
  	} catch {
	    throw FileError.openingForWritingFailed(at: fileURL)
  	}
  }
  private func ascArchivesURLs(_ folderURL: URL) -> [URL] {
    var ascArchivesURLs: [URL] = []
    do {
      let archivesDirectoryURL: URL = folderURL
      var archivesURLs:[URL]
      let directoryContents = try FileManager.default.contentsOfDirectory(at: archivesDirectoryURL, includingPropertiesForKeys: nil, options: [])
      archivesURLs = directoryContents.filter{ $0.hasDirectoryPath }

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

  private func removeArchives(_ folderURL: URL, maxArchives: UInt8) {
    do {
      let archivesURLs = ascArchivesURLs(folderURL)
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

public protocol FileRotationTimeLoggerDelegate: AnyObject, Sendable {
  func fileRotationDailyLogger(_ fileRotationTimeLogger: FileRotationTimeLogger, didRemoveArchivesURL: URL)
}
