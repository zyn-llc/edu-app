import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Light/dark/system. Defaults to following the device.
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);

/// Whether reward/error sounds play. User-toggleable in Settings.
final soundEnabledProvider = StateProvider<bool>((_) => true);
