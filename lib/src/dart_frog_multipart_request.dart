import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

extension RequestConverter on Request {
  MultipartRequest? multipart() {
    final boundary = _extractMultipartBoundary(this);
    if (boundary == null) {
      return null;
    } else {
      return MultipartRequest(
        request: this,
        mediaType: boundary.mediaType,
        boundary: boundary.boundary,
      );
    }
  }
}

({
  MediaType mediaType,
  String boundary,
})? _extractMultipartBoundary(
  Request request,
) {
  final header = request.headers['Content-Type'];
  if (header == null) {
    return null;
  }

  final contentType = MediaType.parse(header);
  if (contentType.type != 'multipart') return null;

  final boundary = contentType.parameters['boundary'];
  if (boundary == null) {
    return null;
  }

  return (mediaType: contentType, boundary: boundary);
}

class MultipartRequest {
  MultipartRequest({
    required this.request,
    required this.mediaType,
    required this.boundary,
  });

  final Request request;
  final MediaType mediaType;
  final String boundary;

  Stream<Multipart> get parts {
    return MimeMultipartTransformer(boundary)
        .bind(request.bytes())
        .map(Multipart.new);
  }
}

/// An entry in a multipart request.
class Multipart extends MimeMultipart {
  Multipart(this._inner) : headers = CaseInsensitiveMap.from(_inner.headers);
  final MimeMultipart _inner;

  @override
  final Map<String, String> headers;

  String? get name => contentDisposition?['name'];
  String? get contentType => headers['content-type'];
  String? get filename => contentDisposition?['filename'];

  Map<String, String>? get contentDisposition {
    final headerValue = headers['content-disposition'];
    if (headerValue == null) return null;
    final headerParts = headerValue.split(';').map((e) => e.trim());

    final ans = <String, String>{};
    for (final headerPart in headerParts) {
      if (headerPart.contains('=')) {
        final [key, value] = headerPart.split('=');
        ans[key.trim()] = value.trim().trimQuotes();
      } else {
        ans[headerPart.trim()] = '';
      }
    }
    return ans;
  }

  late final MediaType? _contentType = _parseContentType();

  Encoding? get _encoding {
    final contentType = _contentType;
    if (contentType == null) return null;
    if (!contentType.parameters.containsKey('charset')) return null;
    return Encoding.getByName(contentType.parameters['charset']);
  }

  MediaType? _parseContentType() {
    final value = headers['content-type'];
    if (value == null) return null;

    return MediaType.parse(value);
  }

  /// Reads the content of this subpart as a single [Uint8List].
  Future<Uint8List> bytes() async {
    final builder = BytesBuilder();
    await forEach(builder.add);
    return builder.takeBytes();
  }

  /// Reads the content of this subpart as a string.
  ///
  /// The optional [encoding] parameter can be used to override the encoding
  /// used. By default, the `content-type` header of this part will be used,
  /// with a fallback to the `content-type` of the surrounding request and
  /// another fallback to [utf8] if everything else fails.
  Future<String> body([Encoding? encoding]) {
    encoding ??= _encoding ?? utf8;
    return encoding.decodeStream(this);
  }

  Future<dynamic> json([Encoding? encoding]) async {
    final string = await body(encoding);
    return jsonDecode(string);
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    void Function()? onDone,
    Function? onError,
    bool? cancelOnError,
  }) {
    return _inner.listen(
      onData,
      onDone: onDone,
      onError: onError,
      cancelOnError: cancelOnError,
    );
  }
}

extension on String {
  String trimQuotes() {
    var ans = this;
    if (ans.startsWith('"')) {
      ans = ans.substring(1);
    }
    if (ans.endsWith('"')) {
      ans = ans.substring(0, ans.length - 1);
    }
    return ans;
  }
}
