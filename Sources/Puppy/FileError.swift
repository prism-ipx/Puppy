import Foundation

public enum FileError: Error, Equatable, LocalizedError, Sendable {
    case isNotFile(url: URL)
    case isNotDirectory(url: URL)
    case invalidPermission(at: URL, filePermission: String)
    case invalidFolderPermission(at: URL, folderPermission: String)
    case creatingDirectoryFailed(at: URL)
    case creatingFileFailed(at: URL)
    case openingForWritingFailed(at: URL)
    case deletingFailed(at: URL)

    public var errorDescription: String? {
        switch self {
        case .isNotDirectory(url: let url):
            return "\(url) is not a Directory"
        case .isNotFile(url: let url):
            return "\(url) is not a file"
        case .invalidPermission(at: let url, filePermission: let filePermission):
            return "invalid file permission. file: \(url), permission: \(filePermission)"
        case .invalidFolderPermission(at: let url, folderPermission: let folderPermission):
            return "invalid file permission. Folder: \(url), permission: \(folderPermission)"
        case .creatingDirectoryFailed(at: let url):
            return "failed to create a directory: \(url)"
        case .creatingFileFailed(at: let url):
            return "failed to create a file: \(url)"
        case .openingForWritingFailed(at: let url):
            return "failed to open a file for writing: \(url)"
        case .deletingFailed(at: let url):
            return "failed to delete a file: \(url)"
        }
    }
}
