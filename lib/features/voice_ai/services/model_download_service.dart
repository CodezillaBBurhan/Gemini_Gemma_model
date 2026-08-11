import 'dart:async';
import 'dart:io';

import 'package:gemma_poc/core/config/on_device_ai_config.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads the official Gemma 3n `.litertlm` bundle once, then stays offline.
///
/// Inference never uses this service. Network is only for initial model fetch.
class ModelDownloadService {
  ModelDownloadService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<File> resolveLocalModelFile() async {
    final dir = await _modelDirectory();
    return File('${dir.path}/${OnDeviceAiConfig.modelFileName}');
  }

  Future<bool> isModelReady() async {
    final file = await resolveLocalModelFile();
    if (!await file.exists()) return false;
    final length = await file.length();
    // Accept files within 5% of expected size, or any file > 1GB if size unknown.
    final expected = OnDeviceAiConfig.expectedModelBytes;
    if (expected <= 0) return length > 1024 * 1024 * 1024;
    return length >= (expected * 0.95);
  }

  Future<Directory> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Downloads from the configured official Hugging Face URL.
  Stream<double> downloadModel({
    String? url,
    String? authToken,
  }) async* {
    final target = await resolveLocalModelFile();
    final temp = File('${target.path}.partial');
    final uri = Uri.parse(url ?? OnDeviceAiConfig.modelDownloadUrl);

    final headers = <String, String>{
      'User-Agent': 'gemma_poc-on-device-ai',
    };
    final token = authToken ?? OnDeviceAiConfig.hfToken;
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final request = http.Request('GET', uri);
    request.headers.addAll(headers);
    final response = await _client.send(request);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'Model download requires Hugging Face access for the gated Gemma repo. '
        'Accept the license on Hugging Face and pass HF_TOKEN via --dart-define.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Model download failed (HTTP ${response.statusCode}).',
      );
    }

    final total = response.contentLength ?? OnDeviceAiConfig.expectedModelBytes;
    var received = 0;
    final sink = temp.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          yield (received / total).clamp(0.0, 1.0);
        }
      }
      await sink.flush();
      await sink.close();
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
      yield 1.0;
    } catch (e) {
      await sink.close();
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
}
