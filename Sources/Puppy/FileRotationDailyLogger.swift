@preconcurrency import Dispatch
import Foundation

public final class FileRotationDailyLogger: FileLoggerable {
  private var uintPermission: UInt16 {
  	return UInt16(filePermission, radix: 8)!
  }

  private var currentDate: Date? = nil
  public let label: String
  public let queue: DispatchQueue
  public let logLevel: LogLevel
  public let logFormat: LogFormattable?
  public let inDebug: Bool
  public var fileURL: URL
  public let folderURL: URL
  public let filePermission: String

  let rotationConfig: RotationConfig
  private weak var delegate: FileRotationDailyLoggerDelegate?

  public init(_ label: String, logLevel: LogLevel = .trace, logFormat: LogFormattable? = nil, folderURL: URL, filePermission: String = "640", rotationConfig: RotationConfig, delegate: FileRotationDailyLoggerDelegate? = nil, inDebug : Bool = false) throws {
    self.label = label
    self.queue = DispatchQueue(label: label)
    self.logLevel = logLevel
    self.logFormat = logFormat
	  self.folderURL = folderURL
    self.fileURL = folderURL
    self.inDebug = inDebug
    puppyDebug("initialized, base logging folder: \(folderURL)")
    self.filePermission = filePermission

    self.rotationConfig = rotationConfig
    self.delegate = delegate

    try validateFolderURL(folderURL)
    try validateFolderPermission(folderURL, folderPermission: filePermission)
    try self.openDailyFile(rotationConfig.rotationType == .dailyinsubfolder)
    self.currentDate = Calendar.current.startOfDay(for: Date())
  }

  public func log(_ level: LogLevel, string: String) {
    rotateFiles()
    append(level, string: string)
    rotateFiles()
  }

  private func rotateFiles() {
    if currentDate != nil && self.currentDate == Calendar.current.startOfDay(for: Date()) && !self.inDebug {
	    return;
    }
    puppyDebug("Checking rotation...")

  	// Removes extra archives.
  	removeArchives(folderURL, maxArchives: rotationConfig.maxArchives)

  	// Opens a new target file.
  	do {
    	puppyDebug("will openFile in rotateFiles")
    	try openDailyFile(self.rotationConfig.rotationType == .dailyinsubfolder)
  	} catch {
    	print("error in openFile while rotating, error: \(error.localizedDescription)")
  	}
  }

  func openDailyFile(_ inSubfolder: Bool = false) throws {
		self.currentDate = Calendar.current.startOfDay(for: Date())
  	let fileDate = Calendar.current.startOfDay(for: Date())
  	var directoryURL = folderURL
  	if(inSubfolder) {
			let folderFormatter = DateFormatter()
			folderFormatter.dateFormat = "y-MM-dd"
			directoryURL.appendPathComponent(folderFormatter.string(from: fileDate), isDirectory: true)
  	}
  	do {
			try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
			puppyDebug("created directoryURL, directoryURL: \(directoryURL)")
  	} catch {
	    throw FileError.creatingDirectoryFailed(at: directoryURL)
  	}

  	let fileFormatter = DateFormatter()
  	fileFormatter.dateFormat = "yMMdd"
  	self.fileURL = directoryURL.appendingPathComponent("swift_\(fileFormatter.string(from: fileDate)).log")

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

  	// var directoryURL = folderURL
  	// if(rotationConfig.rotationType == .dailyinsubfolder) {
    // 	let fileDate = Calendar.current.startOfDay(for: Date())
		// 	let folderFormatter = DateFormatter()
		// 	folderFormatter.dateFormat = "y-MM-dd"
		// 	directoryURL.appendPathComponent(folderFormatter.string(from: fileDate), isDirectory: true)
  	// }
    do {
      let archivesDirectoryURL: URL = folderURL
      var archivesURLs:[URL]
      if(rotationConfig.rotationType == .dailyinsubfolder) {
        let directoryContents = try FileManager.default.contentsOfDirectory(at: archivesDirectoryURL, includingPropertiesForKeys: nil, options: [])
        archivesURLs = directoryContents.filter{ $0.hasDirectoryPath }
      } else {
        archivesURLs = try FileManager.default.contentsOfDirectory(atPath: archivesDirectoryURL.path)
          .map { archivesDirectoryURL.appendingPathComponent($0) }
          .filter { $0 != folderURL && $0.deletingPathExtension() == folderURL }
      }
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

public protocol FileRotationDailyLoggerDelegate: AnyObject, Sendable {
  func fileRotationDailyLogger(_ fileRotationDailyLogger: FileRotationDailyLogger, didRemoveArchivesURL: URL)
}
