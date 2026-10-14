import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'shop_time.dart';

typedef _SetenvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _Setenv = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _TzsetNative = Void Function();
typedef _Tzset = void Function();

/// Sets the process `TZ` to the shop's zone and reloads it. Called first in
/// `main()`, before any plugin reads the environment. Linux is here for the
/// tests; Windows is left alone: its C runtime does not read IANA names in
/// `TZ`.
void useShopClockForProcess() {
  if (!(Platform.isMacOS ||
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isLinux)) {
    return;
  }
  final name = 'TZ'.toNativeUtf8();
  final value = kShopTimeZone.toNativeUtf8();
  try {
    final libc = DynamicLibrary.process();
    final setenv = libc.lookupFunction<_SetenvNative, _Setenv>('setenv');
    final tzset = libc.lookupFunction<_TzsetNative, _Tzset>('tzset');
    if (setenv(name, value, 1) == 0) tzset();
  } catch (error) {
    // Without it the app keeps the device's zone, as before.
    debugPrint('[ShopClock] could not set the process zone: $error');
  } finally {
    malloc.free(name);
    malloc.free(value);
  }
}
