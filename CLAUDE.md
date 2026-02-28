# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`rest-resource-swift` is a **Dart package** (the repository name is a misnomer — it contains Dart, not Swift) providing client-side HATEOAS support for Flutter apps that consume SlySoft REST APIs (`rest-resource-csharp` backend).

## Commands

```bash
dart pub get          # fetch / update dependencies
dart test             # run all unit tests
dart analyze          # static analysis (zero warnings expected)
dart format .         # auto-format all Dart source files
```

Run tests for a single file or test name:

```bash
dart test test/rest_resource_test.dart
dart test --name "GET request"
```

## Architecture

```
lib/
  rest_resource.dart        ← public barrel export
  src/
    link.dart               ← LinkParameter + Link data classes (fromJson)
    resource.dart           ← Resource abstract base class
    rest_client.dart        ← RestClient, RestClientException, LinkNotFoundException
test/
  rest_resource_test.dart   ← unit tests via MockClient (package:http/testing.dart)
pubspec.yaml
analysis_options.yaml
```

### Key types

**`Link` / `LinkParameter`** (`lib/src/link.dart`)
Plain data classes parsed from the `_links` JSON. `Link.fromJson` reads both `parameters` (query/path params) and `fields` (body params) keys since the C# backend uses both.

**`Resource`** (`lib/src/resource.dart`)
Abstract base class. Raw JSON is stored in `_data: Map<String, dynamic>`. Typed subclasses expose computed getters (`stringValue`, `intValue`, `doubleValue`, `boolValue`, `dateValue`). Embedded arrays are accessed via `resourceList<T>(constructor, key)` with an internal cache. Link navigation is through `executeLink<T>(constructor, linkName, {values})`.

**`RestClient`** (`lib/src/rest_client.dart`)
Wraps `http.Client`. Accepts an optional `httpClient` parameter for test injection. Manages default headers (Accept, Authorization). Exposes `get<T>` as the public entry point; `executeRequest` and `buildResource` are used internally by `Resource.executeLink`.

### Constructor tearoff pattern

Dart constructor tearoffs (`UserResource.new`) allow passing constructors as `T Function(RestClient)` values, so `executeLink` can create the correct subtype without `dynamic`.

### Parameter resolution in `executeLink`

Priority order (highest first):
1. Values passed in the `values` map (case-insensitive)
2. Current resource's `_data` fields (case-insensitive)
3. `defaultValue` from `LinkParameter`

Templated path segments (e.g. `{id}`) are substituted first; consumed params are removed before the remainder goes to query string (GET/DELETE) or JSON body (POST/PUT/PATCH).
