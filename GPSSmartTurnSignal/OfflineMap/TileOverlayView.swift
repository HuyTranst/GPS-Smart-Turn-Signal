import SwiftUI
import MapKit

/// Điểm đánh dấu Camera giao thông trên bản đồ
public class TrafficCameraAnnotation: MKPointAnnotation {
    public var camera: TrafficCamera
    
    public init(camera: TrafficCamera) {
        self.camera = camera
        super.init()
        self.coordinate = camera.coordinate
        self.title = camera.title
        if let speed = camera.speedLimitKmh {
            self.subtitle = "Giới hạn: \(speed) km/h • \(camera.sourceType.rawValue)"
        } else {
            self.subtitle = camera.sourceType.rawValue
        }
    }
}

/// Bộ tạo hình ảnh biểu tượng phương tiện (xe ô tô / xe máy thể thao nhìn từ trên xuống)
public struct VehicleIconGenerator {
    public static func createSportVehicleIcon() -> UIImage {
        let size = CGSize(width: 48, height: 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { ctx in
            let cg = ctx.cgContext
            
            // 1. Luồng đèn pha chiếu sáng phía trước (Headlight beam)
            let beamPath = CGMutablePath()
            beamPath.move(to: CGPoint(x: 24, y: 13))
            beamPath.addLine(to: CGPoint(x: 10, y: 2))
            beamPath.addLine(to: CGPoint(x: 38, y: 2))
            beamPath.closeSubpath()
            
            cg.addPath(beamPath)
            cg.setFillColor(UIColor.systemYellow.withAlphaComponent(0.38).cgColor)
            cg.fillPath()
            
            // 2. Bóng đổ xe (Drop shadow)
            let shadowRect = CGRect(x: 15, y: 10, width: 18, height: 30)
            let shadowPath = UIBezierPath(roundedRect: shadowRect, cornerRadius: 8)
            cg.addPath(shadowPath.cgPath)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.40).cgColor)
            cg.fillPath()
            
            // 3. Thân xe thể thao (Chassis) - Màu Electric Cyan công nghệ cao
            let bodyRect = CGRect(x: 15, y: 9, width: 18, height: 28)
            let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: 7.5)
            cg.addPath(bodyPath.cgPath)
            cg.setFillColor(UIColor(red: 0.05, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
            cg.fillPath()
            
            // Viền kim loại sắc sảo
            cg.addPath(bodyPath.cgPath)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            cg.setLineWidth(1.8)
            cg.strokePath()
            
            // 4. Kính chắn gió trước (Windshield)
            let frontGlassRect = CGRect(x: 18, y: 15, width: 12, height: 5.5)
            let frontGlassPath = UIBezierPath(roundedRect: frontGlassRect, cornerRadius: 2)
            cg.addPath(frontGlassPath.cgPath)
            cg.setFillColor(UIColor(white: 0.15, alpha: 0.95).cgColor)
            cg.fillPath()
            
            // 5. Nóc xe & kính sau
            let roofRect = CGRect(x: 18.5, y: 21, width: 11, height: 6.5)
            let roofPath = UIBezierPath(roundedRect: roofRect, cornerRadius: 1.5)
            cg.addPath(roofPath.cgPath)
            cg.setFillColor(UIColor(red: 0.02, green: 0.45, blue: 0.85, alpha: 1.0).cgColor)
            cg.fillPath()
            
            let rearGlassRect = CGRect(x: 18.5, y: 28, width: 11, height: 3.5)
            let rearGlassPath = UIBezierPath(roundedRect: rearGlassRect, cornerRadius: 1)
            cg.addPath(rearGlassPath.cgPath)
            cg.setFillColor(UIColor(white: 0.2, alpha: 0.95).cgColor)
            cg.fillPath()
            
            // 6. Cặp đèn pha trước (Trắng rực)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: 16.5, y: 9, width: 3.5, height: 2.2))
            cg.fillEllipse(in: CGRect(x: 28, y: 9, width: 3.5, height: 2.2))
            
            // 7. Cặp đèn hậu đỏ sau xe
            cg.setFillColor(UIColor.systemRed.cgColor)
            cg.fillEllipse(in: CGRect(x: 16.5, y: 35, width: 3.5, height: 2.2))
            cg.fillEllipse(in: CGRect(x: 28, y: 35, width: 3.5, height: 2.2))
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
        frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        centerOffset = CGPoint(x: 0, y: 0)
        canShowCallout = false
        displayPriority = .required
        zPriority = .max
        
        // Vòng hào quang định vị bên dưới xe
        pulseRingView.frame = CGRect(x: 6, y: 6, width: 42, height: 42)
        pulseRingView.layer.cornerRadius = 21
        pulseRingView.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.20)
        pulseRingView.layer.borderColor = UIColor.systemCyan.withAlphaComponent(0.60).cgColor
        pulseRingView.layer.borderWidth = 1.4
        addSubview(pulseRingView)
        
        // Hình ảnh chiếc xe tự xoay
        vehicleImageView.frame = CGRect(x: 3, y: 3, width: 48, height: 48)
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

/// MKTileOverlay tùy chỉnh: Khắc phục triệt để lỗi màn hình đen khi xoay xe hoặc mạng tải chậm
public class OfflineMKTileOverlay: MKTileOverlay {
    private static let transparentPixelPNG: Data = {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        return Data(base64Encoded: base64) ?? Data()
    }()
    
    private let tileSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "OSMTileCache"
        )
        config.timeoutIntervalForRequest = 3.0
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
    
    public override init(urlTemplate URLTemplate: String? = "https://tile.openstreetmap.org/{z}/{x}/{y}.png") {
        super.init(urlTemplate: URLTemplate)
        self.canReplaceMapContent = false
    }
    
    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let subdomains = ["a", "b", "c"]
        let index = abs(path.x + path.y) % subdomains.count
        let host = subdomains[index]
        return URL(string: "https://\(host).tile.openstreetmap.org/\(path.z)/\(path.x)/\(path.y).png")!
    }
    
    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        if let offlineData = OfflineMapTileManager.shared.getOfflineTileData(z: path.z, x: path.x, y: path.y) {
            result(offlineData, nil)
            return
        }
        
        let osmURL = self.url(forTilePath: path)
        var request = URLRequest(url: osmURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 3.0)
        request.setValue("GPS-Smart-Turn-Signal-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        tileSession.dataTask(with: request) { data, response, error in
            if let d = data, let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                let localURL = OfflineMapTileManager.shared.localTileURL(z: path.z, x: path.x, y: path.y)
                let folder = localURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: folder.path) {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                try? d.write(to: localURL)
                result(d, nil)
            } else {
                result(Self.transparentPixelPNG, nil)
            }
        }.resume()
    }
}

/// UIViewRepresentable bọc MKMapView với biểu tượng xe, camera giao thông và đồng bộ tông màu sáng
public struct OfflineMapView: UIViewRepresentable {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var navigationEngine = NavigationEngine.shared
    @ObservedObject var cameraManager = TrafficCameraManager.shared
    
    public init() {}
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = false
        
        mapView.overrideUserInterfaceStyle = .light
        
        let tileOverlay = OfflineMKTileOverlay()
        mapView.addOverlay(tileOverlay, level: .aboveRoads)
        
        context.coordinator.mapView = mapView
        return mapView
    }
    
    public func updateUIView(_ mapView: MKMapView, context: Context) {
        if let route = navigationEngine.activeRoute {
            context.coordinator.updateRoute(route: route, on: mapView)
        } else {
            context.coordinator.clearRoute(on: mapView)
        }
        
        // Cập nhật danh sách điểm đánh dấu Camera giao thông
        context.coordinator.updateCameras(cameras: cameraManager.allCameras, on: mapView)
        
        // Cập nhật hướng xe xoay mượt mà
        if let userView = mapView.view(for: mapView.userLocation) as? VehicleAnnotationView {
            let course = locationManager.currentCourse
            if course >= 0 {
                userView.updateHeading(degrees: course)
            }
        }
        
        // Tự động điều chỉnh góc zoom phẳng 2D
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
        private var cameraAnnotations: [TrafficCameraAnnotation] = []
        
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
                    pitch: 0,
                    heading: LocationManager.shared.currentCourse >= 0 ? LocationManager.shared.currentCourse : mv.camera.heading
                )
                mv.setCamera(cam, animated: true)
            }
        }
        
        public func handleSmartAutoZoom(location: CLLocation, speedKmh: Double, course: Double) {
            guard let mapView = mapView else { return }
            
            let now = Date()
            
            if !hasInitialZoomed {
                hasInitialZoomed = true
                let initialDist = calculateTargetDistance(speedKmh: speedKmh)
                lastZoomDistance = initialDist
                lastZoomTime = now
                
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: initialDist,
                    pitch: 0,
                    heading: course >= 0 ? course : 0
                )
                mapView.setCamera(camera, animated: true)
                return
            }
            
            let targetDist = calculateTargetDistance(speedKmh: speedKmh)
            let delta = abs(targetDist - lastZoomDistance)
            let timeSinceLast = now.timeIntervalSince(lastZoomTime)
            
            if delta >= 180.0 && timeSinceLast >= 6.0 {
                lastZoomDistance = targetDist
                lastZoomTime = now
                
                let heading = course >= 0 ? course : mapView.camera.heading
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: targetDist,
                    pitch: 0,
                    heading: heading
                )
                
                UIView.animate(withDuration: 1.5) {
                    mapView.setCamera(camera, animated: true)
                }
            } else if timeSinceLast >= 1.5 {
                let currentDistance = mapView.camera.centerCoordinateDistance
                let effectiveDistance = currentDistance > 200 ? currentDistance : targetDist
                let heading = course >= 0 ? course : mapView.camera.heading
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: effectiveDistance,
                    pitch: 0,
                    heading: heading
                )
                mapView.setCamera(camera, animated: true)
            }
        }
        
        private func calculateTargetDistance(speedKmh: Double) -> Double {
            if speedKmh < 15.0 {
                return 680.0
            } else if speedKmh < 45.0 {
                return 920.0
            } else {
                return 1350.0
            }
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = 0.96
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
        
        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 1. Biểu tượng chiếc xe cho người dùng
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
            
            // 2. Biểu tượng Camera giao thông (Màu đỏ nổi bật)
            if let camAnnotation = annotation as? TrafficCameraAnnotation {
                let identifier = "TrafficCameraMarker"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = true
                } else {
                    view?.annotation = annotation
                }
                view?.markerTintColor = UIColor.systemRed
                view?.glyphImage = UIImage(systemName: "camera.fill")
                return view
            }
            
            // 3. Điểm đánh dấu nút rẽ lộ trình
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
        
        /// Cập nhật các điểm Camera trên bản đồ
        func updateCameras(cameras: [TrafficCamera], on mapView: MKMapView) {
            let existingIds = Set(cameraAnnotations.map { $0.camera.id })
            let newIds = Set(cameras.map { $0.id })
            if existingIds == newIds { return }
            
            mapView.removeAnnotations(cameraAnnotations)
            cameraAnnotations.removeAll()
            
            for cam in cameras {
                let ann = TrafficCameraAnnotation(camera: cam)
                cameraAnnotations.append(ann)
                mapView.addAnnotation(ann)
            }
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
