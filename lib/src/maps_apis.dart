import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Proxy for web: custom proxy (Firebase/Vercel) with fallback to public CORS proxy.
Future<http.Response> _fetch(String url, {String? postBody, String? apiKey}) async {
  final useCustomProxy = kIsWeb && kFirebaseProxyUrl.isNotEmpty;

  if (useCustomProxy) {
    try {
      final proxy = Uri.parse(kFirebaseProxyUrl);
      if (postBody != null) {
        final body = <String, dynamic>{'url': url, 'body': postBody};
        if (apiKey != null) body['apiKey'] = apiKey;
        final r = await http
            .post(proxy, body: jsonEncode(body), headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) return r;
      } else {
        final r = await http
            .get(Uri.parse('$kFirebaseProxyUrl?url=${Uri.encodeComponent(url)}'))
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) return r;
      }
    } catch (_) {}
  }

  final uri = kIsWeb
      ? Uri.parse('https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}')
      : Uri.parse(url);
  if (postBody != null) {
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null) headers['X-Goog-Api-Key'] = apiKey;
    return http.post(uri, body: postBody, headers: headers);
  }
  return http.get(uri);
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

/// Nearby parking place from Places API.
class ParkingPlace {
  const ParkingPlace({
    required this.name,
    required this.address,
    required this.latLng,
  });
  final String name;
  final String address;
  final LatLng latLng;
}

/// Pittsburgh center - use as default when user location is outside US or unavailable.
const LatLng _pittsburghCenter = LatLng(40.4406, -79.9959);

/// Known Pittsburgh address fallbacks (CORS proxy can return wrong country).
const LatLng _5000ForbesPittsburgh = LatLng(40.4434, -79.9429);
const LatLng _traderJoesPennAve = LatLng(40.4617, -79.9233);

/// Returns hardcoded coords for known Pittsburgh addresses when geocoding is unreliable (e.g. CORS proxy).
String? pittsburghAddressFallback(String address) {
  final n = address.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  final hasPgh = n.contains('pittsburgh') || n.contains('pa') || n.contains('usa');
  if ((n.contains('5000') && n.contains('forbes')) && (hasPgh || n.length < 50)) {
    return '${_5000ForbesPittsburgh.latitude},${_5000ForbesPittsburgh.longitude}';
  }
  if ((n.contains('trader joe') || n.contains('trader joe\'s')) && n.contains('penn') && (hasPgh || n.length < 50)) {
    return '${_traderJoesPennAve.latitude},${_traderJoesPennAve.longitude}';
  }
  return null;
}

/// True if coordinates are within continental US (avoid wrong-country results e.g. Turkey).
bool isInUS(LatLng p) =>
    p.latitude >= 24 && p.latitude <= 50 && p.longitude >= -125 && p.longitude <= -65;

/// Fetches autocomplete suggestions, restricted to US to avoid wrong-country results (e.g. Turkey).
Future<List<AutocompletePrediction>> fetchAutocomplete(
  String input, {
  LatLng? locationBias,
}) async {
  if (kMapsApiKey.isEmpty || input.trim().length < 2) return [];
  final trimmed = input.trim();
  // Use US location for bias - never pass non-US coords (e.g. Turkey)
  final center = (locationBias != null && isInUS(locationBias))
      ? locationBias
      : _pittsburghCenter;

  // Legacy Places API first (GET, works reliably through CORS proxy)
  try {
    var url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(trimmed)}'
        '&key=$kMapsApiKey'
        '&types=geocode|establishment'
        '&components=country:us'
        '&location=${center.latitude},${center.longitude}&radius=50000';
    final response = await _fetch(url);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') return [];
    final predictions = data['predictions'] as List<dynamic>? ?? [];
    final legacyResults = predictions.map((p) {
      final map = p as Map<String, dynamic>;
      return AutocompletePrediction(
        description: map['description'] as String? ?? '',
        placeId: map['place_id'] as String? ?? '',
      );
    }).toList();
    if (legacyResults.isNotEmpty) return legacyResults;
  } catch (_) {}

  // Places API (New) fallback
  try {
    const placesUrl = 'https://places.googleapis.com/v1/places:autocomplete';
    final bodyMap = <String, dynamic>{
      'input': trimmed,
      'includedRegionCodes': ['us'],
      'locationBias': {
        'circle': {
          'center': {'latitude': center.latitude, 'longitude': center.longitude},
          'radius': 50000.0,
        },
      },
    };
    final response = await _fetch(placesUrl, postBody: jsonEncode(bodyMap), apiKey: kMapsApiKey);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = data['suggestions'] as List<dynamic>? ?? [];
      for (final s in suggestions) {
        final map = s as Map<String, dynamic>;
        final placePred = map['placePrediction'] as Map<String, dynamic>?;
        if (placePred == null) continue;
        final text = placePred['text'] as Map<String, dynamic>?;
        final desc = text?['text'] as String? ?? '';
        final placeId = placePred['placeId'] as String? ?? '';
        if (desc.isNotEmpty && placeId.isNotEmpty) {
          return [AutocompletePrediction(description: desc, placeId: placeId)];
        }
      }
    }
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
    final response = await _fetch(url);
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

/// Geocode an address to "lat,lng".
/// Biases toward US to avoid wrong country results (e.g. "5000 Forbes Ave" -> Pittsburgh, not Turkey).
Future<String?> geocodeAddress(String address) async {
  if (kMapsApiKey.isEmpty || address.trim().isEmpty) return null;
  if (RegExp(r'^-?\d+\.\d+,-?\d+\.\d+$').hasMatch(address.trim())) return address.trim();
  final trimmed = address.trim();
  final looksNonUS = RegExp(r'\b(Turkey|UK|London|Paris|Berlin|Tokyo|Canada|Mexico)\b', caseSensitive: false).hasMatch(trimmed);
  final regionParam = looksNonUS ? '' : '&region=us&components=country:US';
  final addr = (!looksNonUS && !RegExp(r',\s*(USA|US|United States)\s*$', caseSensitive: false).hasMatch(trimmed))
      ? '$trimmed, United States'
      : trimmed;
  final url = 'https://maps.googleapis.com/maps/api/geocode/json'
      '?address=${Uri.encodeComponent(addr)}'
      '$regionParam'
      '&key=$kMapsApiKey';
  try {
    final response = await _fetch(url);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    final loc = (results.first as Map<String, dynamic>)['geometry']?['location'] as Map<String, dynamic>?;
    if (loc == null) return null;
    final lat = (loc['lat'] as num).toDouble();
    final lng = (loc['lng'] as num).toDouble();
    final p = LatLng(lat, lng);
    if (!isInUS(p) && !looksNonUS) return null;
    return '$lat,$lng';
  } catch (_) {
    return null;
  }
}

/// Fetches nearby parking places using Places API Nearby Search.
Future<List<ParkingPlace>> fetchNearbyParking(LatLng location, {int radius = 800}) async {
  if (kMapsApiKey.isEmpty) return [];
  final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=${location.latitude},${location.longitude}'
      '&radius=$radius'
      '&type=parking'
      '&key=$kMapsApiKey';
  try {
    final response = await _fetch(url);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') return [];
    final results = data['results'] as List<dynamic>? ?? [];
    final list = <ParkingPlace>[];
    for (final r in results) {
      final map = r as Map<String, dynamic>;
      final geometry = map['geometry'] as Map<String, dynamic>?;
      final loc = geometry?['location'] as Map<String, dynamic>?;
      if (loc == null) continue;
      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();
      if (!isInUS(LatLng(lat, lng))) continue;
      final name = map['name'] as String? ?? 'Parking';
      final address = map['vicinity'] as String? ?? '';
      list.add(ParkingPlace(name: name, address: address, latLng: LatLng(lat, lng)));
    }
    return list;
  } catch (_) {
    return [];
  }
}

