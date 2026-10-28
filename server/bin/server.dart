import 'dart:io';

import 'package:av_relay/av_relay.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  // 0.0.0.0 so phones on the same Wi-Fi can reach this PC.
  final server = await io.serve(buildRelayHandler(), InternetAddress.anyIPv4, port);
  stdout.writeln('AV_chat relay listening on 0.0.0.0:${server.port}');
}
