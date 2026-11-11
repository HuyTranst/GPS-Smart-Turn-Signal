import SwiftUI
import MapKit

/// Bộ tạo hình ảnh biểu tượng phương tiện (xe ô tô / xe máy thể thao nhìn từ trên xuống)
public struct VehicleIconGenerator {
    public static func createSportVehicleIcon() -> UIImage {
        let size = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let cg = ctx.cgContext
            
            // 1. Luồng đèn pha chiếu sáng phía trước (Headlight beam)
            let beamPath = CGMutablePath()
            beamPath.move(to: CGPoint(x: 22, y: 12))
            beamPath.addLine(to: CGPoint(x: 10, y: 1))
            beamPath.addLine(to: CGPoint(x: 34, y: 1))
            beamPath.closeSubpath()
            
            cg.addPath(beamPath)
            cg.setFillColor(UIColor.systemYellow.withAlphaComponent(0.35).cgColor)
            cg.fillPath()
            
            // 2. Bóng đổ xe (Drop shadow)
            let shadowRect = CGRect(x: 14, y: 9, width: 16, height: 28)
            let shadowPath = UIBezierPath(roundedRect: shadowRect, cornerRadius: 8)
            cg.addPath(shadowPath.cgPath)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            cg.fillPath()
            
            // 3. Thân xe thể thao (Chassis) - Màu Electric Cyan công nghệ cao
            let bodyRect = CGRect(x: 14, y: 8, width: 16, height: 26)
            let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: 7)
            cg.addPath(bodyPath.cgPath)
            cg.setFillColor(UIColor(red: 0.05, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
            cg.fillPath()
            
            // Viền kim loại sắc sảo
            cg.addPath(bodyPath.cgPath)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            cg.setLineWidth(1.5)
            cg.strokePath()
            
            // 4. Kính chắn gió trước (Windshield)
            let frontGlassRect = CGRect(x: 16.5, y: 14, width: 11, height: 5)
            let frontGlassPath = UIBezierPath(roundedRect: frontGlassRect, cornerRadius: 2)
            cg.addPath(frontGlassPath.cgPath)
            cg.setFillColor(UIColor(white: 0.15, alpha: 0.95).cgColor)
            cg.fillPath()
            
            // 5. Nóc xe & kính sau
            let roofRect = CGRect(x: 17, y: 19, width: 10, height: 6)
            let roofPath = UIBezierPath(roundedRect: roofRect, cornerRadius: 1.5)
            cg.addPath(roofPath.cgPath)
            cg.setFillColor(UIColor(red: 0.02, green: 0.45, blue: 0.85, alpha: 1.0).cgColor)
            cg.fillPath()
            
            let rearGlassRect = CGRect(x: 17, y: 25.5, width: 10, height: 3)
            let rearGlassPath = UIBezierPath(roundedRect: rearGlassRect, cornerRadius: 1)
            cg.addPath(rearGlassPath.cgPath)
            cg.setFillColor(UIColor(white: 0.2, alpha: 0.95).cgColor)
            cg.fillPath()
            
            // 6. Cặp đèn pha trước (Trắng / Vàng rực)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: 15, y: 8, width: 3, height: 2))
            cg.fillEllipse(in: CGRect(x: 26, y: 8, width: 3, height: 2))
            
            // 7. Cặp đèn hậu đỏ sau xe
            cg.setFillColor(UIColor.systemRed.cgColor)
            cg.fillEllipse(in: CGRect(x: 15, y: 32, width: 3, height: 2))
            cg.fillEllipse(in: CGRect(x: 26, y: 32, width: 3, height: 2))
        }
    }
}

/// Lớp hiển thị Marker chiếc xe trên bản đồ với khả năng xoay 360 độ theo góc lái thực tế
public class VehicleAnnotationView: MKAnnotationView {
    private let vehicleImageView = UIImageView()
    private let pulseRingView = UIView()
    private var currentHeading: Double = 0.0
    
    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupVehicleView()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupVehicleView()
    }
    
    private func setupVehicleView() {
        frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        centerOffset = CGPoint(x: 0, y: 0)
        canShowCallout = false
        displayPriority = .required
        zPriority = .max
        
        // Vòng hào quang định vị bên dưới xe
        pulseRingView.frame = CGRect(x: 5, y: 5, width: 40, height: 40)
        pulseRingView.layer.cornerRadius = 20
        pulseRingView.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.18)
        pulseRingView.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.55).cgColor
        pulseRingView.layer.borderWidth = 1.2
        addSubview(pulseRingView)
        
        // Hình ảnh chiếc xe tự xoay
        vehicleImageView.frame = CGRect(x: 3, y: 3, width: 44, height: 44)
        vehicleImageView.contentMode = .center
        vehicleImageView.image = VehicleIconGenerator.createSportVehicleIcon()
        addSubview(vehicleImageView)
    }
    
    /// Cập nhật góc xoay xe mượt mà theo góc phương vị GPS (Course / Heading)
    public func updateHeading(degrees: Double) {
        guard degrees >= 0 else { return }
        currentHeading = degrees
        let radians = CGFloat(degrees * .pi / 180.0)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.vehicleImageView.transform = CGAffineTransform(rotationAngle: radians)
        }
    }
}

/// MKTileOverlay tùy chỉnh: Khắc phục triệt để lỗi màn hình đen khi zoom nhỏ hoặc chưa tải tile
public class OfflineMKTileOverlay: MKTileOverlay {
    // 1x1 Transparent PNG data để thay thế khi không có tile (ngăn MapKit vẽ ô vuông màu đen)
    private static let transparentPixelPNG: Data = {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        return Data(base64Encoded: base64) ?? Data()
    }()
    
    public override init() {
        super.init(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        // Quan trọng: Để false để MapKit không coi lớp này che toàn bộ màn hình, tránh lỗi ô vuông đen
        self.canReplaceMapContent = false
    }
    
    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        return URL(string: "https://tile.openstreetmap.org/\(path.z)/\(path.x)/\(path.y).png")!
    }
    
    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        // 1. Ưu tiên đọc dữ liệu tile từ bộ nhớ máy (Offline hoàn toàn)
        if let offlineData = OfflineMapTileManager.shared.getOfflineTileData(z: path.z, x: path.x, y: path.y) {
            result(offlineData, nil)
            return
        }
        
        // 2. Nếu chưa có trong bộ nhớ, tải trực tuyến qua mạng nếu có internet
        let osmURL = self.url(forTilePath: path)
        var request = URLRequest(url: osmURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
        request.setValue("GPS-Smart-Turn-Signal-iOS/1.0 (Vietnam Motorcycle Navigation)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let d = data, let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                // Tự động ghi vào bộ nhớ đệm
                let localURL = OfflineMapTileManager.shared.localTileURL(z: path.z, x: path.x, y: path.y)
                let folder = localURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: folder.path) {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                try? d.write(to: localURL)
                result(d, nil)
            } else {
                // KHẮC PHỤC LỖI Ô ĐEN: Nếu không có dữ liệu, trả về ảnh trong suốt
                // Nhờ đó MapKit hiển thị lớp bản đồ mặc định phía dưới mượt mà, không bao giờ bị đen xì!
                result(Self.transparentPixelPNG, nil)
            }
        }.resume()
    }
}

/// UIViewRepresentable bọc MKMapView với biểu tượng xe đẹp mắt và bản đồ OpenStreetMap không bao giờ bị đen
public struct OfflineMapView: UIViewRepresentable {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var navigationEngine = NavigationEngine.shared
    
    public init() {}
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = false
        
        // Cài đặt lớp bản đồ OpenStreetMap với canReplaceMapContent = false
        let tileOverlay = OfflineMKTileOverlay()
        mapView.addOverlay(tileOverlay, level: .aboveRoads)
        
        context.coordinator.mapView = mapView
        return mapView
    }
    
    public func updateUIView(_ mapView: MKMapView, context: Context) {
        // Cập nhật tuyến đường khi có dẫn đường
        if let route = navigationEngine.activeRoute {
            context.coordinator.updateRoute(route: route, on: mapView)
        } else {
            context.coordinator.clearRoute(on: mapView)
        }
        
        // Tự động cập nhật góc xoay biểu tượng chiếc xe theo hướng di chuyển thực tế
        if let userView = mapView.view(for: mapView.userLocation) as? VehicleAnnotationView {
            let course = locationManager.currentCourse
            if course >= 0 {
                userView.updateHeading(degrees: course)
            }
        }
        
        // Tự động điều chỉnh góc zoom thông minh theo dải tốc độ (không giật liên tục)
        if let loc = locationManager.currentLocation {
            context.coordinator.handleSmartAutoZoom(
                location: loc,
                speedKmh: locationManager.currentSpeedKmh,
                course: locationManager.currentCourse
            )
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OfflineMapView
        weak var mapView: MKMapView?
        private var currentPolyline: MKPolyline?
        private var maneuverAnnotations: [MKPointAnnotation] = []
        
        // Quản lý Auto Zoom thông minh chống giật liên tục
        private var lastZoomDistance: Double = 0.0
        private var lastZoomTime: Date = Date.distantPast
        private var hasInitialZoomed: Bool = false
        
        init(_ parent: OfflineMapView) {
            self.parent = parent
            super.init()
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("RecenterMapOnUser"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, let mv = self.mapView, let loc = LocationManager.shared.currentLocation else { return }
                let targetDist = self.calculateTargetDistance(speedKmh: LocationManager.shared.currentSpeedKmh)
                self.lastZoomDistance = targetDist
                self.lastZoomTime = Date()
                let cam = MKMapCamera(
                    lookingAtCenter: loc.coordinate,
                    fromDistance: targetDist,
                    pitch: 35,
                    heading: LocationManager.shared.currentCourse >= 0 ? LocationManager.shared.currentCourse : mv.camera.heading
                )
                mv.setCamera(cam, animated: true)
            }
        }
        
        /// Xử lý tự động zoom theo tốc độ di chuyển thực tế (Chống giật/chống zoom liên tục)
        public func handleSmartAutoZoom(location: CLLocation, speedKmh: Double, course: Double) {
            guard let mapView = mapView else { return }
            
            let now = Date()
            
            // 1. Khi vừa mở app: Zoom mượt vào vị trí hiện tại lần đầu tiên
            if !hasInitialZoomed {
                hasInitialZoomed = true
                let initialDist = calculateTargetDistance(speedKmh: speedKmh)
                lastZoomDistance = initialDist
                lastZoomTime = now
                
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: initialDist,
                    pitch: 35,
                    heading: course >= 0 ? course : 0
                )
                mapView.setCamera(camera, animated: true)
                return
            }
            
            // 2. Tự động tính toán cự ly zoom tối ưu theo dải tốc độ:
            // - Dưới 15 km/h: zoom gần (~420m) nhìn rõ từng góc cua, hẻm, ngã tư
            // - 15 - 45 km/h: zoom vừa (~650m) lưu thông an toàn trong phố
            // - Trên 45 km/h: zoom xa (~950m) bao quát đại lộ, quốc lộ
            let targetDist = calculateTargetDistance(speedKmh: speedKmh)
            
            // CHỐNG ZOOM LIÊN TỤC:
            // Chỉ đổi mức zoom khi dải tốc độ đổi rõ rệt (delta >= 150m) VÀ cách lần zoom trước >= 6 giây
            let delta = abs(targetDist - lastZoomDistance)
            let timeSinceLast = now.timeIntervalSince(lastZoomTime)
            
            if delta >= 150.0 && timeSinceLast >= 6.0 {
                lastZoomDistance = targetDist
                lastZoomTime = now
                
                let heading = course >= 0 ? course : mapView.camera.heading
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: targetDist,
                    pitch: 35,
                    heading: heading
                )
                
                UIView.animate(withDuration: 1.5) {
                    mapView.setCamera(camera, animated: true)
                }
            } else if timeSinceLast >= 2.0 {
                // Giữ nguyên độ cao zoom hiện tại, chỉ lướt camera theo vị trí xe
                let currentDistance = mapView.camera.centerCoordinateDistance
                let heading = course >= 0 ? course : mapView.camera.heading
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: currentDistance > 100 ? currentDistance : targetDist,
                    pitch: 35,
                    heading: heading
                )
                mapView.setCamera(camera, animated: true)
            }
        }
        
        private func calculateTargetDistance(speedKmh: Double) -> Double {
            if speedKmh < 15.0 {
                return 420.0
            } else if speedKmh < 45.0 {
                return 650.0
            } else {
                return 950.0
            }
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = 0.95
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = 7.0
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        /// Tùy biến hiển thị biểu tượng chiếc xe thay thế chấm xanh mặc định
        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 1. Biểu tượng chiếc xe cho vị trí người dùng
            if annotation is MKUserLocation {
                let userIdentifier = "UserVehicleMarker"
                var vehicleView = mapView.dequeueReusableAnnotationView(withIdentifier: userIdentifier) as? VehicleAnnotationView
                if vehicleView == nil {
                    vehicleView = VehicleAnnotationView(annotation: annotation, reuseIdentifier: userIdentifier)
                } else {
                    vehicleView?.annotation = annotation
                }
                
                let course = LocationManager.shared.currentCourse
                if course >= 0 {
                    vehicleView?.updateHeading(degrees: course)
                }
                return vehicleView
            }
            
            // 2. Điểm đánh dấu khúc rẽ của lộ trình dẫn đường
            let identifier = "ManeuverNode"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
            } else {
                view?.annotation = annotation
            }
            
            view?.markerTintColor = UIColor.systemOrange
            view?.glyphImage = UIImage(systemName: "arrow.turn.up.right")
            return view
        }
        
        func updateRoute(route: NavigationRoute, on mapView: MKMapView) {
            clearRoute(on: mapView)
            
            let coordinates = route.points.map { $0.clLocationCoordinate2D }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            self.currentPolyline = polyline
            mapView.addOverlay(polyline, level: .aboveRoads)
            
            for maneuver in route.maneuvers {
                let annotation = MKPointAnnotation()
                annotation.coordinate = maneuver.point.clLocationCoordinate2D
                annotation.title = maneuver.instruction
                annotation.subtitle = "Góc rẽ: \(Int(maneuver.turnAngleDegrees))°"
                self.maneuverAnnotations.append(annotation)
                mapView.addAnnotation(annotation)
            }
        }
        
        func clearRoute(on mapView: MKMapView) {
            if let pl = currentPolyline {
                mapView.removeOverlay(pl)
                self.currentPolyline = nil
            }
            if !maneuverAnnotations.isEmpty {
                mapView.removeAnnotations(maneuverAnnotations)
                maneuverAnnotations.removeAll()
            }
        }
    }
}
