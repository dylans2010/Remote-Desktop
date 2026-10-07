import Foundation

/// Active status of a file transfer task.
public enum FileTransferState: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case cancelled
    case failed
}

/// Metadata describing a file being transferred.
public struct FileTransferMetadata: Codable, Sendable {
    public let transferID: String
    public let fileName: String
    public let fileSize: Int64
    public let totalChunks: Int

    public init(transferID: String = UUID().uuidString, fileName: String, fileSize: Int64, totalChunks: Int) {
        self.transferID = transferID
        self.fileName = fileName
        self.fileSize = fileSize
        self.totalChunks = totalChunks
    }
}

/// Chunk payload for file transfer.
public struct FileChunkPayload: Codable, Sendable {
    public let transferID: String
    public let chunkIndex: Int
    public let data: Data

    public init(transferID: String, chunkIndex: Int, data: Data) {
        self.transferID = transferID
        self.chunkIndex = chunkIndex
        self.data = data
    }
}

/// Manages chunked end-to-end encrypted file transfers between connected peers.
public final class FileTransferManager: @unchecked Sendable {
    public static let shared = FileTransferManager()

    public static let chunkSize: Int = 64 * 1024 // 64 KB chunk size

    private var activeTransfers: [String: FileTransferState] = [:]
    private var receivedChunks: [String: [Int: Data]] = [:]
    private var transferMetadata: [String: FileTransferMetadata] = [:]
    private let lock = NSLock()

    public var onProgressUpdate: ((String, Float) -> Void)?
    public var onTransferCompleted: ((String, URL) -> Void)?

    private init() {}

    /// Prepare metadata for sending a file at given file URL.
    public func prepareFileForSending(fileURL: URL) throws -> (FileTransferMetadata, [Data]) {
        let fileData = try Data(contentsOf: fileURL)
        let totalSize = Int64(fileData.count)
        let totalChunks = Int(ceil(Double(totalSize) / Double(FileTransferManager.chunkSize)))

        let metadata = FileTransferMetadata(
            fileName: fileURL.lastPathComponent,
            fileSize: totalSize,
            totalChunks: totalChunks
        )

        var chunks: [Data] = []
        for index in 0..<totalChunks {
            let start = index * FileTransferManager.chunkSize
            let length = min(FileTransferManager.chunkSize, fileData.count - start)
            let chunkData = fileData.subdata(in: start..<start + length)
            chunks.append(chunkData)
        }

        lock.lock()
        activeTransfers[metadata.transferID] = .inProgress
        lock.unlock()

        return (metadata, chunks)
    }

    /// Handle incoming file transfer metadata offer.
    public func registerIncomingOffer(metadata: FileTransferMetadata) {
        lock.lock()
        transferMetadata[metadata.transferID] = metadata
        receivedChunks[metadata.transferID] = [:]
        activeTransfers[metadata.transferID] = .pending
        lock.unlock()
    }

    /// Accept incoming file transfer offer.
    public func acceptOffer(transferID: String) {
        lock.lock()
        activeTransfers[transferID] = .inProgress
        lock.unlock()
    }

    /// Process received chunk payload.
    public func handleReceivedChunk(_ chunk: FileChunkPayload) -> URL? {
        lock.lock()
        guard activeTransfers[chunk.transferID] == .inProgress,
              let metadata = transferMetadata[chunk.transferID] else {
            lock.unlock()
            return nil
        }

        receivedChunks[chunk.transferID]?[chunk.chunkIndex] = chunk.data
        let count = receivedChunks[chunk.transferID]?.count ?? 0
        let progress = Float(count) / Float(metadata.totalChunks)
        let completed = (count == metadata.totalChunks)

        if completed {
            activeTransfers[chunk.transferID] = .completed
        }

        let chunksDict = receivedChunks[chunk.transferID] ?? [:]
        lock.unlock()

        onProgressUpdate?(chunk.transferID, progress)

        if completed {
            // Reassemble complete file
            var fileData = Data()
            for index in 0..<metadata.totalChunks {
                if let data = chunksDict[index] {
                    fileData.append(data)
                }
            }

            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(metadata.fileName)
            try? fileData.write(to: destinationURL)

            onTransferCompleted?(chunk.transferID, destinationURL)
            return destinationURL
        }

        return nil
    }

    /// Cancel active transfer task.
    public func cancelTransfer(transferID: String) {
        lock.lock()
        activeTransfers[transferID] = .cancelled
        receivedChunks.removeValue(forKey: transferID)
        transferMetadata.removeValue(forKey: transferID)
        lock.unlock()
    }
}
