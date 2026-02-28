/// A parameter described in a link — used for query, path, or body params.
class LinkParameter {
  final String name;
  final String type;
  final String? defaultValue;
  final List<String> listOfValues;

  const LinkParameter({
    required this.name,
    this.type = 'string',
    this.defaultValue,
    this.listOfValues = const [],
  });

  factory LinkParameter.fromJson(Map<String, dynamic> json) {
    final listOfValues = <String>[];
    if (json['listOfValues'] is List) {
      for (final v in json['listOfValues'] as List) {
        listOfValues.add(v.toString());
      }
    }
    return LinkParameter(
      name: json['name'] as String,
      type: (json['type'] as String?) ?? 'string',
      defaultValue: json['defaultValue'] as String?,
      listOfValues: listOfValues,
    );
  }
}

/// A navigational link returned by the server describing an available action.
class Link {
  final String href;
  final String verb;
  final bool templated;
  final List<LinkParameter> parameters;
  final int? timeout;

  const Link({
    required this.href,
    required this.verb,
    this.templated = false,
    this.parameters = const [],
    this.timeout,
  });

  factory Link.fromJson(Map<String, dynamic> json) {
    final parameters = <LinkParameter>[];
    // The C# backend uses both 'parameters' (query/path) and 'fields' (body).
    for (final key in ['parameters', 'fields']) {
      if (json[key] is List) {
        for (final p in json[key] as List) {
          if (p is Map<String, dynamic>) {
            parameters.add(LinkParameter.fromJson(p));
          }
        }
      }
    }
    return Link(
      href: json['href'] as String,
      verb: ((json['verb'] as String?) ?? 'GET').toUpperCase(),
      templated: (json['templated'] as bool?) ?? false,
      parameters: parameters,
      timeout: json['timeout'] as int?,
    );
  }
}
