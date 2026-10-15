import 'package:flutter/material.dart';
import 'route_finder_screen.dart';
void main() {
  runApp(const MapNavigatorApp());
}

class MapNavigatorApp extends StatelessWidget {
  const MapNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Map Navigator OSM',
      home: RouteFinderScreen(),
    );
  }
}