// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';

import 'base_client.dart';
import 'exception.dart';
import 'request.dart';
import 'response.dart';

/// A `dart:io`-based HTTP client.
///
/// This is the default client when running on the command line.
///
/// You can control the underlying `dart:io` [HttpRequest] by adding values to
/// [Request.context]:
///
/// * `"http.io.follow_redirects"` is a boolean. If it's `true` (the default)
///   then the request will automatically follow HTTP redirects. If it's
///   `false`, the client will need to handle redirects manually. See also
///   [HttpClientRequest.followRedirects].
///
/// * `"http.io.max_redirects"` is an integer that specifies the maximum number
///   of redirects that will be followed if `follow_redirects` is `true`. If the
///   site redirects more than this, [send] will throw a [ClientException]. It
///   defaults to `5`. See also [HttpClientRequest.maxRedirects].
///
/// * `"http.io.persistent_connection"` is a boolean. If it's `true` (the
///   default) the client will request that the TCP connection be kept alive
///   after the request completes. See also
///   [HttpClientRequest.persistentConnection].
class IOClient extends BaseClient {
  /// The underlying `dart:io` HTTP client.
  HttpClient _inner;

  /// Creates a new HTTP client.
  IOClient([HttpClient inner]) : _inner = inner ?? new HttpClient();

  Future<Response> send(Request request) async {
    try {
      var ioRequest = await _inner.openUrl(request.method, request.url);
      var context = request.context;

      ioRequest
        ..followRedirects = context['http.io.follow_redirects'] ?? true
        ..maxRedirects = context['http.io.max_redirects'] ?? 5
        ..persistentConnection =
            context['http.io.persistent_connection'] ?? true;
      request.headers.forEach((name, value) {
        ioRequest.headers.set(name, value);
      });

      request.read().pipe(DelegatingStreamConsumer.typed<List<int>>(ioRequest));
      var response = await ioRequest.done;

      var headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key] = values.join(',');
      });

      return new Response(_responseUrl(request, response), response.statusCode,
          reasonPhrase: response.reasonPhrase,
          body: DelegatingStream.typed<List<int>>(response).handleError(
              (error) => throw new ClientException(error.message, error.uri),
              test: (error) => error is HttpException),
          headers: headers);
    } on HttpException catch (error) {
      throw new ClientException(error.message, error.uri);
    } on SocketException catch (error) {
      throw new ClientException(error.message, request.url);
    }
  }

  void close() {
    if (_inner != null) _inner.close(force: true);
    _inner = null;
  }

  /// Determines the finalUrl retrieved by evaluating any redirects received in
  /// the [response] based on the initial [request].
  Uri _responseUrl(Request request, HttpClientResponse response) {
    var finalUrl = request.url;

    for (var redirect in response.redirects) {
      var location = redirect.location;

      // Redirects can either be absolute or relative
      finalUrl = location.isAbsolute ? location : finalUrl.resolveUri(location);
    }

    return finalUrl;
  }
}
