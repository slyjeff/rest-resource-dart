import 'dart:convert';
import 'package:http/http.dart' as http;

/// Minimal interface that [RestClient.buildResource] requires on any resource.
///
/// [Resource] extends this. App code always extends [Resource] directly.
abstract class ResourceBase {
  void populateFromJson(Map<String, dynamic> json);
  // ignore: avoid_setters_without_getters
  set response(http.Response? value);
}

/// Thrown when the server returns a non-2xx response and
/// [RestClient.throwExceptions] is `true`.
class RestClientException implements Exception {
  final int statusCode;
  final http.Response response;

  RestClientException(this.statusCode, this.response);

  @override
  String toString() =>
      'RestClientException: HTTP $statusCode\n${response.body}';
}

/// Thrown when [Resource.executeLink] is called with a link name that does not
/// exist on the current resource.
class LinkNotFoundException implements Exception {
  final String linkName;

  LinkNotFoundException(this.linkName);

  @override
  String toString() => 'LinkNotFoundException: link "$linkName" not found';
}

/// HTTP client wrapper that handles authentication headers, request execution,
/// and typed resource construction.
class RestClient {
  final String baseUrl;
  final http.Client _httpClient;

  /// When `true` (default), a non-2xx response throws [RestClientException].
  /// When `false`, the resource is returned with [Resource.response] set.
  bool throwExceptions = true;

  final Map<String, String> _defaultHeaders = {
    'Accept': 'application/slysoft+json, application/json',
  };

  RestClient(this.baseUrl, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Sets an `Authorization` header, e.g. `setAuthorizationHeader('Bearer', token)`.
  void setAuthorizationHeader(String scheme, String value) {
    _defaultHeaders['Authorization'] = '$scheme $value';
  }

  /// Sets an arbitrary default header sent with every request.
  void setHeader(String name, String value) {
    _defaultHeaders[name] = value;
  }

  /// Performs a GET request to [path] and deserializes the response into [T].
  Future<T> get<T extends ResourceBase>(
    T Function(RestClient) constructor,
    String path,
  ) async {
    final uri = _buildUri(path, {});
    final response = await executeRequest(verb: 'GET', uri: uri);
    return buildResource(constructor, response);
  }

  /// Executes an HTTP request and returns the raw [http.Response].
  Future<http.Response> executeRequest({
    required String verb,
    required Uri uri,
    String? body,
    String? contentType,
  }) async {
    final headers = Map<String, String>.from(_defaultHeaders);
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }

    http.Response response;
    switch (verb) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
      case 'DELETE':
        response = await _httpClient.delete(uri, headers: headers);
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: body,
        );
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: headers,
          body: body,
        );
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: headers,
          body: body,
        );
      default:
        throw ArgumentError('Unsupported HTTP verb: $verb');
    }
    return response;
  }

  /// Constructs a resource of type [T] from an [http.Response].
  ///
  /// If [throwExceptions] is `true` and the response is non-2xx, throws
  /// [RestClientException]. Otherwise returns the resource with
  /// `response` set so callers can inspect the status.
  Future<T> buildResource<T extends ResourceBase>(
    T Function(RestClient) constructor,
    http.Response response,
  ) async {
    final resource = constructor(this);
    resource.response = response;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (throwExceptions) {
        throw RestClientException(response.statusCode, response);
      }
      return resource;
    }

    final body = response.body;
    if (body.isNotEmpty) {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        resource.populateFromJson(json);
      }
    }

    return resource;
  }

  /// Builds a [Uri] by resolving [path] against [baseUrl] and appending
  /// [queryParams] as a query string.
  Uri _buildUri(String path, Map<String, String> queryParams) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final rel = path.startsWith('/') ? path.substring(1) : path;
    final full = '$base$rel';
    final uri = Uri.parse(full);
    if (queryParams.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParams},
    );
  }

  /// Builds a URI from a full href (which may already be absolute).
  Uri buildUriFromHref(String href, Map<String, String> queryParams) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      final uri = Uri.parse(href);
      if (queryParams.isEmpty) return uri;
      return uri.replace(
        queryParameters: {...uri.queryParameters, ...queryParams},
      );
    }
    return _buildUri(href, queryParams);
  }
}
