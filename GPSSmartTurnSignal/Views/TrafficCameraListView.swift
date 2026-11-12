import SwiftUI
import CoreLocation
import MapKit

/// Chế độ mở màn hình thêm mới hoặc chỉnh sửa tên đường Camera giao thông
public enum CameraEditorMode: Identifiable {
    case create(coordinate: CLLocationCoordinate2D)
    case edit(camera: TrafficCamera)
    
    public var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let cam):
            return "edit-\(cam.id)"
        }
    }
}

/// Giao diện thêm hoặc chỉnh sửa thủ công tên đường / địa chỉ & giới hạn tốc độ của Camera
public struct CameraEditorSheet: View {
    @ObservedObject var cameraManager = TrafficCameraManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    public let mode: CameraEditorMode
    
    @State private var streetTitle: String = ""
    @State private var speedLimitText: String = ""
    @State private var isResolvingAddress: Bool = false
    
    public init(mode: CameraEditorMode) {
        self.mode = mode
        switch mode {
        case .create:
            _streetTitle = State(initialValue: "")
            _speedLimitText = State(initialValue: "")
        case .edit(let cam):
            _streetTitle = State(initialValue: cam.title)
            _speedLimitText = State(initialValue: cam.speedLimitKmh.map { String($0) } ?? "")
        }
    }
    
    private var targetCoordinate: CLLocationCoordinate2D {
        switch mode {
        case .create(let coord): return coord
        case .edit(let cam): return cam.coordinate
        }
    }
    
    private var navigationTitleText: String {
        switch mode {
        case .create: return "Ghim Camera Mới"
        case .edit: return "Sửa Thông Tin Camera"
        }
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Tên đường / Địa chỉ gần đúng"),
                    footer: Text("Hệ thống tự lấy tên đường hoặc địa chỉ gần đúng. Bạn có thể nhập lại thủ công; nếu bỏ trống sẽ tự động lưu là \"No name\".")
                ) {
                    HStack {
                        TextField("Nhập tên đường hoặc để trống (No name)", text: $streetTitle)
                            .autocapitalization(.words)
                        
                        if !streetTitle.isEmpty {
                            Button(action: { streetTitle = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    
                    Button(action: fetchStreetAddress) {
                        HStack(spacing: 8) {
                            if isResolvingAddress {
                                ProgressView()
                                    .scaleEffect(0.85)
                                Text("Đang tìm tên đường từ tọa độ...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "location.magnifyingglass")
                                    .foregroundColor(.blue)
                                Text("Tự động lấy tên đường / địa chỉ")
                            }
                        }
                    }
                    .disabled(isResolvingAddress)
                }
                
                Section(header: Text("Giới hạn tốc độ (Tùy chọn)")) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.orange)
                        TextField("Ví dụ: 50, 60, 80 (bỏ trống nếu không rõ)", text: $speedLimitText)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section(header: Text("Tọa độ GPS đã chốt")) {
                    HStack {
                        Text("Vĩ độ / Kinh độ")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.5f, %.5f", targetCoordinate.latitude, targetCoordinate.longitude))
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Hủy") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Lưu") {
                    saveChanges()
                }
                .font(.headline)
            )
            .onAppear {
                if case .create = mode {
                    fetchStreetAddress()
                }
            }
        }
    }
    
    private func fetchStreetAddress() {
        isResolvingAddress = true
        cameraManager.resolveStreetAddress(for: targetCoordinate) { resolved in
            isResolvingAddress = false
            let current = streetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || current == "No name" {
                streetTitle = resolved
            }
        }
    }
    
    private func saveChanges() {
        let trimmed = streetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "No name" : trimmed
        let parsedSpeed = Int(speedLimitText.trimmingCharacters(in: .whitespacesAndNewlines))
        
        switch mode {
        case .create(let coord):
            cameraManager.saveCameraAtCurrentLocation(
                title: finalTitle,
                speedLimit: parsedSpeed,
                customCoordinate: coord
            )
        case .edit(let cam):
            cameraManager.updateCamera(
                id: cam.id,
                title: finalTitle,
                speedLimit: parsedSpeed
            )
        }
        presentationMode.wrappedValue.dismiss()
    }
}

/// Giao diện quản lý danh sách Camera giao thông & Phạt nguội
public struct TrafficCameraListView: View {
    @ObservedObject var cameraManager = TrafficCameraManager.shared
    @ObservedObject var locationManager = LocationManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var editorMode: CameraEditorMode? = nil
    @State private var showingNoGPSAlert = false
    
    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter
    }()
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                // Section 1: Thao tác ghim camera tại vị trí hiện tại
                Section(
                    header: Text("Định vị camera giao thông"),
                    footer: Text("Ghim vị trí kèm tự động lấy tên đường (hoặc sửa thủ công). Nếu không có mạng hoặc không tìm thấy tên đường sẽ ghi \"No name\".")
                ) {
                    Button(action: {
                        guard let coord = locationManager.currentLocation?.coordinate else {
                            showingNoGPSAlert = true
                            return
                        }
                        editorMode = .create(coordinate: coord)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.badge.plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ghim Camera Tại Vị Trí Này")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Chốt tọa độ hiện tại, tự lấy tên đường hoặc nhập thủ công")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button(action: {
                        cameraManager.saveCameraAtCurrentLocation()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ghim Nhanh 1 Chạm")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Lưu ngay và tự động dò tên đường ngầm")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Section 2: Trạng thái cảnh báo hiện tại
                if cameraManager.isCameraWarningActive, let activeCam = cameraManager.activeWarningCamera {
                    Section(header: Text("Đang trong vùng cảnh báo")) {
                        Button(action: {
                            openCameraOnMap(activeCam)
                        }) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activeCam.title)
                                        .font(.headline)
                                        .foregroundColor(.red)
                                    Text("Cách: \(cameraManager.warningDistanceMeters) mét • ĐÃ MỞ ĐÈN SỐ 3")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                Image(systemName: "map.fill")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Section 3: Danh sách Camera đã lưu thủ công (Local)
                Section(
                    header: Text("Camera đã lưu thủ công (\(cameraManager.localCameras.count))"),
                    footer: Text("Nhấp trực tiếp vào một camera để mở bản đồ ngay tại vị trí đó.")
                ) {
                    if cameraManager.localCameras.isEmpty {
                        Text("Chưa có camera nào được lưu. Hãy bấm 'Ghim Camera' khi đi ngang qua các trụ camera giao thông!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(cameraManager.localCameras) { cam in
                            cameraRow(cam, editable: true)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let id = cameraManager.localCameras[index].id
                                cameraManager.deleteCamera(id: id)
                            }
                        }
                    }
                }
                
                // Section 4: Danh sách Camera từ OpenStreetMap (nếu đã tải cache)
                if !cameraManager.osmCameras.isEmpty {
                    Section(header: Text("Camera OpenStreetMap (\(cameraManager.osmCameras.count))")) {
                        ForEach(cameraManager.osmCameras) { cam in
                            cameraRow(cam, editable: false)
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
            .sheet(item: $editorMode) { mode in
                CameraEditorSheet(mode: mode)
            }
            .alert(isPresented: $showingNoGPSAlert) {
                Alert(
                    title: Text("Chưa có tín hiệu GPS"),
                    message: Text("Vui lòng chờ thiết bị định vị xong tọa độ hiện tại rồi thử lại."),
                    dismissButton: .default(Text("Đã hiểu"))
                )
            }
        }
    }
    
    private func cameraRow(_ cam: TrafficCamera, editable: Bool) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                openCameraOnMap(cam)
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                        .frame(width: 34, height: 34)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cam.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        HStack(spacing: 6) {
                            if let userLoc = locationManager.currentLocation {
                                let camLoc = CLLocation(latitude: cam.latitude, longitude: cam.longitude)
                                let dist = Int(userLoc.distance(from: camLoc))
                                Text("Cách: \(dist)m")
                                    .font(.caption)
                                    .foregroundColor(dist <= Int(AppSettings.shared.cameraWarningDistanceMeters) ? .red : .secondary)
                            }
                            
                            if let speed = cam.speedLimitKmh {
                                Text("• Tối đa: \(speed) km/h")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Text("\(Self.rowDateFormatter.string(from: cam.createdAt)) • \(String(format: "%.5f, %.5f", cam.latitude, cam.longitude))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BorderlessButtonStyle())
            
            if editable {
                Button(action: {
                    editorMode = .edit(camera: cam)
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .accessibilityLabel("Sửa tên camera")
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(action: { openCameraOnMap(cam) }) {
                Label("Xem trên bản đồ ứng dụng", systemImage: "map.fill")
            }
            if editable {
                Button(action: { editorMode = .edit(camera: cam) }) {
                    Label("Sửa tên đường / Tốc độ", systemImage: "pencil")
                }
            }
            Button(action: { openInAppleMaps(cam) }) {
                Label("Mở bằng Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
            }
            if editable {
                Button(role: .destructive, action: { cameraManager.deleteCamera(id: cam.id) }) {
                    Label("Xóa camera", systemImage: "trash")
                }
            }
        }
    }
    
    private func openCameraOnMap(_ cam: TrafficCamera) {
        cameraManager.focusMapOnCamera(cam)
        presentationMode.wrappedValue.dismiss()
    }
    
    private func openInAppleMaps(_ cam: TrafficCamera) {
        let placemark = MKPlacemark(coordinate: cam.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = cam.title
        mapItem.openInMaps(launchOptions: nil)
    }
}
