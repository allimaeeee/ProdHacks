import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Wraps URL with CORS proxy on web to avoid "Failed to fetch" from browser.
Uri _url(String url) {
  if (kIsWeb) {
    return Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(url)}');
  }
  return Uri.parse(url);
}

/// Place Autocomplete prediction.
class AutocompletePrediction {
  const AutocompletePrediction({
    required this.description,
    required this.placeId,
  });
  final String description;
  final String placeId;
}

/// Place details with coordinates.
class PlaceDetails {
  const PlaceDetails({
    required this.latLng,
    required this.formattedAddress,
  });
  final LatLng latLng;
  final String formattedAddress;
}

/// Directions result with route polyline and summary.
class DirectionsResult {
  const DirectionsResult({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.bounds,
  });
  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final LatLngBounds bounds;
}

/// Fetches autocomplete suggestions, optionally biased by location for distance/relevance.
Future<List<AutocompletePrediction>> fetchAutocomplete(
  String input, {
  LatLng? locationBias,
}) async {
  if (kMapsApiKey.isEmpty || input.trim().length < 2) return [];
  final trimmed = input.trim();

  // Places API (New)
  try {
    final url = 'https://places.googleapis.com/v1/places:autocomplete';
    final uri = _url(url);
    final bodyMap = <String, dynamic>{'input': trimmed};
    if (locationBias != null) {
      bodyMap['locationBias'] = {
        'circle': {
          'center': {
            'latitude': locationBias.latitude,
            'longitude': locationBias.longitude,
          },
          'radius': 50000.0, // 50 km
        },
      };
    }
    final body = jsonEncode(bodyMap);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': kMapsApiKey,
      },
      body: body,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = data['suggestions'] as List<dynamic>? ?? [];
      final results = <AutocompletePrediction>[];
      for (final s in suggestions) {
        final map = s as Map<String, dynamic>;
        final placePred = map['placePrediction'] as Map<String, dynamic>?;
        if (placePred == null) continue;
        final text = placePred['text'] as Map<String, dynamic>?;
        final desc = text?['text'] as String? ?? '';
        final placeId = placePred['placeId'] as String? ?? '';
        if (desc.isNotEmpty && placeId.isNotEmpty) {
          results.add(AutocompletePrediction(description: desc, placeId: placeId));
        }
      }
      if (results.isNotEmpty) return results;
    }
  } catch (_) {}

  // Legacy Places API fallback
  try {
    var url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(trimmed)}'
        '&key=$kMapsApiKey'
        '&types=geocode|establishment';
    if (locationBias != null) {
      url += '&location=${locationBias.latitude},${locationBias.longitude}&radius=50000';
    }
    final response = await http.get(_url(url));
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') return [];
    final predictions = data['predictions'] as List<dynamic>? ?? [];
    return predictions.map((p) {
      final map = p as Map<String, dynamic>;
      return AutocompletePrediction(
        description: map['description'] as String? ?? '',
        placeId: map['place_id'] as String? ?? '',
      );
    }).toList();
  } catch (_) {}
  return [];
}

Future<PlaceDetails?> fetchPlaceDetails(String placeId) async {
  if (kMapsApiKey.isEmpty) return null;
  final url = 'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${Uri.encodeComponent(placeId)}'
      '&key=$kMapsApiKey'
      '&fields=geometry,formatted_address';
  try {
    final response = await http.get(_url(url));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final result = data['result'] as Map<String, dynamic>?;
    if (result == null) return null;
    final geometry = result['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    if (location == null) return null;
    final lat = (location['lat'] as num).toDouble();
    final lng = (location['lng'] as num).toDouble();
    return PlaceDetails(
      latLng: LatLng(lat, lng),
      formattedAddress: result['formatted_address'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

/// Geocode an address to "lat,lng" for more accurate directions.
Future<String?> geocodeAddress(String address) async {
  if (kMapsApiKey.isEmpty || address.trim().isEmpty) return null;
  if (RegExp(r'^-?\d+\.\d+,-?\d+\.\d+$').hasMatch(address.trim())) return address.trim();
  final url = 'https://maps.googleapis.com/maps/api/geocode/json'
      '?address=${Uri.encodeComponent(address.trim())}'
      '&key=$kMapsApiKey';
  try {
    final response = await http.get(_url(url));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    final loc = (results.first as Map<String, dynamic>)['geometry']?['location'] as Map<String, dynamic>?;
    if (loc == null) return null;
    final lat = (loc['lat'] as num).toDouble();
    final lng = (loc['lng'] as num).toDouble();
    return '$lat,$lng';
  } catch (_) {
    return null;
  }
}

/// Result: either success with DirectionsResult or error message.
typedef DirectionsResponse = ({DirectionsResult? result, String? error});

Future<DirectionsResponse> fetchDrivingDirections(
  String origin,
  String destination,
) async {
  if (kMapsApiKey.isEmpty) {
    return (result: null, error: 'API key missing. Run: dart run tool/run_web_with_key.dart');
  }
  final url = 'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${Uri.encodeComponent(origin)}'
      '&destination=${Uri.encodeComponent(destination)}'
      '&mode=driving'
      '&key=$kMapsApiKey';
  try {
    final response = await http.get(_url(url));
    if (response.statusCode != 200) {
      return (result: null, error: 'Network error ${response.statusCode}. Check Directions API is enabled.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String? ?? '';
    if (status != 'OK') {
      final msg = data['error_message'] as String? ?? status;
      return (result: null, error: 'Directions: $msg. Enable Directions API in Google Cloud.');
    }
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return (result: null, error: 'No route found. Try different addresses.');
    }
    final route = routes.first as Map<String, dynamic>;
    final overview = route['overview_polyline'] as Map<String, dynamic>?;
    final encoded = overview?['points'] as String?;
    if (encoded == null || encoded.isEmpty) {
      return (result: null, error: 'Route has no polyline data.');
    }
    final points = decodePolyline(encoded);
    if (points.isEmpty) {
      return (result: null, error: 'Could not decode route.');
    }

    final legs = route['legs'] as List<dynamic>?;
    String distanceText = '';
    String durationText = '';
    double swLat = points.first.latitude, swLng = points.first.longitude;
    double neLat = swLat, neLng = swLng;
    for (final p in points) {
      if (p.latitude < swLat) swLat = p.latitude;
      if (p.longitude < swLng) swLng = p.longitude;
      if (p.latitude > neLat) neLat = p.latitude;
      if (p.longitude > neLng) neLng = p.longitude;
    }
    if (legs != null && legs.isNotEmpty) {
      final leg = legs.first as Map<String, dynamic>;
      distanceText = leg['distance']?['text'] as String? ?? '';
      durationText = leg['duration']?['text'] as String? ?? '';
    }

    return (
      result: DirectionsResult(
        points: points,
        distanceText: distanceText,
        durationText: durationText,
        bounds: LatLngBounds(
          southwest: LatLng(swLat, swLng),
          northeast: LatLng(neLat, neLng),
        ),
      ),
      error: null,
    );
  } catch (e) {
    return (result: null, error: 'Request failed: $e');
  }
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0;
  int lat = 0, lng = 0;
  while (index < encoded.length) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) == 1 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) == 1 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
