import SwiftUI
import MapKit

/// MKTileOverlay tùy chỉnh hỗ trợ ưu tiên đọc bản đồ OpenStreetMap từ bộ nhớ Offline
public class OfflineMKTileOverlay: MKTileOverlay {
    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        return URL(string: "https://tile.openstreetmap.org/\(path.z)/\(path.x)/\(path.y).png")!
    }
    
    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        // 1. Ưu tiên đọc dữ liệu tile từ bộ nhớ máy (Hoàn toàn Offline)
        if let offlineData = OfflineMapTileManager.shared.getOfflineTileData(z: path.z, x: path.x, y: path.y) {
            result(offlineData, nil)
            return
        }
        
        // 2. Nếu máy có mạng và chưa tải trước, tải trực tuyến và tự động lưu vào cache
        let osmURL = self.url(forTilePath: path)
        var request = URLRequest(url: osmURL)
        request.setValue("GPS-Smart-Turn-Signal-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let d = data, error == nil {
                // Tự động lưu tile vào bộ nhớ cục bộ
                let localURL = OfflineMapTileManager.shared.localTileURL(z: path.z, x: path.x, y: path.y)
                let folder = localURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: folder.path) {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                try? d.write(to: localURL)
                result(d, nil)
            } else {
                result(nil, error)
            }
        }.resume()
    }
}

/// UIViewRepresentable bọc MKMapView với bản đồ OpenStreetMap Offline và lộ trình dẫn đường
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
        
        // Cài đặt lớp bản đồ OpenStreetMap thay thế lớp nền mặc định
        let tileOverlay = OfflineMKTileOverlay()
        tileOverlay.canReplaceMapContent = true
        mapView.addOverlay(tileOverlay, level: .aboveLabels)
        
        context.coordinator.mapView = mapView
        return mapView
    }
    
    public func updateUIView(_ mapView: MKMapView, context: Context) {
        // Cập nhật tuyến đường khi thay đổi
        if let route = navigationEngine.activeRoute {
            context.coordinator.updateRoute(route: route, on: mapView)
        } else {
            context.coordinator.clearRoute(on: mapView)
        }
        
        // Tự động điều chỉnh góc zoom thông minh theo tốc độ (Không zoom giật liên tục)
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
                    heading: LocationManager.shared.currentCourse
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
            // - Dưới 15 km/h (vào ngã rẽ, dừng đèn đỏ): zoom gần (~420m) nhìn rõ góc đường
            // - 15 - 45 km/h (chạy phố bình thường): zoom vừa (~650m)
            // - Trên 45 km/h (đường thoáng, đại lộ): zoom xa (~950m) bao quát
            let targetDist = calculateTargetDistance(speedKmh: speedKmh)
            
            // CHỐNG ZOOM LIÊN TỤC:
            // Chỉ tự động zoom khi dải tốc độ thay đổi đáng kể (chênh lệch cự ly >= 150m) VÀ cách lần zoom trước tối thiểu 6 giây!
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
                // Giữ nguyên mức zoom hiện tại, chỉ di chuyển tâm xe mượt mà
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
        
        /// Tính toán khoảng cách zoom camera theo tốc độ xe
        private func calculateTargetDistance(speedKmh: Double) -> Double {
            if speedKmh < 15.0 {
                return 420.0 // Zoom sát khi đi chậm, dừng hoặc sắp bẻ lái ngã rẽ
            } else if speedKmh < 45.0 {
                return 650.0 // Zoom vừa khi lưu thông trong phố
            } else {
                return 950.0 // Zoom rộng khi chạy đường trường/đại lộ
            }
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
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
            guard !(annotation is MKUserLocation) else { return nil }
            
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
            
            // Vẽ đường dẫn
            let coordinates = route.points.map { $0.clLocationCoordinate2D }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            self.currentPolyline = polyline
            mapView.addOverlay(polyline, level: .aboveRoads)
            
            // Thêm các điểm nút giao
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
