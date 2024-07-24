import SwiftUI
import MapKit
import PlaygroundSupport

enum TransportType: String, CaseIterable, Identifiable {
    case driving
    case walking
    case biking

    var id: String { self.rawValue }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .driving:
            return .automobile
        case .walking:
            return .walking
        case .biking:
            return .automobile // Use automobile for biking calculation and adjust time later (MKDirectionsTransportType doesn't support Biking, so we'll have to do it manually)
        }
    }
}

struct ContentView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @State private var sourceLatitude: String = ""
    @State private var sourceLongitude: String = ""
    @State private var destinationLatitude: String = ""
    @State private var destinationLongitude: String = ""
    @State private var selectedTransportType: TransportType = .driving

    @State private var showAlert = false
    @State private var distance: String = ""
    @State private var travelTime: String = ""

    var body: some View {
        VStack {
            HStack {
                VStack {
                    TextField("Source Latitude", text: $sourceLatitude)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Source Longitude", text: $sourceLongitude)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                VStack {
                    TextField("Destination Latitude", text: $destinationLatitude)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Destination Longitude", text: $destinationLongitude)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding()

            Picker("Transport Type", selection: $selectedTransportType) {
                ForEach(TransportType.allCases) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            Button(action: {
                if let srcLat = Double(sourceLatitude),
                   let srcLong = Double(sourceLongitude),
                   let destLat = Double(destinationLatitude),
                   let destLong = Double(destinationLongitude) {
                    let sourceCoordinate = CLLocationCoordinate2D(latitude: srcLat, longitude: srcLong)
                    let destinationCoordinate = CLLocationCoordinate2D(latitude: destLat, longitude: destLong)
                    region = MKCoordinateRegion(
                        center: sourceCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
                    )
                    NotificationCenter.default.post(name: .drawRoute, object: (sourceCoordinate, destinationCoordinate, selectedTransportType.mkTransportType, selectedTransportType))
                } else {
                    showAlert = true
                }
            }) {
                Text("Draw Route")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Invalid Input"), message: Text("Please enter valid coordinates."), dismissButton: .default(Text("OK")))
            }
            .padding()

            Text("Distance: \(distance)")
            Text("Estimated Travel Time: \(travelTime)")

            MapView(region: $region, distance: $distance, travelTime: $travelTime)
                .edgesIgnoringSafeArea(.all)
                .frame(width: 500, height: 500)  // Adjust size as needed
        }
    }
}

struct MapView: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var distance: String
    @Binding var travelTime: String

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(context.coordinator.handleDrawRoute(notification:)), name: .drawRoute, object: nil)
        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        nsView.setRegion(region, animated: true)
    }

    func makeCoordinator() -> MapViewCoordinator {
        return MapViewCoordinator(distance: $distance, travelTime: $travelTime)
    }
}

class MapViewCoordinator: NSObject, MKMapViewDelegate {
    var mapView: MKMapView?
    @Binding var distance: String
    @Binding var travelTime: String

    init(distance: Binding<String>, travelTime: Binding<String>) {
        _distance = distance
        _travelTime = travelTime
    }

    @objc func handleDrawRoute(notification: Notification) {
        guard let userInfo = notification.object as? (CLLocationCoordinate2D, CLLocationCoordinate2D, MKDirectionsTransportType, TransportType) else { return }
        if let mapView = mapView {
            drawRoute(on: mapView, from: userInfo.0, to: userInfo.1, transportType: userInfo.2, originalTransportType: userInfo.3)
        } else {
            print("error, mapView is nil!")
        }
    }

    func drawRoute(on mapView: MKMapView, from sourceCoordinate: CLLocationCoordinate2D, to destinationCoordinate: CLLocationCoordinate2D, transportType: MKDirectionsTransportType, originalTransportType: TransportType) {
        mapView.removeOverlays(mapView.overlays)
        
        let sourcePlacemark = MKPlacemark(coordinate: sourceCoordinate)
        let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)

        let sourceMapItem = MKMapItem(placemark: sourcePlacemark)
        let destinationMapItem = MKMapItem(placemark: destinationPlacemark)

        let request = MKDirections.Request()
        request.source = sourceMapItem
        request.destination = destinationMapItem
        request.transportType = transportType

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let response = response else {
                if let error = error {
                    print("Error calculating directions: \(error.localizedDescription)")
                }
                return
            }

            for route in response.routes {
                mapView.addOverlay(route.polyline)
                mapView.setVisibleMapRect(route.polyline.boundingMapRect, animated: true)
                
                let distanceInMeters = route.distance
                let distanceInMiles = distanceInMeters * 0.000621371
                let distanceInKilometers = distanceInMeters / 1000
                
                // Update distance and travel time
                DispatchQueue.main.async {
                    self.distance = String(format: "%.2f miles (%.2f km)", distanceInMiles, distanceInKilometers)
                    
                    var travelTimeInSeconds = route.expectedTravelTime
                    if originalTransportType == .biking {
                        travelTimeInSeconds *= 4 // Assume biking takes roughly four times as long as driving
                    }
                    self.travelTime = String(format: "%.2f minutes", travelTimeInSeconds / 60)
                }
            }
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .yellow
            renderer.lineWidth = 3
            return renderer
        }
        return MKOverlayRenderer()
    }
}

extension Notification.Name {
    static let drawRoute = Notification.Name("drawRoute")
}

PlaygroundPage.current.setLiveView(ContentView())
