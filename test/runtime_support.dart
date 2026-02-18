import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

bool? _linuxRuntimeDlopenSupportedCache;

bool _supportsRuntimeDlopenOnLinux() {
  if (!Platform.isLinux) {
    return true;
  }
  final cached = _linuxRuntimeDlopenSupportedCache;
  if (cached != null) {
    return cached;
  }

  final dartExecutable = p.normalize(Platform.resolvedExecutable);
  final dartDir = p.dirname(dartExecutable);
  final candidates = <String>[
    p.join(dartDir, 'dartaotruntime'),
    p.join(dartDir, 'cache', 'dart-sdk', 'bin', 'dartaotruntime'),
  ];

  for (final candidate in candidates) {
    if (!File(candidate).existsSync()) {
      continue;
    }
    try {
      DynamicLibrary.open(candidate);
      _linuxRuntimeDlopenSupportedCache = true;
      return true;
    } catch (_) {
      // Try next candidate path.
    }
  }

  _linuxRuntimeDlopenSupportedCache = false;
  return false;
}

bool shouldSkipRuntimeDependentLinuxTests() {
  return Platform.isLinux && !_supportsRuntimeDlopenOnLinux();
}
