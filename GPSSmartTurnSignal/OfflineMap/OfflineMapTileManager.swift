import Foundation
import Combine
import CoreLocation

/// Quản lý việc tải về, lưu trữ và đọc dữ liệu bản đồ OpenStreetMap Offline trên iPhone
public final class OfflineMapTileManager: ObservableObject {
    public static let shared = OfflineMapTileManager()
    
    // MARK: - Published Properties
    @Published public var availableRegions: [OfflineMapRegion] = []
    @Published public var totalDiskUsageBytes: Int64 = 0
    @Published public var isDownloadingAny: Bool = false
    
    private let fileManager = FileManager.default
    private let mapsDirectory: URL
    private let metadataURL: URL
    private let downloadQueue = OperationQueue()
    
    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.mapsDirectory = documents.appendingPathComponent("OfflineMaps", isDirectory: true)
        self.metadataURL = documents.appendingPathComponent("offline_regions.json")
        
        createDirectoriesIfNeeded()
        loadRegionsMetadata()
        calculateTotalDiskUsage()
        
        downloadQueue.maxConcurrentOperationCount = 6
    }
    
    private func createDirectoriesIfNeeded() {
        if !fileManager.fileExists(atPath: mapsDirectory.path) {
            try? fileManager.createDirectory(at: mapsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    // MARK: - Metadata Persistence
    
    private func loadRegionsMetadata() {
        if fileManager.fileExists(atPath: metadataURL.path),
           let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONDecoder().decode([OfflineMapRegion].self, from: data) {
            self.availableRegions = decoded
        } else {
            self.availableRegions = OfflineMapRegion.defaultRegions
            saveRegionsMetadata()
        }
    }
    
    private func saveRegionsMetadata() {
        if let data = try? JSONEncoder().encode(availableRegions) {
            try? data.write(to: metadataURL)
        }
    }
    
    // MARK: - Tile Storage Paths
    
    /// Đường dẫn file tile cục bộ trên đĩa
    public func localTileURL(z: Int, x: Int, y: Int) -> URL {
        return mapsDirectory.appendingPathComponent("\(z)/\(x)/\(y).png")
    }
    
    /// Kiểm tra và lấy dữ liệu tile từ bộ nhớ máy (Không cần Internet)
    public func getOfflineTileData(z: Int, x: Int, y: Int) -> Data? {
        let url = localTileURL(z: z, x: x, y: y)
        if fileManager.fileExists(atPath: url.path) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
    
    // MARK: - Tile Calculation (Slippy Map Tile Names)
    
    public static func tileX(lon: Double, zoom: Int) -> Int {
        let n = pow(2.0, Double(zoom))
        return Int(floor((lon + 180.0) / 360.0 * n))
    }
    
    public static func tileY(lat: Double, zoom: Int) -> Int {
        let latRad = lat * .pi / 180.0
        let n = pow(2.0, Double(zoom))
        let y = (1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n
        return Int(floor(y))
    }
    
    // MARK: - Region Download Operations
    
    /// Tải gói bản đồ Offline cho một khu vực
    public func downloadRegion(regionId: String) {
        guard let index = availableRegions.firstIndex(where: { $0.id == regionId }) else { return }
        var region = availableRegions[index]
        
        region.status = .downloading
        region.downloadedTiles = 0
        
        // Tính toán toàn bộ các tile cần tải
        var tilesToDownload: [(z: Int, x: Int, y: Int)] = []
        for z in region.minZoom...region.maxZoom {
            let xMin = Self.tileX(lon: region.minLon, zoom: z)
            let xMax = Self.tileX(lon: region.maxLon, zoom: z)
            let yMin = Self.tileY(lat: region.maxLat, zoom: z) // y ngược chiều latitude
            let yMax = Self.tileY(lat: region.minLat, zoom: z)
            
            for x in min(xMin, xMax)...max(xMin, xMax) {
                for y in min(yMin, yMax)...max(yMin, yMax) {
                    tilesToDownload.append((z, x, y))
                }
            }
        }
        
        region.totalTiles = tilesToDownload.count
        availableRegions[index] = region
        saveRegionsMetadata()
        isDownloadingAny = true
        
        let session = URLSession.shared
        let group = DispatchGroup()
        var completedCount = 0
        var totalBytesDownloaded: Int64 = 0
        let lock = NSLock()
        
        for item in tilesToDownload {
            let tileURL = localTileURL(z: item.z, x: item.x, y: item.y)
            // Nếu tile đã tồn tại thì bỏ qua tải lại
            if fileManager.fileExists(atPath: tileURL.path) {
                lock.lock()
                completedCount += 1
                lock.unlock()
                continue
            }
            
            group.enter()
            let osmURL = URL(string: "https://tile.openstreetmap.org/\(item.z)/\(item.x)/\(item.y).png")!
            var request = URLRequest(url: osmURL)
            request.setValue("GPS-Smart-Turn-Signal-iOS/1.0", forHTTPHeaderField: "User-Agent")
            
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                defer { group.leave() }
                guard let self = self, let d = data, error == nil else { return }
                
                // Lưu tile vào đĩa
                let folder = tileURL.deletingLastPathComponent()
                if !self.fileManager.fileExists(atPath: folder.path) {
                    try? self.fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
                }
                try? d.write(to: tileURL)
                
                lock.lock()
                completedCount += 1
                totalBytesDownloaded += Int64(d.count)
                let currentCompleted = completedCount
                lock.unlock()
                
                // Cập nhật tiến độ sau mỗi 10 tile
                if currentCompleted % 10 == 0 || currentCompleted == tilesToDownload.count {
                    DispatchQueue.main.async {
                        if let currentIndex = self.availableRegions.firstIndex(where: { $0.id == regionId }) {
                            self.availableRegions[currentIndex].downloadedTiles = currentCompleted
                            self.availableRegions[currentIndex].sizeBytes += Int64(d.count)
                        }
                    }
                }
            }
            task.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if let finalIndex = self.availableRegions.firstIndex(where: { $0.id == regionId }) {
                self.availableRegions[finalIndex].status = .downloaded
                self.availableRegions[finalIndex].downloadedTiles = self.availableRegions[finalIndex].totalTiles
                self.saveRegionsMetadata()
            }
            self.isDownloadingAny = self.availableRegions.contains(where: { $0.status == .downloading })
            self.calculateTotalDiskUsage()
        }
    }
    
    /// Xóa một khu vực bản đồ đã tải để giải phóng dung lượng bộ nhớ
    public func deleteRegion(regionId: String) {
        guard let index = availableRegions.firstIndex(where: { $0.id == regionId }) else { return }
        var region = availableRegions[index]
        
        // Xóa các file tile của khu vực
        for z in region.minZoom...region.maxZoom {
            let xMin = Self.tileX(lon: region.minLon, zoom: z)
            let xMax = Self.tileX(lon: region.maxLon, zoom: z)
            let yMin = Self.tileY(lat: region.maxLat, zoom: z)
            let yMax = Self.tileY(lat: region.minLat, zoom: z)
            
            for x in min(xMin, xMax)...max(xMin, xMax) {
                for y in min(yMin, yMax)...max(yMin, yMax) {
                    let tileURL = localTileURL(z: z, x: x, y: y)
                    try? fileManager.removeItem(at: tileURL)
                }
            }
        }
        
        region.status = .notDownloaded
        region.downloadedTiles = 0
        region.sizeBytes = 0
        availableRegions[index] = region
        saveRegionsMetadata()
        calculateTotalDiskUsage()
    }
    
    /// Xóa sạch toàn bộ bản đồ Offline trong máy
    public func clearAllOfflineData() {
        try? fileManager.removeItem(at: mapsDirectory)
        createDirectoriesIfNeeded()
        for i in 0..<availableRegions.count {
            availableRegions[i].status = .notDownloaded
            availableRegions[i].downloadedTiles = 0
            availableRegions[i].sizeBytes = 0
        }
        saveRegionsMetadata()
        totalDiskUsageBytes = 0
    }
    
    /// Tính toán tổng dung lượng thư mục bản đồ Offline
    public func calculateTotalDiskUsage() {
        var size: Int64 = 0
        if let enumerator = fileManager.enumerator(at: mapsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: []) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        DispatchQueue.main.async {
            self.totalDiskUsageBytes = size
        }
    }
    
    public var formattedTotalDiskUsage: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalDiskUsageBytes)
    }
}
