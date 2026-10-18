import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:monopoly_deal_server/monopoly_deal_server.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()..addOption('port', abbr: 'p', defaultsTo: '8080');
  final port = int.parse(parser.parse(args)['port'] as String);

  final handler = buildHandler(RoomManager());
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('Monopoly Deal server listening on ws://${server.address.host}:${server.port}');
}
