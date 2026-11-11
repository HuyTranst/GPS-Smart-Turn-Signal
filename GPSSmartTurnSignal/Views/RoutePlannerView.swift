import SwiftUI

/// Màn hình chọn lộ trình và bắt đầu hành trình dẫn đường
public struct RoutePlannerView: View {
    @ObservedObject var navigation = NavigationEngine.shared
    @Environment(\.presentationMode) var presentationMode
    
    private let sampleRoutes: [NavigationRoute] = [
        .sampleHanoiRoute,
        .sampleHcmcRoute
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("CHỌN TUYẾN ĐƯỜNG DẪN ĐƯỜNG")) {
                    ForEach(sampleRoutes) { route in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(route.title)
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.1f km", route.totalDistanceMeters / 1000.0))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                            }
                            
                            Text("\(route.maneuvers.count) ngã rẽ có sẵn trên tuyến")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    navigation.startNavigation(route: route)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Label("Bắt đầu dẫn đường", systemImage: "location.fill")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    navigation.startSimulation(route: route)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Label("Chạy thử mô phỏng", systemImage: "play.circle.fill")
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                
                if navigation.isNavigating {
                    Section {
                        Button(role: .destructive, action: {
                            navigation.stopNavigation()
                        }) {
                            HStack {
                                Spacer()
                                Label("Dừng hành trình hiện tại", systemImage: "stop.circle.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chọn Tuyến Đường")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
