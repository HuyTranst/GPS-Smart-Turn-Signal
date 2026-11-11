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
        mapView.userTrackingMode = .followWithHeading
        mapView.showsCompass = true
        mapView.showsScale = true
        
        // Cài đặt lớp bản đồ OpenStreetMap thay thế lớp nền mặc định
        let tileOverlay = OfflineMKTileOverlay()
        tileOverlay.canReplaceMapContent = true
        mapView.addOverlay(tileOverlay, level: .aboveLabels)
        
        return mapView
    }
    
    public func updateUIView(_ mapView: MKMapView, context: Context) {
        // Cập nhật tuyến đường khi thay đổi
        if let route = navigationEngine.activeRoute {
            context.coordinator.updateRoute(route: route, on: mapView)
        } else {
            context.coordinator.clearRoute(on: mapView)
        }
        
        // Giữ tâm bản đồ theo vị trí xe khi đang dẫn đường
        if navigationEngine.isNavigating, let loc = locationManager.currentLocation {
            let camera = MKMapCamera(
                lookingAtCenter: loc.coordinate,
                fromDistance: 600, // Zoom sát mặt đất khi lái xe
                pitch: 45, // Góc nghiêng 3D dễ quan sát hướng rẽ
                heading: locationManager.currentCourse
            )
            mapView.setCamera(camera, animated: true)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OfflineMapView
        private var currentPolyline: MKPolyline?
        private var maneuverAnnotations: [MKPointAnnotation] = []
        
        init(_ parent: OfflineMapView) {
            self.parent = parent
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
