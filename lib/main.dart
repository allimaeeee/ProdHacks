import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'src/app_config.dart';
import 'src/maps_apis.dart';

/// Bottom sheet showing nearby parking places.
Future<void> _showParkingSheet(
  BuildContext context, {
  required LatLng location,
  required String destinationName,
  void Function(ParkingPlace)? onSelectParking,
}) async {
  final parking = await fetchNearbyParking(location, radius: 800);
  if (!context.mounted) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Parking near $destinationName',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: parking.isEmpty
                  ? Center(
                      child: Text(
                        'No parking found nearby. Enable Places API in Google Cloud.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: parking.length,
                      itemBuilder: (_, i) {
                        final p = parking[i];
                        return ListTile(
                          leading: const Icon(Icons.local_parking),
                          title: Text(p.name),
                          subtitle: p.address.isNotEmpty ? Text(p.address) : null,
                          onTap: () {
                            onSelectParking?.call(p);
                            if (onSelectParking != null) Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'InstaPark',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4285F4)),
      ),
      home: const MapPage(title: 'InstaPark'),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.title});

  final String title;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  final Set<Marker> _markers = {};
  bool _searching = false;
  List<AutocompletePrediction> _suggestions = [];
  bool _showSuggestions = false;
  bool _suggestionsLoading = false;
  Timer? _debounce;
  LatLng? _userLocation;
  /// When set, the app bar shows a list icon to reopen the parking sheet for this destination.
  LatLng? _parkingListLocation;
  String? _parkingListDestinationName;

  // Fallback when location isn't available yet or is denied
  static const CameraPosition _fallbackPosition = CameraPosition(
    target: LatLng(37.7749, -122.4194),
    zoom: 12,
  );

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
        _suggestionsLoading = false;
      });
      return;
    }
    setState(() {
      _showSuggestions = true;
      _suggestionsLoading = true;
      _suggestions = [];
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final list = await fetchAutocomplete(value, locationBias: _userLocation);
      if (!mounted) return;
      setState(() {
        _suggestions = list;
        _suggestionsLoading = false;
      });
    });
  }

  Future<void> _selectPlace(AutocompletePrediction prediction) async {
    setState(() {
      _searchController.text = prediction.description;
      _showSuggestions = false;
      _suggestions = [];
    });
    var details = await fetchPlaceDetails(prediction.placeId);
    if (details == null || !isInUS(details.latLng)) {
      var coords = pittsburghAddressFallback(prediction.description) ?? await geocodeAddress(prediction.description);
      if (coords == null) coords = pittsburghAddressFallback('${prediction.description}, Pittsburgh, PA, USA') ?? await geocodeAddress('${prediction.description}, USA');
      if (coords != null) {
        final parts = coords.split(',');
        if (parts.length == 2) {
          details = PlaceDetails(
            latLng: LatLng(double.parse(parts[0]), double.parse(parts[1])),
            formattedAddress: prediction.description,
          );
        }
      }
    }
    if (details == null || !mounted) return;
    final d = details!;
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: MarkerId(prediction.placeId),
          position: d.latLng,
          infoWindow: InfoWindow(title: d.formattedAddress),
        ),
      );
    });
    final controller = _mapController;
    if (controller != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(d.latLng, 14),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Found: ${prediction.description}'),
        action: SnackBarAction(
          label: 'Parking nearby',
          onPressed: () => _openParkingSheet(d.latLng, prediction.description),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    if (kMapsApiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Search needs MAPS_API_KEY. Run: dart run tool/run_web_with_key.dart',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    setState(() => _searching = true);
    try {
      var coords = pittsburghAddressFallback(query) ?? await geocodeAddress(query);
      if (coords == null) coords = pittsburghAddressFallback('$query, Pittsburgh, PA, USA') ?? await geocodeAddress('$query, USA');
      if (coords == null) throw Exception('No results');
      final parts = coords.split(',');
      if (parts.length != 2) throw Exception('Invalid result');
      final placeLatLng = LatLng(double.parse(parts[0]), double.parse(parts[1]));
      if (!isInUS(placeLatLng)) throw Exception('Address resolved outside US. Try adding ", USA"');
      if (!mounted) return;
      setState(() {
        _markers.clear();
        _markers.add(
          Marker(
            markerId: const MarkerId('search'),
            position: placeLatLng,
            infoWindow: InfoWindow(title: query),
          ),
        );
      });
      final controller = _mapController;
      if (controller != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(placeLatLng, 14),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found: $query'),
          action: SnackBarAction(
            label: 'Parking nearby',
            onPressed: () => _openParkingSheet(placeLatLng, query),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openParkingSheet(LatLng location, String destinationName) {
    setState(() {
      _parkingListLocation = location;
      _parkingListDestinationName = destinationName;
    });
    // Open sheet after frame so AppBar rebuilds and list icon is visible when sheet closes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showParkingSheet(
        context,
        location: location,
        destinationName: destinationName,
        onSelectParking: _onSelectParking,
      );
    });
  }

  void _onSelectParking(ParkingPlace p) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value.startsWith('parking_'));
      _markers.add(
        Marker(
          markerId: MarkerId('parking_${p.latLng.latitude}_${p.latLng.longitude}'),
          position: p.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: p.name, snippet: p.address),
        ),
      );
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(p.latLng, 16),
    );
  }

  Future<void> _moveToCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    if (!mounted) return;
    setState(() => _userLocation = LatLng(position.latitude, position.longitude));
    final controller = _mapController;
    if (controller == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        14,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
          widget.title.isEmpty ? 'Parking' : widget.title,
          style: GoogleFonts.alike(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_parkingListLocation != null)
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: 'Parking list',
              color: Theme.of(context).appBarTheme.iconTheme?.color ?? Theme.of(context).colorScheme.onSurface,
              onPressed: () => _showParkingSheet(
                context,
                location: _parkingListLocation!,
                destinationName: _parkingListDestinationName ?? 'Parking',
                onSelectParking: _onSelectParking,
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search bar above the map so it's always visible (not covered by map on web)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search address or place...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: _searching ? null : _searchPlace,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
                onSubmitted: (_) => _searchPlace(),
                textInputAction: TextInputAction.search,
                onTap: () {
                  if (_suggestions.isNotEmpty) setState(() => _showSuggestions = true);
                },
              ),
            ),
          ),
          if (_showSuggestions)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 260),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _suggestionsLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _suggestions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No suggestions. Enable Places API in Google Cloud. If using a proxy, try removing FIREBASE_PROXY_URL from api_keys.env.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _suggestions.length,
                          itemBuilder: (context, i) {
                            final p = _suggestions[i];
                            return ListTile(
                              leading: const Icon(Icons.location_on, size: 20, color: Colors.grey),
                              title: Text(
                                p.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                              onTap: () => _selectPlace(p),
                            );
                          },
                        ),
            ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _fallbackPosition,
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                _moveToCurrentPosition();
              },
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              markers: _markers,
            ),
          ),
        ],
      ),
    );
  }
}
