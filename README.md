# rest_resource

A Flutter/Dart client library for APIs powered by the [SlySoft HATEOAS backend](https://github.com/slysofttech/rest-resource-csharp). The backend embeds a `_links` object in every JSON response that describes what actions are available and how to call them. This library parses those links and makes them callable with full type safety — no hard-coded URLs required.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  rest_resource:
    git:
      url: https://github.com/slysofttech/rest-resource-swift.git
```

Then run:

```bash
flutter pub get
```

---

## Core Concepts

The backend returns JSON with a `_links` object alongside resource data:

```json
{
  "firstName": "Jane",
  "id": 42,
  "_links": {
    "self":       { "href": "/api/users/42", "verb": "GET" },
    "deleteUser": { "href": "/api/users/42", "verb": "DELETE" },
    "searchUsers": {
      "href": "/api/users", "verb": "GET",
      "parameters": [{ "name": "lastName" }, { "name": "firstName", "defaultValue": "" }]
    }
  }
}
```

Key ideas:
- Each link has an `href`, a `verb` (GET/POST/PUT/PATCH/DELETE), and optional `parameters`.
- The client **discovers and calls links** rather than hard-coding URLs.
- Route changes on the server require **zero client changes**.
- Links may be absent when the current user lacks permission — use `hasLink` before calling.

---

## Defining Resource Classes

```dart
import 'package:rest_resource/rest_resource.dart';

// Every resource class must:
//  1. Extend Resource
//  2. Forward the constructor: SubClass(super.client)
//  3. Expose data as computed getters using stringValue/intValue/etc.
//  4. Expose links as async methods calling executeLink(...)

class UserResource extends Resource {
  UserResource(super.client);

  // Data properties — typed getters read from the raw JSON
  int    get id        => intValue('id') ?? 0;
  String get firstName => stringValue('firstName') ?? '';
  String get lastName  => stringValue('lastName') ?? '';

  // Link availability guard (link may not exist if user lacks permission)
  bool get canDeleteUser => hasLink('deleteUser');

  // Link methods — name must match the link name from the backend exactly
  Future<void> deleteUser() =>
      executeLink(Resource.new, 'deleteUser');

  Future<UserResource> updateUser({
    required String firstName,
    required String lastName,
  }) => executeLink(UserResource.new, 'updateUser', values: {
        'firstName': firstName,
        'lastName': lastName,
      });

  Future<UserListResource> searchUsers({
    String lastName = '',
    String firstName = '',
  }) => executeLink(UserListResource.new, 'searchUsers', values: {
        'lastName': lastName,
        'firstName': firstName,
      });
}

// Resources with embedded lists
class UserListResource extends Resource {
  UserListResource(super.client);

  // Embedded arrays of sub-resources
  List<UserResource> get users => resourceList(UserResource.new, 'users');
  int get totalCount => intValue('totalCount') ?? 0;
}
```

---

## Setting Up the Client

```dart
final client = RestClient('https://api.example.com');

// Bearer token auth
client.setAuthorizationHeader('Bearer', accessToken);

// Or any arbitrary header
client.setHeader('X-Api-Key', apiKey);
```

---

## Making the First Request

```dart
// GET the root/application resource to discover what's available
final app = await client.get(ApplicationResource.new, '/api');

// Navigate to users via a link (no hard-coded URLs needed)
final userList = await app.getUsers();

for (final user in userList.users) {
  print('${user.firstName} ${user.lastName}');
}
```

---

## Working with a Single Resource

```dart
final user = await client.get(UserResource.new, '/api/users/42');

print(user.firstName);  // Jane
print(user.statusCode); // 200

// Check before calling — the link may not exist if not authorized
if (user.canDeleteUser) {
  await user.deleteUser();
}

// Call a link that returns a new resource
final updated = await user.updateUser(
  firstName: 'Jane',
  lastName: 'Doe',
);
```

---

## Handling Embedded Lists

```dart
final list = await client.get(UserListResource.new, '/api/users');

// resourceList() deserializes embedded JSON arrays into typed resources
for (final user in list.users) {
  print(user.id);  // Each item is a fully typed UserResource
}
```

---

## Error Handling

Two modes are available:

```dart
// Mode 1 (default): throw on non-2xx
try {
  final user = await client.get(UserResource.new, '/api/users/999');
} on RestClientException catch (e) {
  print(e.statusCode);           // e.g. 404
  print(e.response.body);        // raw response body for error details
} on LinkNotFoundException catch (e) {
  print(e.linkName);             // which link was missing
}

// Mode 2: never throw — inspect response on the returned resource
client.throwExceptions = false;
final user = await client.get(UserResource.new, '/api/users/999');
if (user.isNotFound) {
  print('User does not exist');
} else if (user.isOk) {
  print(user.firstName);
}
```

---

## Status Code Helpers

Every `Resource` exposes these properties after a request:

| Property        | True when status code is |
|-----------------|--------------------------|
| `isOk`          | 200                      |
| `isBadRequest`  | 400                      |
| `isUnauthorized`| 401                      |
| `isForbidden`   | 403                      |
| `isNotFound`    | 404                      |
| `statusCode`    | the actual code (int?)   |

---

## Supported Data Types

```dart
String?   stringValue('key')
int?      intValue('key')
double?   doubleValue('key')
bool?     boolValue('key')
DateTime? dateValue('key')    // parses ISO 8601; backend sends UTC
```

All lookups are case-insensitive.

---

## Available Link Verbs

Verb routing is automatic — your code just calls `executeLink`:

| Verb           | Parameters sent as                        |
|----------------|-------------------------------------------|
| GET, DELETE    | URL query string                          |
| POST, PUT      | JSON body (`application/json`)            |
| PATCH          | JSON body (`application/merge-patch+json`)|

Templated hrefs (e.g. `/api/users/{id}`) are resolved from the `values` map before the remaining parameters are sent as query string or body.

**Parameter resolution order** (highest to lowest priority):
1. Values passed in `values` map
2. Current resource's data fields (case-insensitive)
3. `defaultValue` declared by the server in the link definition

---

## Complete Flutter Integration Example

```dart
import 'package:flutter/material.dart';
import 'package:rest_resource/rest_resource.dart';

// --- Resource definitions ---

class UserResource extends Resource {
  UserResource(super.client);

  int    get id        => intValue('id') ?? 0;
  String get firstName => stringValue('firstName') ?? '';
  String get lastName  => stringValue('lastName') ?? '';

  bool get canDelete => hasLink('deleteUser');

  Future<void> deleteUser() => executeLink(Resource.new, 'deleteUser');
}

// --- Flutter widget ---

class UserProfilePage extends StatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final RestClient _client;
  late final Future<UserResource> _userFuture;

  @override
  void initState() {
    super.initState();
    _client = RestClient('https://api.example.com');
    _client.setAuthorizationHeader('Bearer', 'your-token-here');
    _userFuture = _client.get(UserResource.new, '/api/users/${widget.userId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: FutureBuilder<UserResource>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            if (err is RestClientException) {
              return Center(child: Text('Error ${err.statusCode}'));
            }
            return Center(child: Text('$err'));
          }

          final user = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${user.firstName} ${user.lastName}',
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('ID: ${user.id}'),
                if (user.canDelete)
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await user.deleteUser();
                        if (context.mounted) Navigator.of(context).pop();
                      } on RestClientException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Delete failed: ${e.statusCode}')),
                          );
                        }
                      }
                    },
                    child: const Text('Delete User'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

---

## API Reference

### `RestClient`

| Method / Property | Description |
|---|---|
| `RestClient(baseUrl, {httpClient?})` | Create a client. Pass a custom `httpClient` for testing. |
| `throwExceptions` | When `true` (default), non-2xx throws `RestClientException`. |
| `setAuthorizationHeader(scheme, value)` | Sets `Authorization: <scheme> <value>` on all requests. |
| `setHeader(name, value)` | Sets an arbitrary header on all requests. |
| `get<T>(constructor, path)` | Perform a GET and deserialize into resource `T`. |

### `Resource`

| Method / Property | Description |
|---|---|
| `stringValue(key)` | Returns field as `String?` (case-insensitive). |
| `intValue(key)` | Returns field as `int?`. |
| `doubleValue(key)` | Returns field as `double?`. |
| `boolValue(key)` | Returns field as `bool?`. |
| `dateValue(key)` | Returns field as `DateTime?` parsed from ISO 8601. |
| `resourceList<T>(constructor, key)` | Returns embedded array as `List<T>` (cached). |
| `hasLink(name)` | Returns `true` if the named link is present. |
| `executeLink<T>(constructor, linkName, {values})` | Calls the named link and returns resource `T`. |
| `response` | The raw `http.Response` from the last request. |
| `statusCode` | HTTP status code, or `null`. |
| `isOk` | `true` when status is 200. |
| `isBadRequest` | `true` when status is 400. |
| `isUnauthorized` | `true` when status is 401. |
| `isForbidden` | `true` when status is 403. |
| `isNotFound` | `true` when status is 404. |

### Exceptions

| Exception | When thrown |
|---|---|
| `RestClientException(statusCode, response)` | Non-2xx response and `throwExceptions = true`. |
| `LinkNotFoundException(linkName)` | `executeLink` called with a link not present on the resource. |
