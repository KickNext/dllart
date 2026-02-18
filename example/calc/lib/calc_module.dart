import 'dart:typed_data';

import 'package:dllart/dllart_annotations.dart';

Map<String, dynamic> _expectMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw ArgumentError('Expected JSON object payload');
}

num _expectNumber(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) {
    return value;
  }
  throw ArgumentError('Expected numeric field: $key');
}

String _expectString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw ArgumentError('Expected string field: $key');
}

int _expectPositiveInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! num) {
    throw ArgumentError('Expected numeric field: $key');
  }
  final result = value.toInt();
  if (result <= 0) {
    throw ArgumentError('Expected positive value for field: $key');
  }
  return result;
}

const int _cpuMask = 0x7fffffff;
const int _ioMask32 = 0xffffffff;
const int _ioBlockSize = 1 << 20;
Uint8List? _ioPayload;

void _fillIoBuffer(Uint8List buffer) {
  var seed = 0xA5A5A5A5;
  for (var i = 0; i < buffer.length; i++) {
    seed ^= (seed << 13) & _ioMask32;
    seed ^= seed >> 17;
    seed ^= (seed << 5) & _ioMask32;
    seed &= _ioMask32;
    buffer[i] = seed & 0xff;
  }
}

@DllartExport()
Object? add(Object? args) {
  final payload = _expectMap(args);
  return _expectNumber(payload, 'a') + _expectNumber(payload, 'b');
}

@DllartExport('add_fast')
int addFast(int a, int b) {
  return a + b;
}

@DllartExport('cpu_work_fast')
int cpuWorkFast(int iterations, int seed) {
  if (iterations <= 0) {
    throw ArgumentError('iterations must be > 0');
  }
  var x = seed & _cpuMask;
  var acc = 0;
  for (var i = 0; i < iterations; i++) {
    x = ((x * 1103515245) + 12345) & _cpuMask;
    acc = (acc + ((x ^ i) & _cpuMask)) & _cpuMask;
  }
  return acc;
}

@DllartExport('sum4_fast')
int sum4Fast(int a, int b, int c, int d) {
  return a + b + c + d;
}

@DllartExport('avg2_fast')
double avg2Fast(double a, double b) {
  return (a + b) / 2.0;
}

@DllartExport()
Object? mul(Object? args) {
  final payload = _expectMap(args);
  return _expectNumber(payload, 'a') * _expectNumber(payload, 'b');
}

@DllartExport()
Object? echo(Object? args) {
  final payload = _expectMap(args);
  return payload['value'];
}

@DllartExport()
Object? ping() {
  return 'pong';
}

@DllartExport('io_write')
int ioWrite(Object? args) {
  final payload = _expectMap(args);
  _expectString(payload, 'path');
  final fileMb = _expectPositiveInt(payload, 'fileMb');
  // Intentionally in-memory payload synthesis for benchmark parity.
  // The exported API shape mirrors file-style operations without dart:io usage.
  final totalBytes = fileMb * 1024 * 1024;
  final payloadBuffer = Uint8List(totalBytes);
  final pattern = Uint8List(_ioBlockSize);
  _fillIoBuffer(pattern);

  var offset = 0;
  while (offset < totalBytes) {
    final chunk = (totalBytes - offset) > _ioBlockSize
        ? _ioBlockSize
        : (totalBytes - offset);
    payloadBuffer.setRange(offset, offset + chunk, pattern);
    offset += chunk;
  }

  _ioPayload = payloadBuffer;
  return totalBytes;
}

@DllartExport('io_read')
int ioRead(Object? args) {
  final payload = _expectMap(args);
  _expectString(payload, 'path');
  final fileMb = _expectPositiveInt(payload, 'fileMb');
  final totalBytes = fileMb * 1024 * 1024;
  final data = _ioPayload;
  if (data == null) {
    throw StateError('No payload written before read');
  }
  if (data.length != totalBytes) {
    throw StateError('Payload size mismatch');
  }

  var checksum = 0;
  for (var i = 0; i < data.length; i++) {
    checksum += data[i];
  }

  _ioPayload = null;
  return checksum;
}
