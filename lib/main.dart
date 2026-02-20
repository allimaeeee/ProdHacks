import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'src/app_config.dart';
import 'src/maps_apis.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MapPage(title: 'Park Assist'),
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
  final Set<Polyline> _polylines = {};
  bool _searching = false;
  List<AutocompletePrediction> _suggestions = [];
  bool _showSuggestions = false;
  bool _suggestionsLoading = false;
  Timer? _debounce;
  LatLng? _userLocation;

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

  Future<void> _selectPlace(AutocompletePrediction prediction, {bool useAsDestination = false}) async {
    setState(() {
      _searchController.text = prediction.description;
      _showSuggestions = false;
      _suggestions = [];
    });
    if (useAsDestination) {
      _openDirections(initialDestination: prediction.description);
      return;
    }
    final details = await fetchPlaceDetails(prediction.placeId);
    if (details == null || !mounted) return;
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: MarkerId(prediction.placeId),
          position: details.latLng,
          infoWindow: InfoWindow(title: details.formattedAddress),
        ),
      );
    });
    final controller = _mapController;
    if (controller != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(details.latLng, 14),
      );
    }
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
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(query)}'
        '&key=$kMapsApiKey',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) throw Exception('Geocoding failed');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        throw Exception(data['error_message'] ?? 'No results');
      }
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) throw Exception('No results');
      final first = results.first as Map<String, dynamic>;
      final geometry = first['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) throw Exception('Invalid result');
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final placeId = first['place_id'] as String? ?? 'search';
      final placeLatLng = LatLng(lat, lng);
      if (!mounted) return;
      setState(() {
        _markers.clear();
        _markers.add(
          Marker(
            markerId: MarkerId(placeId),
            position: placeLatLng,
            infoWindow: InfoWindow(
              title: first['formatted_address'] as String? ?? query,
            ),
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
      final formattedAddr = first['formatted_address'] as String? ?? query;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found: $formattedAddr'),
          action: SnackBarAction(
            label: 'Get directions',
            onPressed: () => _openDirections(initialDestination: formattedAddr),
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

  void _openDirections({String? initialDestination}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DirectionsSheet(
        initialDestination: initialDestination,
        locationBias: _userLocation,
        onGetDirections: (String originStr, String destStr) async {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) Navigator.of(ctx).maybePop();
          });
          if (kMapsApiKey.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Directions need MAPS_API_KEY. Run: dart run tool/run_web_with_key.dart'),
              ),
            );
            return;
          }
          setState(() => _searching = true);
          try {
            final response = await fetchDrivingDirections(originStr, destStr);
            if (!mounted) return;
            if (response.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(response.error!), duration: const Duration(seconds: 6)),
              );
              setState(() => _searching = false);
              return;
            }
            final result = response.result!;
            final start = result.points.isNotEmpty ? result.points.first : null;
            final end = result.points.isNotEmpty ? result.points.last : null;
            setState(() {
              _polylines.clear();
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: result.points,
                  color: Colors.blue.shade700,
                  width: 5,
                  geodesic: true,
                ),
              );
              _markers.clear();
              if (start != null) {
                _markers.add(
                  Marker(
                    markerId: const MarkerId('origin'),
                    position: start,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    infoWindow: const InfoWindow(title: 'Start'),
                  ),
                );
              }
              if (end != null) {
                _markers.add(
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: end,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    infoWindow: const InfoWindow(title: 'End'),
                  ),
                );
              }
              _searching = false;
            });
            final controller = _mapController;
            if (controller != null && result.points.isNotEmpty) {
              final b = result.bounds;
              final latSpan = (b.northeast.latitude - b.southwest.latitude).abs();
              final lngSpan = (b.northeast.longitude - b.southwest.longitude).abs();
              final midLat = (b.southwest.latitude + b.northeast.latitude) / 2;
              final midLng = (b.southwest.longitude + b.northeast.longitude) / 2;
              if (latSpan < 0.001 && lngSpan < 0.001) {
                await controller.animateCamera(
                  CameraUpdate.newLatLngZoom(LatLng(midLat, midLng), 14),
                );
              } else if (latSpan > 0.01 || lngSpan > 0.01) {
                await controller.animateCamera(
                  CameraUpdate.newLatLngBounds(result.bounds, 100),
                );
              } else {
                await controller.animateCamera(
                  CameraUpdate.newLatLngZoom(LatLng(midLat, midLng), 12),
                );
              }
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result.durationText} • ${result.distanceText}'),
                duration: const Duration(seconds: 4),
              ),
            );
          } catch (e) {
            if (mounted) {
              setState(() => _searching = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Directions failed: $e')),
              );
            }
          }
        },
      ),
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
        title: Text(widget.title.isEmpty ? 'Parking' : widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_car),
            tooltip: 'Driving directions',
            onPressed: _openDirections,
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
                            'No suggestions. Enable Places API (New) or Places API in Google Cloud.',
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
                              trailing: IconButton(
                                icon: const Icon(Icons.directions),
                                tooltip: 'Use as destination',
                                onPressed: () => _selectPlace(p, useAsDestination: true),
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
              polylines: _polylines,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for From/To with autocomplete and "Get directions" (driving).
class _DirectionsSheet extends StatefulWidget {
  const _DirectionsSheet({
    required this.onGetDirections,
    this.initialDestination,
    this.locationBias,
  });

  final void Function(String originStr, String destStr) onGetDirections;
  final String? initialDestination;
  final LatLng? locationBias;

  @override
  State<_DirectionsSheet> createState() => _DirectionsSheetState();
}

class _DirectionsSheetState extends State<_DirectionsSheet> {
  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController();
    _toController = TextEditingController(text: widget.initialDestination ?? '');
  }
  List<AutocompletePrediction> _fromSuggestions = [];
  List<AutocompletePrediction> _toSuggestions = [];
  bool _useMyLocation = true;
  Timer? _fromDebounce;
  Timer? _toDebounce;

  void _fetchFromSuggestions(String value) {
    _fromDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _fromSuggestions = []);
      return;
    }
    _fromDebounce = Timer(const Duration(milliseconds: 350), () async {
      final list = await fetchAutocomplete(value, locationBias: widget.locationBias);
      if (!mounted) return;
      setState(() => _fromSuggestions = list);
    });
  }

  void _fetchToSuggestions(String value) {
    _toDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _toSuggestions = []);
      return;
    }
    _toDebounce = Timer(const Duration(milliseconds: 350), () async {
      final list = await fetchAutocomplete(value, locationBias: widget.locationBias);
      if (!mounted) return;
      setState(() => _toSuggestions = list);
    });
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    super.dispose();
  }

  Future<void> _submitDirections() async {
    String originStr;
    if (_useMyLocation) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        originStr = '${pos.latitude},${pos.longitude}';
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
        return;
      }
    } else {
      final fromText = _fromController.text.trim();
      if (fromText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a starting point')),
        );
        return;
      }
      final geocoded = await geocodeAddress(fromText);
      originStr = geocoded ?? fromText;
    }

    final toText = _toController.text.trim();
    if (toText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a destination')),
      );
      return;
    }
    final destGeocoded = await geocodeAddress(toText);
    final destStr = destGeocoded ?? toText;
    widget.onGetDirections(originStr, destStr);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(Icons.directions_car, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Driving directions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // From
              Row(
                children: [
                  const Icon(Icons.trip_origin, color: Colors.green, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          value: _useMyLocation,
                          onChanged: (v) => setState(() {
                            _useMyLocation = v ?? true;
                            if (_useMyLocation) _fromController.clear();
                            _fromSuggestions = [];
                          }),
                          title: const Text('My location', style: TextStyle(fontSize: 14)),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                        if (!_useMyLocation)
                          TextField(
                            controller: _fromController,
                            onChanged: _fetchFromSuggestions,
                            onTap: () {},
                            decoration: InputDecoration(
                              hintText: 'Start address',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_useMyLocation && _fromSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 36),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fromSuggestions.length,
                    itemBuilder: (ctx, i) {
                      final p = _fromSuggestions[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on, size: 18),
                        title: Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        onTap: () {
                          _fromController.text = p.description;
                          setState(() => _fromSuggestions = []);
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              // To
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _toController,
                      onChanged: _fetchToSuggestions,
                      onTap: () {},
                      decoration: InputDecoration(
                        hintText: 'Destination address',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_toSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 36),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _toSuggestions.length,
                    itemBuilder: (ctx, i) {
                      final p = _toSuggestions[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on, size: 18),
                        title: Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        onTap: () {
                          _toController.text = p.description;
                          setState(() => _toSuggestions = []);
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitDirections,
                icon: const Icon(Icons.directions),
                label: const Text('Get directions'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
