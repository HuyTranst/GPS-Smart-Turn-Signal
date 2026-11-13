import SwiftUI
import CoreLocation
import MapKit

/// View biểu tượng Camera giám sát an ninh CCTV gắn tường (chuẩn theo hình người dùng cung cấp)
public struct CCTVCameraIconView: View {
    public var size: CGFloat
    public var color: Color
    
    public init(size: CGFloat = 20, color: Color = .white) {
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        if UIImage(named: "cctv_camera") != nil {
            Image("cctv_camera")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundColor(color)
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: size * 0.85, weight: .bold))
                .foregroundColor(color)
        }
    }
}

/// Chế độ mở màn hình thêm mới hoặc chỉnh sửa tên đường Camera giao thông
public enum CameraEditorMode: Identifiable {
    case create(coordinate: CLLocationCoordinate2D)
    case edit(camera: TrafficCamera)
    
    public var id: String {
        switch self {
        case .create(let coord):
            return "create-\(coord.latitude)-\(coord.longitude)"
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
                Section {
                    HStack(spacing: 14) {
                        CCTVCameraIconView(size: 32, color: .orange)
                            .frame(width: 44, height: 44)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(navigationTitleText)
                                .font(.headline)
                            Text("Tọa độ: \(String(format: "%.5f, %.5f", targetCoordinate.latitude, targetCoordinate.longitude))")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(
                    header: Text("Tên đường / Địa chỉ gần đúng"),
                    footer: Text("Hệ thống tự động dò tên đường gần đúng. Bạn có thể chỉnh sửa lại thủ công; nếu bỏ trống sẽ tự lưu là \"No name\".")
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
                                Text("Đang dò tên đường từ tọa độ...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "location.magnifyingglass")
                                    .foregroundColor(.blue)
                                Text("Tự động lấy lại tên đường / địa chỉ")
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
    @State private var showingSyncAlert = false
    
    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter
    }()
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                // Section 0: Cấu hình nhanh cự ly cảnh báo & nhịp rung (đồng bộ cùng Cài đặt)
                Section(
                    header: Text("Cài đặt cảnh báo & nhịp rung"),
                    footer: Text("Khi xe tiến vào cự ly cài đặt, máy sẽ phát âm thanh cảnh báo, mở Relay 3 trên ESP32 và rung chu kỳ dồn dập.")
                ) {
                    HStack {
                        Text("Khoảng cách cảnh báo")
                        Spacer()
                        Text("\(Int(AppSettings.shared.cameraWarningDistanceMeters)) mét")
                            .bold()
                            .foregroundColor(.orange)
                    }
                    Slider(value: Binding(
                        get: { AppSettings.shared.cameraWarningDistanceMeters },
                        set: { AppSettings.shared.cameraWarningDistanceMeters = $0 }
                    ), in: 50...1000, step: 10)
                    
                    Toggle(isOn: Binding(
                        get: { AppSettings.shared.isCameraRepeatingVibrationEnabled },
                        set: { AppSettings.shared.isCameraRepeatingVibrationEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rung lặp lại khi trong vùng camera")
                                .font(.body.bold())
                            Text("Rung dồn dập rồi tạm nghỉ, lặp lại cho đến khi ra khỏi vùng")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Stepper(value: Binding(
                        get: { AppSettings.shared.cameraVibrationPulses },
                        set: { AppSettings.shared.cameraVibrationPulses = $0 }
                    ), in: 1...10) {
                        HStack {
                            Text("Số nhịp rung mỗi đợt")
                                .font(.body.bold())
                            Spacer()
                            Text("\(AppSettings.shared.cameraVibrationPulses) lần")
                                .bold()
                                .foregroundColor(.orange)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Thời gian nghỉ giữa các đợt rung")
                                .font(.body.bold())
                            Spacer()
                            Text(String(format: "%.1f giây", AppSettings.shared.cameraVibrationPauseSeconds))
                                .bold()
                                .foregroundColor(.orange)
                        }
                        Slider(value: Binding(
                            get: { AppSettings.shared.cameraVibrationPauseSeconds },
                            set: { AppSettings.shared.cameraVibrationPauseSeconds = $0 }
                        ), in: 1.0...8.0, step: 0.5)
                        Text("Mặc định: Rung 5 lần dồn dập, nghỉ 3.0 giây, sau đó rung tiếp.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        cameraManager.triggerTestCameraVibration()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundColor(.orange)
                            Text("Bấm Thử Nghiệm Nhịp Rung Ngay (\(AppSettings.shared.cameraVibrationPulses) lần)")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Section 1: Thao tác ghim camera (tại xe hoặc từ xa theo tâm bản đồ)
                Section(
                    header: Text("Định vị & Ghim camera giao thông"),
                    footer: Text("Có thể ghim tại vị trí xe hiện tại HOẶC rê bản đồ đến ngã tư bất kỳ rồi ghim từ xa mà không cần chạy xe đến nơi.")
                ) {
                    // 1. Ghim tại vị trí xe hiện tại
                    Button(action: {
                        guard let coord = locationManager.currentLocation?.coordinate else {
                            showingNoGPSAlert = true
                            return
                        }
                        editorMode = .create(coordinate: coord)
                    }) {
                        HStack(spacing: 12) {
                            CCTVCameraIconView(size: 22, color: .orange)
                                .frame(width: 32, height: 32)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ghim Tại Vị Trí Xe Hiện Tại")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Chốt tọa độ GPS hiện tại, tự lấy tên đường hoặc nhập thủ công")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    
                    // 2. Ghim tại vị trí tâm bản đồ đang xem (Ghim từ xa)
                    if let centerCoord = cameraManager.currentMapCenterCoordinate {
                        Button(action: {
                            editorMode = .create(coordinate: centerCoord)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "scope")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.blue)
                                    .frame(width: 32, height: 32)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ghim Tại Vị Trí Tâm Bản Đồ (Từ xa)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("Tọa độ tâm: \(String(format: "%.4f, %.4f", centerCoord.latitude, centerCoord.longitude))")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    
                    // 3. Ghim nhanh 1 chạm
                    Button(action: {
                        cameraManager.saveCameraAtCurrentLocation()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.yellow)
                                .frame(width: 32, height: 32)
                            
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
                                CCTVCameraIconView(size: 22, color: .red)
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
                        Text("Chưa có camera nào được lưu. Hãy bấm 'Ghim Camera' hoặc nhấn giữ trên bản đồ để thêm!")
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
                
                // Section 4: Dữ liệu Camera Offline (Cần Thơ, Sóc Trăng & Toàn Quốc)
                Section(
                    header: Text("Dữ liệu camera offline (\(cameraManager.osmCameras.count))"),
                    footer: Text("Bộ dữ liệu camera AI phạt nguội và bắn tốc độ tại TP. Cần Thơ, Tỉnh Sóc Trăng, TP.HCM, Hà Nội, Đà Nẵng hoạt động 100% không cần Internet.")
                ) {
                    // Nạp camera Cần Thơ & Sóc Trăng
                    Button(action: {
                        cameraManager.loadCanThoSocTrangPresetCameras(notify: true)
                        showingSyncAlert = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nạp Camera Cần Thơ & Sóc Trăng (22 Điểm)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Gồm 12 nút giao Cần Thơ, 8 nút giao Sóc Trăng, Cầu Cần Thơ, QL1A")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    
                    // Di chuyển bản đồ đến Cần Thơ để xem
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                        cameraManager.focusMapOnCanTho()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "map.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Di Chuyển Bản Đồ Đến Cần Thơ")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                                Text("Ninh Kiều, Cái Răng, Bình Thủy, Cầu Quang Trung...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    
                    // Di chuyển bản đồ đến Sóc Trăng để xem
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                        cameraManager.focusMapOnSocTrang()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Di Chuyển Bản Đồ Đến Sóc Trăng")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.purple)
                                Text("Trần Hưng Đạo, Lê Duẩn, Lê Hồng Phong, Ngã 3 Trà Tim, QL1A...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    
                    // Nạp trọn bộ Việt Nam
                    Button(action: {
                        cameraManager.loadBuiltinVietnamPresetCameras(notify: true)
                        showingSyncAlert = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nạp Trọn Bộ Camera Việt Nam")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Gồm cả Cần Thơ, Sóc Trăng, TP.HCM, Hà Nội, Đà Nẵng, Cao tốc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    
                    ForEach(cameraManager.osmCameras) { cam in
                        cameraRow(cam, editable: false)
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
                    message: Text("Vui lòng chờ thiết bị định vị xong tọa độ hiện tại hoặc rê bản đồ rồi chọn 'Ghim tại tâm bản đồ'."),
                    dismissButton: .default(Text("Đã hiểu"))
                )
            }
            .alert(isPresented: $showingSyncAlert) {
                Alert(
                    title: Text("Đã nạp camera offline"),
                    message: Text("Đã lưu các điểm camera trọng điểm vào bộ nhớ máy, sẵn sàng cảnh báo 150m không cần mạng."),
                    dismissButton: .default(Text("Tuyệt vời"))
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
                    CCTVCameraIconView(size: 20, color: .orange)
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
