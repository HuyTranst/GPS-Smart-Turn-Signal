import SwiftUI

/// Màn hình quản lý tải và xóa các gói bản đồ OpenStreetMap Offline trên iPhone
public struct OfflineMapManagerView: View {
    @ObservedObject var mapManager = OfflineMapTileManager.shared
    @State private var showingClearConfirmation = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                // Section 1: Thống kê dung lượng
                Section(header: Text("DUNG LƯỢNG BẢN ĐỒ OFFLINE")) {
                    HStack {
                        Label("Đang sử dụng trên máy", systemImage: "internaldrive.fill")
                        Spacer()
                        Text(mapManager.formattedTotalDiskUsage)
                            .bold()
                            .foregroundColor(.blue)
                    }
                    
                    if mapManager.totalDiskUsageBytes > 0 {
                        Button(role: .destructive, action: {
                            showingClearConfirmation = true
                        }) {
                            Label("Xóa sạch toàn bộ bản đồ đã tải", systemImage: "trash.fill")
                        }
                    }
                }
                
                // Section 2: Danh sách các khu vực có sẵn
                Section(header: Text("CÁC TỈNH / THÀNH PHỐ")) {
                    ForEach(mapManager.availableRegions) { region in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(region.name)
                                        .font(.headline)
                                    Text(region.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Nút trạng thái
                                switch region.status {
                                case .notDownloaded, .failed:
                                    Button(action: {
                                        mapManager.downloadRegion(regionId: region.id)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.down.circle.fill")
                                            Text("Tải về")
                                        }
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                case .downloading:
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    
                                case .downloaded:
                                    Button(action: {
                                        mapManager.deleteRegion(regionId: region.id)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("Đã tải")
                                                .foregroundColor(.secondary)
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .font(.caption)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            // Thanh tiến độ khi đang tải
                            if region.status == .downloading {
                                VStack(alignment: .leading, spacing: 2) {
                                    ProgressView(value: region.progressPercent)
                                        .accentColor(.blue)
                                    HStack {
                                        Text("\(region.downloadedTiles) / \(region.totalTiles) ô bản đồ")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(region.progressPercent * 100))%")
                                            .font(.caption2.bold())
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            if region.status == .downloaded {
                                HStack {
                                    Text("Dung lượng: \(region.formattedSize)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("Zoom \(region.minZoom) - \(region.maxZoom)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                
                // Section 3: Ghi chú sử dụng Offline
                Section(header: Text("LƯU Ý HOẠT ĐỘNG OFFLINE")) {
                    Text("• Dữ liệu bản đồ được lấy từ OpenStreetMap và lưu trực tiếp vào bộ nhớ iPhone.\n• Khi mất sóng điện thoại hoặc không có Internet, bản đồ và GPS vẫn hoạt động bình thường trên các khu vực đã tải.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Bản Đồ Offline")
            .confirmationDialog("Xác nhận xóa toàn bộ?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("Xóa tất cả", role: .destructive) {
                    mapManager.clearAllOfflineData()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Toàn bộ các gói bản đồ OpenStreetMap đã tải về máy sẽ bị xóa.")
            }
        }
    }
}
