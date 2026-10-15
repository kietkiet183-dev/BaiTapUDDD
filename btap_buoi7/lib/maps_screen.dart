import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final List<Marker> _markers = [];
  List<LatLng> _routePoints = [];
  LatLng? _currentPosition;
  
  // Điểm đích mẫu (Ví dụ: Trung tâm TP.HCM)
  final LatLng _destination = const LatLng(10.7769, 106.7009);

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // Lấy vị trí hiện tại của người dùng
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng bật dịch vụ vị trí!')),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _updateMarkers();
    });

    // Di chuyển camera đến vị trí hiện tại
    _mapController.move(_currentPosition!, 14.0);

    // Tự động gọi tìm đường đến điểm đích
    _getDirections();
  }

  // Cập nhật các Marker (Vị trí hiện tại và Đích đến)
  void _updateMarkers() {
    _markers.clear();
    if (_currentPosition != null) {
      _markers.add(
        Marker(
          point: _currentPosition!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.blue, size: 35),
        ),
      );
    }
    _markers.add(
      Marker(
        point: _destination,
        width: 40,
        height: 40,
        child: const Icon(Icons.flag, color: Colors.red, size: 35),
      ),
    );
  }

  // Tìm đường đi miễn phí sử dụng OSRM API (Thay cho Google Directions API)
  Future<void> _getDirections() async {
    if (_currentPosition == null) return;

    // URL OSRM công khai miễn phí (Lưu ý: OSRM nhận định dạng kinh độ,vĩ độ - lng,lat)
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${_currentPosition!.longitude},${_currentPosition!.latitude};'
      '${_destination.longitude},${_destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'];
        if (routes != null && routes.isNotEmpty) {
          final coords = routes[0]['geometry']['coordinates'] as List;
          setState(() {
            // Chuyển đổi tọa độ GeoJSON [lng, lat] thành LatLng(lat, lng) của flutter_map
            _routePoints = coords.map((coord) {
              return LatLng(coord[1], coord[0]);
            }).toList();
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không tìm thấy tuyến đường nào!')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi gọi API tìm đường: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Navigator (OSM)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              if (_currentPosition != null) {
                _mapController.move(_currentPosition!, 14.0);
              }
            },
          ),
        ],
      ),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition!,
                initialZoom: 14.0,
              ),
              children: [
                // Lớp hiển thị bản đồ OSM
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app',
                ),
                // Lớp vẽ đường đi (Polyline)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
                // Lớp hiển thị các Marker
                MarkerLayer(
                  markers: _markers,
                ),
              ],
            ),
    );
  }
}