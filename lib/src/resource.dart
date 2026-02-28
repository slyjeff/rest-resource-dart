import 'dart:convert';
import 'package:http/http.dart' as http;

import 'link.dart';
import 'rest_client.dart'; // RestClient, ResourceBase, LinkNotFoundException

/// Abstract base class for all HATEOAS resources.
///
/// Subclasses expose typed computed properties that read from [_data] and
/// define link-navigation methods that call [executeLink].
///
/// ```dart
/// class UserResource extends Resource {
///   UserResource(super.client);
///
///   String get firstName => stringValue('firstName') ?? '';
///   int    get id        => intValue('id') ?? 0;
///
///   Future<UserResource> updateUser({required String firstName}) =>
///       executeLink(UserResource.new, 'updateUser', values: {'firstName': firstName});
/// }
/// ```
abstract class Resource extends ResourceBase {
  final RestClient _client;

  Map<String, dynamic> _data = {};
  Map<String, Link> _links = {};

  /// Cache of deserialized sub-resource lists keyed by JSON field name.
  final Map<String, List<Resource>> _listCache = {};

  /// The raw HTTP response from the most recent request on this resource.
  http.Response? response;

  Resource(RestClient client) : _client = client;

  // ---------------------------------------------------------------------------
  // Hydration
  // ---------------------------------------------------------------------------

  /// Populates this resource from a decoded JSON map.
  ///
  /// Called by [RestClient.buildResource] after a successful response. Extracts
  /// `_links` into typed [Link] objects; everything else goes into [_data].
  void populateFromJson(Map<String, dynamic> json) {
    _links = {};
    _data = {};
    _listCache.clear();

    for (final entry in json.entries) {
      if (entry.key == '_links') {
        final linksJson = entry.value;
        if (linksJson is Map<String, dynamic>) {
          for (final linkEntry in linksJson.entries) {
            if (linkEntry.value is Map<String, dynamic>) {
              _links[linkEntry.key] =
                  Link.fromJson(linkEntry.value as Map<String, dynamic>);
            }
          }
        }
      } else {
        _data[entry.key] = entry.value;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Raw value lookup
  // ---------------------------------------------------------------------------

  /// Case-insensitive lookup of [key] in [_data].
  dynamic _getValue(String key) {
    // Exact match first.
    if (_data.containsKey(key)) return _data[key];
    // Case-insensitive fallback.
    final lower = key.toLowerCase();
    for (final entry in _data.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Typed accessors for subclasses
  // ---------------------------------------------------------------------------

  /// Returns the value of [key] as a [String], or `null` if absent.
  String? stringValue(String key) {
    final v = _getValue(key);
    if (v == null) return null;
    return v.toString();
  }

  /// Returns the value of [key] as an [int], or `null` if absent or not parseable.
  int? intValue(String key) {
    final v = _getValue(key);
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Returns the value of [key] as a [double], or `null` if absent or not parseable.
  double? doubleValue(String key) {
    final v = _getValue(key);
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Returns the value of [key] as a [bool], or `null` if absent.
  bool? boolValue(String key) {
    final v = _getValue(key);
    if (v == null) return null;
    if (v is bool) return v;
    if (v is String) {
      if (v.toLowerCase() == 'true') return true;
      if (v.toLowerCase() == 'false') return false;
    }
    return null;
  }

  /// Returns the value of [key] parsed as a UTC [DateTime] from an ISO 8601
  /// string, or `null` if absent or not parseable.
  DateTime? dateValue(String key) {
    final v = _getValue(key);
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Embedded resource lists
  // ---------------------------------------------------------------------------

  /// Returns a typed list of sub-resources embedded under [key].
  ///
  /// Results are cached so repeated calls do not re-deserialize the JSON.
  ///
  /// ```dart
  /// List<UserResource> get users => resourceList(UserResource.new, 'users');
  /// ```
  List<T> resourceList<T extends Resource>(
    T Function(RestClient) constructor,
    String key,
  ) {
    if (_listCache.containsKey(key)) {
      return List<T>.from(_listCache[key]!);
    }

    final rawList = _getValue(key);
    if (rawList is! List) return [];

    final result = <T>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        final resource = constructor(_client);
        resource.populateFromJson(item);
        result.add(resource);
      }
    }
    _listCache[key] = result;
    return result;
  }

  // ---------------------------------------------------------------------------
  // Link helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if a link named [name] is present on this resource.
  bool hasLink(String name) => _links.containsKey(name);

  // ---------------------------------------------------------------------------
  // executeLink
  // ---------------------------------------------------------------------------

  /// Executes the named link and deserializes the response into a resource of
  /// type [T].
  ///
  /// Parameter resolution order (highest to lowest priority):
  /// 1. Values passed in [values] (case-insensitive match)
  /// 2. This resource's own [_data] (case-insensitive match)
  /// 3. The [LinkParameter.defaultValue] declared by the server
  ///
  /// Templated paths (e.g. `/api/users/{id}`) are resolved before sending.
  /// Remaining parameters are sent as:
  /// - GET / DELETE → URL query string
  /// - POST / PUT   → JSON body (`application/json`)
  /// - PATCH        → JSON body (`application/merge-patch+json`)
  Future<T> executeLink<T extends Resource>(
    T Function(RestClient) constructor,
    String linkName, {
    Map<String, dynamic> values = const {},
  }) async {
    final link = _links[linkName];
    if (link == null) {
      throw LinkNotFoundException(linkName);
    }

    // Build a case-insensitive lookup of caller-supplied values.
    final valuesLower = <String, dynamic>{};
    for (final entry in values.entries) {
      valuesLower[entry.key.toLowerCase()] = entry.value;
    }

    // Resolve each parameter's effective value.
    final resolved = <String, dynamic>{};
    for (final param in link.parameters) {
      final nameLower = param.name.toLowerCase();
      if (valuesLower.containsKey(nameLower)) {
        final v = valuesLower[nameLower];
        if (v != null) resolved[param.name] = v;
      } else {
        final fromData = _getValue(param.name);
        if (fromData != null) {
          resolved[param.name] = fromData;
        } else if (param.defaultValue != null) {
          resolved[param.name] = param.defaultValue;
        }
      }
    }

    // For links with no declared parameters, pass any caller-supplied values
    // directly (allows ad-hoc POST/PATCH bodies).
    if (link.parameters.isEmpty && values.isNotEmpty) {
      for (final entry in values.entries) {
        resolved[entry.key] = entry.value;
      }
    }

    // Resolve templated path segments, e.g. {id} → 42.
    var href = link.href;
    final pathParams = <String>{};
    final templatePattern = RegExp(r'\{(\w+)\}');
    href = href.replaceAllMapped(templatePattern, (match) {
      final paramName = match.group(1)!;
      // Case-insensitive lookup of the template variable.
      final paramNameLower = paramName.toLowerCase();
      for (final entry in resolved.entries) {
        if (entry.key.toLowerCase() == paramNameLower) {
          pathParams.add(entry.key);
          return Uri.encodeComponent(entry.value.toString());
        }
      }
      return match.group(0)!; // leave unreplaced if not found
    });

    // Remove path params from the resolved map — they've been consumed.
    for (final key in pathParams) {
      resolved.remove(key);
    }

    final verb = link.verb;
    late http.Response httpResponse;

    if (verb == 'GET' || verb == 'DELETE') {
      // Remaining params → query string.
      final queryParams = resolved.map(
        (k, v) => MapEntry(k, v.toString()),
      );
      final uri = _client.buildUriFromHref(href, queryParams);
      httpResponse = await _client.executeRequest(verb: verb, uri: uri);
    } else {
      // Remaining params → JSON body.
      final uri = _client.buildUriFromHref(href, {});
      final contentType = verb == 'PATCH'
          ? 'application/merge-patch+json'
          : 'application/json';
      final body = resolved.isEmpty ? null : jsonEncode(resolved);
      httpResponse = await _client.executeRequest(
        verb: verb,
        uri: uri,
        body: body,
        contentType: contentType,
      );
    }

    return _client.buildResource(constructor, httpResponse);
  }

  // ---------------------------------------------------------------------------
  // Status code helpers
  // ---------------------------------------------------------------------------

  /// HTTP status code from [response], or `null` if no response is set.
  int? get statusCode => response?.statusCode;

  /// `true` if [statusCode] is 200.
  bool get isOk => response?.statusCode == 200;

  /// `true` if [statusCode] is 400.
  bool get isBadRequest => response?.statusCode == 400;

  /// `true` if [statusCode] is 401.
  bool get isUnauthorized => response?.statusCode == 401;

  /// `true` if [statusCode] is 403.
  bool get isForbidden => response?.statusCode == 403;

  /// `true` if [statusCode] is 404.
  bool get isNotFound => response?.statusCode == 404;
}
