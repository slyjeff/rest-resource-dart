/// Client-side HATEOAS support for Flutter apps consuming SlySoft REST resources.
///
/// Import this library to use [RestClient], [Resource], [Link],
/// [LinkParameter], [RestClientException], and [LinkNotFoundException].
library rest_resource;

export 'src/link.dart' show Link, LinkParameter;
export 'src/resource.dart' show Resource;
export 'src/rest_client.dart'
    show RestClient, ResourceBase, RestClientException, LinkNotFoundException;
