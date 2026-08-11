import 'package:flutter/services.dart';
import 'package:gemma_poc/core/config/on_device_ai_config.dart';

/// Shared MethodChannel / EventChannel handles for on-device voice AI.
class OnDeviceAiChannel {
  OnDeviceAiChannel._();

  static const MethodChannel methods = MethodChannel(
    OnDeviceAiConfig.methodChannelName,
  );

  static const EventChannel events = EventChannel(
    OnDeviceAiConfig.eventChannelName,
  );
}
