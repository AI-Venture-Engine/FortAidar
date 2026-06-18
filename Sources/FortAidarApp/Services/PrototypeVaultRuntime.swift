import Foundation
import FortAidarCore

struct PrototypeVaultRuntime: Sendable {
    let identity: VaultIdentity
    private var fileManager: FileManager { .default }

    init(identity: VaultIdentity) {
        self.identity = identity
    }

    var vaultDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("FortAidar", isDirectory: true)
    }

    var vaultPath: URL {
        vaultDirectory.appendingPathComponent(identity.vaultRelativePath, isDirectory: true)
    }

    var supportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FortAidar", isDirectory: true)
    }

    var mountRoot: URL {
        supportDirectory
            .appendingPathComponent("mnt", isDirectory: true)
            .appendingPathComponent(identity.id, isDirectory: true)
    }

    func vaultExists() -> Bool {
        fileManager.fileExists(atPath: vaultPath.path)
    }

    func createVault(passphrase: String) async throws {
        try prepareBaseDirectories()
        let command = ProcessCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "create",
                "-size", "2g",
                "-type", "SPARSEBUNDLE",
                "-fs", "APFS",
                "-volname", "FortAidar",
                "-encryption", "AES-256",
                "-stdinpass",
                "-quiet",
                vaultPath.path
            ],
            stdin: passphrase + "\n"
        )
        try await command.run()
    }

    func unlock(passphrase: String) async throws -> URL {
        try prepareBaseDirectories()
        let mountPoint = mountRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        chmod(mountPoint.path, 0o700)

        let command = ProcessCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                vaultPath.path,
                "-mountpoint", mountPoint.path,
                "-stdinpass",
                "-nobrowse",
                "-noautoopen",
                "-quiet"
            ],
            stdin: passphrase + "\n"
        )
        try await command.run()
        return mountPoint
    }

    func lock(mountPoint: URL) async throws {
        let command = ProcessCommand(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", mountPoint.path, "-force"],
            stdin: nil
        )
        try await command.run()
    }

    func importItems(_ urls: [URL], into mountPoint: URL) throws -> [VaultItem] {
        var imported: [VaultItem] = []

        for source in urls {
            let destination = uniqueDestination(for: source.lastPathComponent, in: mountPoint)
            try fileManager.copyItem(at: source, to: destination)
            imported.append(item(for: destination))
        }

        return imported
    }

    func listItems(at mountPoint: URL) -> [VaultItem] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.map(item(for:)).sorted { $0.addedAt > $1.addedAt }
    }

    private func prepareBaseDirectories() throws {
        try fileManager.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mountRoot, withIntermediateDirectories: true)
        chmod(vaultDirectory.path, 0o700)
        chmod(supportDirectory.path, 0o700)
        chmod(mountRoot.path, 0o700)
    }

    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        for index in 1...999 {
            let nextName = ext.isEmpty ? "\(base) copy \(index)" : "\(base) copy \(index).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    private func item(for url: URL) -> VaultItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let isDirectory = values?.isDirectory ?? false
        let size = values?.fileSize ?? 0
        let date = values?.contentModificationDate ?? Date()

        return VaultItem(
            name: url.lastPathComponent,
            kind: isDirectory ? "Folder" : "File",
            sizeDescription: isDirectory ? "folder" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
            addedAt: date
        )
    }
}

struct ProcessCommand: Sendable {
    let executable: String
    let arguments: [String]
    let stdin: String?

    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let inputPipe: Pipe?
            if stdin != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                inputPipe = pipe
            } else {
                inputPipe = nil
            }

            process.terminationHandler = { process in
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData + outputData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: RuntimeError.commandFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
                if let stdin, let inputPipe {
                    inputPipe.fileHandleForWriting.write(Data(stdin.utf8))
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum RuntimeError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "Command failed." : message
        }
    }
}
