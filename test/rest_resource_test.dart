import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:rest_resource/rest_resource.dart';

// ---------------------------------------------------------------------------
// Test resource classes
// ---------------------------------------------------------------------------

class UserResource extends Resource {
  UserResource(super.client);

  int get id => intValue('id') ?? 0;
  String get firstName => stringValue('firstName') ?? '';
  String get lastName => stringValue('lastName') ?? '';
  double get score => doubleValue('score') ?? 0.0;
  bool get active => boolValue('active') ?? false;
  DateTime? get createdAt => dateValue('createdAt');

  List<String> get tagNames => stringListValue('tagNames');

  bool get canDeleteUser => hasLink('deleteUser');
  bool get canUpdateUser => hasLink('updateUser');

  Future<UserResource> getSelf() => executeLink(UserResource.new, 'self');

  Future<UserResource> deleteUser() =>
      executeLink(UserResource.new, 'deleteUser');

  Future<UserResource> updateUser({String? firstName, String? lastName}) =>
      executeLink(
        UserResource.new,
        'updateUser',
        values: {
          if (firstName != null) 'firstName': firstName,
          if (lastName != null) 'lastName': lastName,
        },
      );

  Future<UserResource> patchUser({String? firstName}) => executeLink(
        UserResource.new,
        'patchUser',
        values: {if (firstName != null) 'firstName': firstName},
      );

  Future<UserListResource> searchUsers({
    String? lastName,
    String? firstName,
  }) =>
      executeLink(
        UserListResource.new,
        'searchUsers',
        values: {
          if (lastName != null) 'lastName': lastName,
          if (firstName != null) 'firstName': firstName,
        },
      );

  Future<UserResource> getById({required int id}) =>
      executeLink(UserResource.new, 'getById', values: {'id': id});

  Future<UserListResource> filterUsers({
    List<String>? tags,
    List<int>? ids,
  }) =>
      executeLink(
        UserListResource.new,
        'filterUsers',
        values: {
          if (tags != null) 'tags': tags,
          if (ids != null) 'ids': ids,
        },
      );
}

class UserListResource extends Resource {
  UserListResource(super.client);

  List<UserResource> get users => resourceList(UserResource.new, 'users');
  int get totalCount => intValue('totalCount') ?? 0;
}

// Plain data class — deliberately does NOT extend Resource.
class Tag {
  final int id;
  final String name;

  const Tag({required this.id, required this.name});

  factory Tag.fromJson(Map<String, dynamic> json) =>
      Tag(id: (json['id'] as num).toInt(), name: json['name'] as String);
}

class TagListResource extends Resource {
  TagListResource(super.client);

  List<Tag> get tags => objectList(Tag.fromJson, 'tags');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _userJson({
  int id = 42,
  String firstName = 'Jane',
  String lastName = 'Smith',
  Map<String, dynamic> extraLinks = const {},
}) {
  final links = <String, dynamic>{
    'self': {'href': '/api/users/$id', 'verb': 'GET'},
    'deleteUser': {'href': '/api/users/$id', 'verb': 'DELETE'},
    'updateUser': {
      'href': '/api/users/$id',
      'verb': 'PUT',
      'fields': [
        {'name': 'firstName', 'defaultValue': ''},
        {'name': 'lastName', 'defaultValue': ''},
      ],
    },
    'patchUser': {
      'href': '/api/users/$id',
      'verb': 'PATCH',
      'fields': [
        {'name': 'firstName'},
      ],
    },
    'searchUsers': {
      'href': '/api/users',
      'verb': 'GET',
      'parameters': [
        {'name': 'lastName'},
        {'name': 'firstName', 'defaultValue': ''},
      ],
    },
    'getById': {
      'href': '/api/users/{id}',
      'verb': 'GET',
      'parameters': [
        {'name': 'id'},
      ],
    },
    'filterUsers': {
      'href': '/api/users',
      'verb': 'GET',
      'parameters': [
        {'name': 'tags'},
        {'name': 'ids'},
      ],
    },
    ...extraLinks,
  };

  return jsonEncode({
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'score': 9.5,
    'active': true,
    'createdAt': '2024-01-15T10:30:00Z',
    '_links': links,
  });
}

String _userListJson() {
  return jsonEncode({
    'totalCount': 2,
    'users': [
      {'id': 1, 'firstName': 'Alice', 'lastName': 'A'},
      {'id': 2, 'firstName': 'Bob', 'lastName': 'B'},
    ],
    '_links': {
      'self': {'href': '/api/users', 'verb': 'GET'},
    },
  });
}

String _tagListJson() {
  return jsonEncode({
    'tags': [
      {'id': 1, 'name': 'Alpha'},
      {'id': 2, 'name': 'Beta'},
    ],
    '_links': {
      'self': {'href': '/api/tags', 'verb': 'GET'},
    },
  });
}

RestClient _clientWith(MockClient mock) =>
    RestClient('https://api.example.com', httpClient: mock);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // 1. Link parsing
  // -------------------------------------------------------------------------
  group('Link parsing', () {
    test('_links are parsed into Link objects with correct verbs', () async {
      final mock = MockClient((_) async => http.Response(_userJson(), 200));
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');

      expect(user.hasLink('self'), isTrue);
      expect(user.hasLink('deleteUser'), isTrue);
      expect(user.hasLink('searchUsers'), isTrue);
      expect(user.hasLink('nonExistent'), isFalse);
    });

    test('link parameters are parsed correctly', () async {
      final mock = MockClient((_) async => http.Response(_userJson(), 200));
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');

      // Access internal state via executeLink behavior (verified via requests).
      // Indirect check: searching with no args uses defaultValue '' from param.
      http.Request? captured;
      final capturingMock = MockClient((req) async {
        captured = req;
        return http.Response(_userListJson(), 200);
      });
      final client2 = _clientWith(capturingMock);
      final user2 = await client2.get(UserResource.new, '/api/users/42');
      // Re-populate user2 with the user JSON since the first call returned list JSON.
      // Instead, get user first, then search.
      final userMock = MockClient((req) async {
        if (req.url.path.contains('users/42')) {
          return http.Response(_userJson(), 200);
        }
        captured = req;
        return http.Response(_userListJson(), 200);
      });
      final client3 = _clientWith(userMock);
      final user3 = await client3.get(UserResource.new, '/api/users/42');
      await user3.searchUsers();

      expect(captured, isNotNull);
      // firstName has defaultValue '' so it appears in query string.
      expect(captured!.url.queryParameters.containsKey('firstName'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 2. GET request
  // -------------------------------------------------------------------------
  group('GET request', () {
    test('query params are appended to URL', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/users/42') {
          return http.Response(_userJson(), 200);
        }
        captured = req;
        return http.Response(_userListJson(), 200);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.searchUsers(lastName: 'Smith', firstName: 'Jane');

      expect(captured, isNotNull);
      expect(captured!.url.queryParameters['lastName'], 'Smith');
      expect(captured!.url.queryParameters['firstName'], 'Jane');
    });

    test('list values produce repeated query params (?foo=a&foo=b)', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/users/42') {
          return http.Response(_userJson(), 200);
        }
        captured = req;
        return http.Response(_userListJson(), 200);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.filterUsers(tags: ['alpha', 'beta'], ids: [1, 2, 3]);

      expect(captured, isNotNull);
      expect(captured!.url.queryParametersAll['tags'], ['alpha', 'beta']);
      expect(captured!.url.queryParametersAll['ids'], ['1', '2', '3']);
    });

    test('empty list values are omitted from query string entirely', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/users/42') {
          return http.Response(_userJson(), 200);
        }
        captured = req;
        return http.Response(_userListJson(), 200);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.filterUsers(tags: [], ids: [42]);

      expect(captured, isNotNull);
      // tags was empty → must not appear at all (not even as "?tags=" or "?tags=[]")
      expect(captured!.url.queryParameters.containsKey('tags'), isFalse);
      expect(captured!.url.queryParametersAll['ids'], ['42']);
    });

    test('single-element list still emits one param (not a stringified list)',
        () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/users/42') {
          return http.Response(_userJson(), 200);
        }
        captured = req;
        return http.Response(_userListJson(), 200);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.filterUsers(tags: ['only']);

      expect(captured, isNotNull);
      expect(captured!.url.queryParametersAll['tags'], ['only']);
      // Explicitly verify we didn't serialize the list to "[only]".
      expect(captured!.url.query.contains('['), isFalse);
      expect(captured!.url.query.contains(']'), isFalse);
    });

    test('Accept header is sent', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_userJson(), 200);
      });
      final client = _clientWith(mock);
      await client.get(UserResource.new, '/api/users/42');

      expect(captured!.headers['Accept'], contains('application/json'));
    });

    test('data properties are populated', () async {
      final mock = MockClient((_) async => http.Response(_userJson(), 200));
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');

      expect(user.id, 42);
      expect(user.firstName, 'Jane');
      expect(user.lastName, 'Smith');
      expect(user.score, 9.5);
      expect(user.active, isTrue);
      expect(user.createdAt, DateTime.parse('2024-01-15T10:30:00Z'));
    });
  });

  // -------------------------------------------------------------------------
  // 3. POST request
  // -------------------------------------------------------------------------
  group('POST request', () {
    test(
      'params serialized as JSON body with application/json content type',
      () async {
        http.Request? captured;
        final mock = MockClient((req) async {
          if (req.url.path == '/api/users/42') {
            if (req.method == 'GET') {
              // Override link to use POST for this test.
              final overrideJson = jsonEncode({
                'id': 42,
                'firstName': 'Jane',
                '_links': {
                  'updateUser': {
                    'href': '/api/users/42',
                    'verb': 'POST',
                    'fields': [
                      {'name': 'firstName'},
                      {'name': 'lastName'},
                    ],
                  },
                },
              });
              return http.Response(overrideJson, 200);
            }
            captured = req;
            return http.Response(_userJson(), 200);
          }
          return http.Response('', 404);
        });
        final client = _clientWith(mock);
        final user = await client.get(UserResource.new, '/api/users/42');
        await user.updateUser(firstName: 'John', lastName: 'Doe');

        expect(captured, isNotNull);
        expect(captured!.method, 'POST');
        expect(captured!.headers['Content-Type'], contains('application/json'));
        final body = jsonDecode(captured!.body) as Map<String, dynamic>;
        expect(body['firstName'], 'John');
        expect(body['lastName'], 'Doe');
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. PATCH request
  // -------------------------------------------------------------------------
  group('PATCH request', () {
    test('uses application/merge-patch+json content type', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.method == 'GET') return http.Response(_userJson(), 200);
        captured = req;
        return http.Response(_userJson(), 200);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.patchUser(firstName: 'Janet');

      expect(captured, isNotNull);
      expect(captured!.method, 'PATCH');
      expect(
        captured!.headers['Content-Type'],
        contains('application/merge-patch+json'),
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['firstName'], 'Janet');
    });
  });

  // -------------------------------------------------------------------------
  // 5. DELETE request
  // -------------------------------------------------------------------------
  group('DELETE request', () {
    test('no body is sent', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.method == 'GET') return http.Response(_userJson(), 200);
        captured = req;
        return http.Response('', 204);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.deleteUser();

      expect(captured, isNotNull);
      expect(captured!.method, 'DELETE');
      expect(captured!.body, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // 6. Templated URL resolution
  // -------------------------------------------------------------------------
  group('Templated URL resolution', () {
    test(
      '{id} is replaced in href; leftover params go to query string',
      () async {
        http.Request? captured;
        final mock = MockClient((req) async {
          if (req.method == 'GET' && req.url.path.contains('users/42')) {
            return http.Response(_userJson(), 200);
          }
          captured = req;
          return http.Response(_userJson(id: 7), 200);
        });
        final client = _clientWith(mock);
        final user = await client.get(UserResource.new, '/api/users/42');
        await user.getById(id: 7);

        expect(captured, isNotNull);
        expect(captured!.url.path, contains('/7'));
        // 'id' was consumed as a path param, should not appear in query string.
        expect(captured!.url.queryParameters.containsKey('id'), isFalse);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 7. Parameter resolution order
  // -------------------------------------------------------------------------
  group('Parameter resolution order', () {
    test('caller values override resource data and defaults', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.method == 'GET') return http.Response(_userJson(), 200);
        captured = req;
        return http.Response(_userJson(), 200);
      });
      final client = _clientWith(mock);
      // User has firstName='Jane' in _data; we pass 'Override'.
      final user = await client.get(UserResource.new, '/api/users/42');
      await user.updateUser(firstName: 'Override', lastName: 'New');

      expect(captured, isNotNull);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['firstName'], 'Override');
    });

    test('resource data fills in missing caller values', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.method == 'GET') return http.Response(_userJson(), 200);
        captured = req;
        return http.Response(_userJson(), 200);
      });
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');
      // Only supply lastName; firstName should come from _data ('Jane').
      await user.updateUser(lastName: 'New');

      expect(captured, isNotNull);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['firstName'], 'Jane'); // from _data
      expect(body['lastName'], 'New'); // from caller
    });

    test(
      'defaultValue is used when caller and resource data both absent',
      () async {
        http.Request? captured;
        final mock = MockClient((req) async {
          // Initial GET for the user — return a user with no firstName in _data.
          if (req.url.path == '/api/users/42') {
            return http.Response(
              jsonEncode({
                'id': 1,
                '_links': {
                  'searchUsers': {
                    'href': '/api/users',
                    'verb': 'GET',
                    'parameters': [
                      {'name': 'lastName'},
                      {'name': 'firstName', 'defaultValue': 'defaultFirst'},
                    ],
                  },
                },
              }),
              200,
            );
          }
          // Subsequent search call — capture and return list.
          captured = req;
          return http.Response(_userListJson(), 200);
        });
        final client = _clientWith(mock);
        final user = await client.get(UserResource.new, '/api/users/42');
        // Don't supply firstName — should use defaultValue 'defaultFirst'.
        await user.searchUsers(lastName: 'Test');

        expect(captured, isNotNull);
        expect(captured!.url.queryParameters['firstName'], 'defaultFirst');
      },
    );
  });

  // -------------------------------------------------------------------------
  // 8. resourceList
  // -------------------------------------------------------------------------
  group('resourceList', () {
    test('embedded arrays are deserialized into typed resources', () async {
      final mock = MockClient((_) async => http.Response(_userListJson(), 200));
      final client = _clientWith(mock);
      final list = await client.get(UserListResource.new, '/api/users');

      expect(list.users, hasLength(2));
      expect(list.users[0].firstName, 'Alice');
      expect(list.users[1].firstName, 'Bob');
      expect(list.totalCount, 2);
    });

    test('resourceList returns empty list when key is absent', () async {
      final mock = MockClient(
        (_) async => http.Response(jsonEncode({'_links': {}}), 200),
      );
      final client = _clientWith(mock);
      final list = await client.get(UserListResource.new, '/api/users');

      expect(list.users, isEmpty);
    });

    test('resourceList caches results on repeated calls', () async {
      final mock = MockClient((_) async => http.Response(_userListJson(), 200));
      final client = _clientWith(mock);
      final list = await client.get(UserListResource.new, '/api/users');

      final first = list.users;
      final second = list.users;
      // Same list instance from cache.
      expect(identical(first[0], second[0]), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 8b. objectList
  // -------------------------------------------------------------------------
  group('objectList', () {
    test('embedded arrays are deserialized into typed plain objects', () async {
      final mock = MockClient((_) async => http.Response(_tagListJson(), 200));
      final client = _clientWith(mock);
      final list = await client.get(TagListResource.new, '/api/tags');

      expect(list.tags, hasLength(2));
      expect(list.tags[0].id, 1);
      expect(list.tags[0].name, 'Alpha');
      expect(list.tags[1].id, 2);
      expect(list.tags[1].name, 'Beta');
    });

    test('objectList returns empty list when key is absent', () async {
      final mock = MockClient(
        (_) async => http.Response(jsonEncode({'_links': {}}), 200),
      );
      final client = _clientWith(mock);
      final list = await client.get(TagListResource.new, '/api/tags');

      expect(list.tags, isEmpty);
    });

    test(
      'objectList returns empty list when value is not a JSON array',
      () async {
        final mock = MockClient(
          (_) async => http.Response(
            jsonEncode({'tags': 'not-a-list', '_links': {}}),
            200,
          ),
        );
        final client = _clientWith(mock);
        final list = await client.get(TagListResource.new, '/api/tags');

        expect(list.tags, isEmpty);
      },
    );

    test('objectList skips non-map elements in the array', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tags': [
              {'id': 1, 'name': 'Alpha'},
              'not-a-map',
              42,
              {'id': 2, 'name': 'Beta'},
            ],
            '_links': {},
          }),
          200,
        ),
      );
      final client = _clientWith(mock);
      final list = await client.get(TagListResource.new, '/api/tags');

      expect(list.tags, hasLength(2));
      expect(list.tags[0].name, 'Alpha');
      expect(list.tags[1].name, 'Beta');
    });
  });

  group('stringListValue', () {
    test('reads JSON array of strings', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tagNames': ['vegan', 'gluten-free'],
            '_links': {},
          }),
          200,
        ),
      );
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/user');

      expect(user.tagNames, ['vegan', 'gluten-free']);
    });

    test('returns empty list when key is absent', () async {
      final mock = MockClient(
        (_) async => http.Response(jsonEncode({'_links': {}}), 200),
      );
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/user');

      expect(user.tagNames, isEmpty);
    });

    test('returns empty list when value is not a JSON array', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'tagNames': 'not-a-list', '_links': {}}),
          200,
        ),
      );
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/user');

      expect(user.tagNames, isEmpty);
    });

    test('coerces non-string elements via toString()', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tagNames': ['vegan', 42, true],
            '_links': {},
          }),
          200,
        ),
      );
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/user');

      expect(user.tagNames, ['vegan', '42', 'true']);
    });
  });

  // -------------------------------------------------------------------------
  // 9. Error handling — throwExceptions = true
  // -------------------------------------------------------------------------
  group('Error handling (throwExceptions = true)', () {
    test('non-2xx throws RestClientException', () async {
      final mock = MockClient(
        (_) async => http.Response('{"error":"not found"}', 404),
      );
      final client = _clientWith(mock);

      expect(
        () => client.get(UserResource.new, '/api/users/999'),
        throwsA(
          isA<RestClientException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test('LinkNotFoundException thrown for missing link', () async {
      final mock = MockClient((_) async => http.Response(_userJson(), 200));
      final client = _clientWith(mock);
      final user = await client.get(UserResource.new, '/api/users/42');

      expect(
        () => user.executeLink(UserResource.new, 'nonExistentLink'),
        throwsA(
          isA<LinkNotFoundException>().having(
            (e) => e.linkName,
            'linkName',
            'nonExistentLink',
          ),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // 10. throwExceptions = false
  // -------------------------------------------------------------------------
  group('throwExceptions = false', () {
    test(
      'returns resource with response attached; no throw on non-2xx',
      () async {
        final mock = MockClient(
          (_) async => http.Response('{"error":"not found"}', 404),
        );
        final client = _clientWith(mock);
        client.throwExceptions = false;

        final user = await client.get(UserResource.new, '/api/users/999');

        expect(user.isNotFound, isTrue);
        expect(user.isOk, isFalse);
        expect(user.statusCode, 404);
      },
    );

    test('successful response still populates resource', () async {
      final mock = MockClient((_) async => http.Response(_userJson(), 200));
      final client = _clientWith(mock);
      client.throwExceptions = false;

      final user = await client.get(UserResource.new, '/api/users/42');

      expect(user.isOk, isTrue);
      expect(user.firstName, 'Jane');
    });
  });

  // -------------------------------------------------------------------------
  // 11. Status code helpers
  // -------------------------------------------------------------------------
  group('Status code helpers', () {
    Future<UserResource> _userWithStatus(int code) async {
      final mock = MockClient((_) async => http.Response('{}', code));
      final client = _clientWith(mock);
      client.throwExceptions = false;
      return client.get(UserResource.new, '/api/users/1');
    }

    test('isOk true for 200', () async {
      final user = await _userWithStatus(200);
      expect(user.isOk, isTrue);
    });

    test('isBadRequest true for 400', () async {
      final user = await _userWithStatus(400);
      expect(user.isBadRequest, isTrue);
    });

    test('isUnauthorized true for 401', () async {
      final user = await _userWithStatus(401);
      expect(user.isUnauthorized, isTrue);
    });

    test('isForbidden true for 403', () async {
      final user = await _userWithStatus(403);
      expect(user.isForbidden, isTrue);
    });

    test('isNotFound true for 404', () async {
      final user = await _userWithStatus(404);
      expect(user.isNotFound, isTrue);
    });

    test('statusCode returns correct value', () async {
      final user = await _userWithStatus(503);
      expect(user.statusCode, 503);
    });
  });

  // -------------------------------------------------------------------------
  // 12. Authorization header
  // -------------------------------------------------------------------------
  group('Authorization header', () {
    test('setAuthorizationHeader sends correct Authorization header', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_userJson(), 200);
      });
      final client = _clientWith(mock);
      client.setAuthorizationHeader('Bearer', 'my-token');
      await client.get(UserResource.new, '/api/users/42');

      expect(captured!.headers['Authorization'], 'Bearer my-token');
    });

    test('setHeader sends arbitrary header', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(_userJson(), 200);
      });
      final client = _clientWith(mock);
      client.setHeader('X-Api-Key', 'abc123');
      await client.get(UserResource.new, '/api/users/42');

      expect(captured!.headers['X-Api-Key'], 'abc123');
    });
  });
}
