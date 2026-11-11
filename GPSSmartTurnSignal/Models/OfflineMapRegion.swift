import Foundation
import CoreLocation

/// Trạng thái tải của gói bản đồ Offline
public enum DownloadStatus: String, Codable {
    case notDownloaded = "Chưa tải"
    case downloading = "Đang tải..."
    case downloaded = "Đã tải về máy"
    case failed = "Tải thất bại"
}

/// Thông tin khu vực bản đồ Offline có thể tải về máy
public struct OfflineMapRegion: Identifiable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let minLat: Double
    public let maxLat: Double
    public let minLon: Double
    public let maxLon: Double
    public let minZoom: Int
    public let maxZoom: Int
    
    public var status: DownloadStatus
    public var downloadedTiles: Int
    public var totalTiles: Int
    public var sizeBytes: Int64
    
    public init(
        id: String,
        name: String,
        description: String,
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double,
        minZoom: Int = 12,
        maxZoom: Int = 15,
        status: DownloadStatus = .notDownloaded,
        downloadedTiles: Int = 0,
        totalTiles: Int = 0,
        sizeBytes: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.status = status
        self.downloadedTiles = downloadedTiles
        self.totalTiles = totalTiles
        self.sizeBytes = sizeBytes
    }
    
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
    
    public var progressPercent: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }
    
    /// Danh sách các tỉnh/thành phố tiêu biểu tại Việt Nam
    public static var defaultRegions: [OfflineMapRegion] {
        return [
            OfflineMapRegion(
                id: "hanoi",
                name: "Thủ đô Hà Nội",
                description: "Bao gồm các quận Hoàn Kiếm, Ba Đình, Đống Đa, Cầu Giấy...",
                minLat: 20.95,
                maxLat: 21.10,
                minLon: 105.75,
                maxLon: 105.90,
                minZoom: 12,
                maxZoom: 15
            ),
            OfflineMapRegion(
                id: "hcmc",
                name: "TP. Hồ Chí Minh",
                description: "Khu vực trung tâm Quận 1, Quận 3, Quận 5, Bình Thạnh, Thủ Đức...",
                minLat: 10.70,
                maxLat: 10.85,
                minLon: 106.60,
                maxLon: 106.78,
                minZoom: 12,
                maxZoom: 15
            ),
            OfflineMapRegion(
                id: "danang",
                name: "Thành phố Đà Nẵng",
                description: "Trung tâm TP Đà Nẵng, Bán đảo Sơn Trà, Ngũ Hành Sơn...",
                minLat: 15.98,
                maxLat: 16.12,
                minLon: 108.15,
                maxLon: 108.30,
                minZoom: 12,
                maxZoom: 15
            ),
            OfflineMapRegion(
                id: "haiphong",
                name: "Thành phố Hải Phòng",
                description: "Khu vực nội thành Hải Phòng và các tuyến trục chính...",
                minLat: 20.80,
                maxLat: 20.92,
                minLon: 106.62,
                maxLon: 106.75,
                minZoom: 12,
                maxZoom: 15
            ),
            OfflineMapRegion(
                id: "cantho",
                name: "Thành phố Cần Thơ",
                description: "Ninh Kiều, Cái Răng, Bình Thủy...",
                minLat: 10.00,
                maxLat: 10.08,
                minLon: 105.72,
                maxLon: 105.82,
                minZoom: 12,
                maxZoom: 15
            )
        ]
    }
}
