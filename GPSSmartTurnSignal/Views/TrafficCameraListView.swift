import SwiftUI
import CoreLocation

/// Giao diện quản lý danh sách Camera giao thông & Phạt nguội
public struct TrafficCameraListView: View {
    @ObservedObject var cameraManager = TrafficCameraManager.shared
    @ObservedObject var locationManager = LocationManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingAddAlert = false
    @State private var newCameraTitle = ""
    @State private var newCameraSpeedLimit = ""
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                // Section 1: Thao tác nhanh tại vị trí hiện tại
                Section(header: Text("Định vị camera giao thông")) {
                    Button(action: {
                        cameraManager.saveCameraAtCurrentLocation()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.badge.plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ghim Camera Tại Vị Trí Này")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Lưu ngay tọa độ GPS hiện tại vào bộ nhớ máy")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Section 2: Trạng thái cảnh báo hiện tại
                if cameraManager.isCameraWarningActive, let activeCam = cameraManager.activeWarningCamera {
                    Section(header: Text("Đang trong vùng cảnh báo")) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text(activeCam.title)
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text("Cách: \(cameraManager.warningDistanceMeters) mét • ĐÃ MỞ ĐÈN SỐ 3")
                                    .font(.subheadline)
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Section 3: Danh sách Camera đã lưu thủ công (Local)
                Section(header: Text("Camera đã lưu thủ công (\(cameraManager.localCameras.count))")) {
                    if cameraManager.localCameras.isEmpty {
                        Text("Chưa có camera nào được lưu. Hãy bấm 'Ghim Camera' khi đi ngang qua các trụ camera giao thông!")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(cameraManager.localCameras) { cam in
                            cameraRow(cam)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let id = cameraManager.localCameras[index].id
                                cameraManager.deleteCamera(id: id)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Camera Giao Thông")
            .navigationBarItems(
                leading: Button("Đóng") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: EditButton()
            )
        }
    }
    
    private func cameraRow(_ cam: TrafficCamera) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                Text(cam.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    if let userLoc = locationManager.currentLocation {
                        let camLoc = CLLocation(latitude: cam.latitude, longitude: cam.longitude)
                        let dist = Int(userLoc.distance(from: camLoc))
                        Text("Cách: \(dist)m")
                            .font(.caption)
                            .foregroundColor(dist <= 500 ? .red : .gray)
                    }
                    
                    if let speed = cam.speedLimitKmh {
                        Text("• Tối đa: \(speed) km/h")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 3)
    }
}
