import Foundation

/// Protocol abstraction for file system operations to enable testing
protocol FileSystemProtocol {
  func fileExists(at url: URL) -> Bool
  func fileExists(atPath path: String) -> Bool
  func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
  func copyItem(at srcURL: URL, to dstURL: URL) throws
  func moveItem(at srcURL: URL, to dstURL: URL) throws
  func removeItem(at url: URL) throws
  func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws
    -> [URL]
  func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
  func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws
  func createFile(atPath path: String, contents data: Data?, attributes: [FileAttributeKey: Any]?)
    -> Bool
}

/// Real implementation using FileManager
final class RealFileSystem: FileSystemProtocol {
  private let fileManager = FileManager.default

  func fileExists(at url: URL) -> Bool {
    fileManager.fileExists(atPath: url.path)
  }

  func fileExists(atPath path: String) -> Bool {
    fileManager.fileExists(atPath: path)
  }

  func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
    try fileManager.createDirectory(
      at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
  }

  func copyItem(at srcURL: URL, to dstURL: URL) throws {
    try fileManager.copyItem(at: srcURL, to: dstURL)
  }

  func moveItem(at srcURL: URL, to dstURL: URL) throws {
    try fileManager.moveItem(at: srcURL, to: dstURL)
  }

  func removeItem(at url: URL) throws {
    try fileManager.removeItem(at: url)
  }

  func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws
    -> [URL]
  {
    try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
  }

  func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
    try fileManager.attributesOfItem(atPath: path)
  }

  func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
    try fileManager.setAttributes(attributes, ofItemAtPath: path)
  }

  func createFile(atPath path: String, contents data: Data?, attributes: [FileAttributeKey: Any]?)
    -> Bool
  {
    fileManager.createFile(atPath: path, contents: data, attributes: attributes)
  }
}

/// Mock implementation for testing
final class MockFileSystem: FileSystemProtocol {
  var files: Set<String> = []
  var directories: Set<String> = []
  var fileContents: [String: Data] = [:]
  var fileAttributes: [String: [FileAttributeKey: Any]] = [:]

  var shouldFailCopy = false
  var shouldFailMove = false
  var shouldFailCreate = false

  func fileExists(at url: URL) -> Bool {
    fileExists(atPath: url.path)
  }

  func fileExists(atPath path: String) -> Bool {
    files.contains(path) || directories.contains(path)
  }

  func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
    if shouldFailCreate {
      throw NSError(
        domain: "MockFileSystem", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Mock create directory failed"])
    }

    directories.insert(url.path)

    if withIntermediateDirectories {
      // Add parent directories
      var parentURL = url.deletingLastPathComponent()
      while parentURL.path != "/" && !parentURL.path.isEmpty {
        directories.insert(parentURL.path)
        parentURL = parentURL.deletingLastPathComponent()
      }
    }
  }

  func copyItem(at srcURL: URL, to dstURL: URL) throws {
    if shouldFailCopy {
      throw NSError(
        domain: "MockFileSystem", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mock copy failed"]
      )
    }

    guard files.contains(srcURL.path) else {
      throw NSError(
        domain: "MockFileSystem", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Source file not found"])
    }

    files.insert(dstURL.path)
    if let content = fileContents[srcURL.path] {
      fileContents[dstURL.path] = content
    }
    if let attrs = fileAttributes[srcURL.path] {
      fileAttributes[dstURL.path] = attrs
    }
  }

  func moveItem(at srcURL: URL, to dstURL: URL) throws {
    if shouldFailMove {
      throw NSError(
        domain: "MockFileSystem", code: 4, userInfo: [NSLocalizedDescriptionKey: "Mock move failed"]
      )
    }

    try copyItem(at: srcURL, to: dstURL)
    try removeItem(at: srcURL)
  }

  func removeItem(at url: URL) throws {
    files.remove(url.path)
    directories.remove(url.path)
    fileContents.removeValue(forKey: url.path)
    fileAttributes.removeValue(forKey: url.path)
  }

  func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws
    -> [URL]
  {
    guard directories.contains(url.path) else {
      throw NSError(
        domain: "MockFileSystem", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "Directory not found"])
    }

    let dirPath = url.path.hasSuffix("/") ? url.path : url.path + "/"

    return files.compactMap { filePath in
      if filePath.hasPrefix(dirPath) {
        let relativePath = String(filePath.dropFirst(dirPath.count))
        if !relativePath.contains("/") {
          return URL(fileURLWithPath: filePath)
        }
      }
      return nil
    }
  }

  func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
    guard files.contains(path) || directories.contains(path) else {
      throw NSError(
        domain: "MockFileSystem", code: 6, userInfo: [NSLocalizedDescriptionKey: "Item not found"])
    }

    return fileAttributes[path] ?? [
      .size: fileContents[path]?.count ?? 0,
      .type: directories.contains(path)
        ? FileAttributeType.typeDirectory : FileAttributeType.typeRegular,
    ]
  }

  func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
    guard files.contains(path) || directories.contains(path) else {
      throw NSError(
        domain: "MockFileSystem", code: 7, userInfo: [NSLocalizedDescriptionKey: "Item not found"])
    }

    if fileAttributes[path] == nil {
      fileAttributes[path] = [:]
    }
    fileAttributes[path]?.merge(attributes) { _, new in new }
  }

  func createFile(atPath path: String, contents data: Data?, attributes: [FileAttributeKey: Any]?)
    -> Bool
  {
    if shouldFailCreate {
      return false
    }

    files.insert(path)
    fileContents[path] = data
    fileAttributes[path] = attributes
    return true
  }

  // Test helper methods
  func reset() {
    files.removeAll()
    directories.removeAll()
    fileContents.removeAll()
    fileAttributes.removeAll()
    shouldFailCopy = false
    shouldFailMove = false
    shouldFailCreate = false
  }

  func addTestFile(at path: String, contents: Data? = nil, size: Int? = nil) {
    files.insert(path)
    fileContents[path] = contents ?? Data("test".utf8)
    fileAttributes[path] = [.size: size ?? fileContents[path]?.count ?? 0]
  }

  func addTestDirectory(at path: String) {
    directories.insert(path)
  }
}
