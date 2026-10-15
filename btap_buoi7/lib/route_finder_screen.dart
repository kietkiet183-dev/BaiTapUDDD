import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class RouteFinderScreen extends StatefulWidget {
  const RouteFinderScreen({super.key});

  @override
  State<RouteFinderScreen> createState() => _RouteFinderScreenState();
}

class _RouteFinderScreenState extends State<RouteFinderScreen> {
  final MapController _mapController = MapController();
  final List<Marker> _markers = [];
  List<LatLng> _routePoints = [];

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  LatLng? _startLatLng;
  LatLng? _endLatLng;

  // Biến lưu thông tin khoảng cách và thời gian
  String _routeInfo = '';
  
  // Loại phương tiện: 'driving' (ô tô/xe máy), 'foot' (đi bộ), 'bike' (xe đạp)
  String _selectedProfile = 'driving';

  static const LatLng _initialCenter = LatLng(10.7769, 106.7009); // TP.HCM

  @override
  void initState() {
    super.initState();
    _getCurrentLocationForStart();
  }

  // 1. Lấy vị trí hiện tại làm điểm xuất phát
  Future<void> _getCurrentLocationForStart() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _startLatLng = LatLng(position.latitude, position.longitude);
      _startController.text = "${position.latitude}, ${position.longitude}";
      _updateMarkers();
    });

    _mapController.move(_startLatLng!, 14.0);
  }

  // 2. Thêm chức năng: Lấy vị trí hiện tại làm ĐIỂM ĐÍCH
  Future<void> _setCurrentLocationAsEnd() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      _endLatLng = LatLng(position.latitude, position.longitude);
      _endController.text = "${position.latitude}, ${position.longitude}";
      _updateMarkers();
    });
  }

  // Cập nhật các Marker trên bản đồ
  void _updateMarkers() {
    _markers.clear();
    if (_startLatLng != null) {
      _markers.add(
        Marker(
          point: _startLatLng!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.blue, size: 35),
        ),
      );
    }
    if (_endLatLng != null) {
      _markers.add(
        Marker(
          point: _endLatLng!,
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: Colors.red, size: 35),
        ),
      );
    }
  }

  // 3. Chức năng Geocoding miễn phí: Chuyển địa chỉ chữ sang tọa độ dùng Nominatim API
  Future<LatLng?> _geocodeAddress(String address) async {
    if (address.isEmpty) return null;
    
    // Nếu người dùng đã nhập sẵn dạng tọa độ (lat, lng) thì tách trực tiếp
    if (address.contains(',')) {
      try {
        List<String> parts = address.split(',');
        return LatLng(double.parse(parts[0].trim()), double.parse(parts[1].trim()));
      } catch (_) {}
    }

    // Nếu nhập địa chỉ bằng chữ (Ví dụ: "227 Nguyễn Văn Cừ")
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(address)}&format=json&limit=1');
    try {
      final response = await http.get(url, headers: {'User-Agent': 'com.thua.routefinder'});
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          double lat = double.parse(data[0]['lat']);
          double lon = double.parse(data[0]['lon']);
          return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  // 4. Tìm đường đi, tính khoảng cách, thời gian và chọn phương tiện
  Future<void> _findRoute() async {
    if (_startController.text.isEmpty || _endController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đầy đủ điểm xuất phát và đích đến!')),
      );
      return;
    }

    // Chuyển đổi địa chỉ chữ sang LatLng
    _startLatLng = await _geocodeAddress(_startController.text);
    _endLatLng = await _geocodeAddress(_endController.text);

    if (_startLatLng == null || _endLatLng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy tọa độ của địa chỉ đã nhập!')),
        );
      }
      return;
    }

    // Gọi OSRM Routing API theo phương tiện đã chọn ('driving', 'foot', 'bike')
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/$_selectedProfile/'
      '${_startLatLng!.longitude},${_startLatLng!.latitude};'
      '${_endLatLng!.longitude},${_endLatLng!.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'];
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final coords = route['geometry']['coordinates'] as List;
          
          double distanceMeters = route['distance']; // Mét
          double durationSeconds = route['duration']; // Giây

          String distStr = distanceMeters > 1000 
              ? '${(distanceMeters / 1000).toStringAsFixed(1)} km' 
              : '${distanceMeters.toStringAsFixed(0)} m';
              
          String durStr = durationSeconds > 60 
              ? '${(durationSeconds / 60).toStringAsFixed(0)} phút' 
              : '${durationSeconds.toStringAsFixed(0)} giây';

          setState(() {
            _routeInfo = 'Khoảng cách: $distStr - Thời gian: $durStr';
            _routePoints = coords.map((coord) => LatLng(coord[1], coord[0])).toList();
            _updateMarkers();
          });
          _mapController.move(_startLatLng!, 13.0);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không tìm thấy tuyến đường phù hợp!')),
            );
          }
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
      appBar: AppBar(title: const Text('Route Finder - Nâng cao')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // Ô nhập điểm xuất phát (Hỗ trợ cả địa chỉ chữ và tọa độ)
                TextField(
                  controller: _startController,
                  decoration: const InputDecoration(
                    labelText: 'Điểm xuất phát (Địa chỉ hoặc lat, lng)',
                    hintText: 'Ví dụ: 227 Nguyễn Văn Cừ hoặc 10.77, 106.70',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        decoration: const InputDecoration(
                          labelText: 'Điểm đích (Địa chỉ hoặc lat, lng)',
                          hintText: 'Nhập địa chỉ hoặc click bản đồ',
                        ),
                      ),
                    ),
                    // Nút nhanh lấy vị trí hiện tại làm điểm đích (Bài tập 4)
                    IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      tooltip: 'Lấy vị trí hiện tại làm điểm đích',
                      onPressed: _setCurrentLocationAsEnd,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                
                // Chọn phương tiện di chuyển (Bài về nhà)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Phương tiện: '),
                    ChoiceChip(
                      label: const Text('Ô tô / Xe máy'),
                      selected: _selectedProfile == 'driving',
                      onSelected: (selected) => setState(() => _selectedProfile = 'driving'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Đi bộ'),
                      selected: _selectedProfile == 'foot',
                      onSelected: (selected) => setState(() => _selectedProfile = 'foot'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Xe đạp'),
                      selected: _selectedProfile == 'bike',
                      onSelected: (selected) => setState(() => _selectedProfile = 'bike'),
                    ),
                  ],
                ),

                const SizedBox(height: 5),
                ElevatedButton(
                  onPressed: _findRoute,
                  child: const Text('Tìm đường đi'),
                ),
                
                // Hiển thị khoảng cách và thời gian di chuyển
                if (_routeInfo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _routeInfo,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: 12.0,
                // Cho phép click chuột/chạm vào bản đồ để chọn điểm đích (Bài tập 4)
                onTap: (tapPosition, latLng) {
                  setState(() {
                    _endLatLng = latLng;
                    _endController.text = "${latLng.latitude}, ${latLng.longitude}";
                    _updateMarkers();
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.thua.routefinder',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: _markers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}