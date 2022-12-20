library unleash_proxy_client_flutter;

import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:events_emitter/events_emitter.dart';
import 'package:unleash_proxy_client_flutter/parse_toggles.dart';
import 'package:unleash_proxy_client_flutter/storage_provider.dart';
import 'package:unleash_proxy_client_flutter/toggle_config.dart';
import 'package:unleash_proxy_client_flutter/unleash_context.dart';
import 'package:unleash_proxy_client_flutter/variant.dart';

import 'http_toggle_client.dart';
import 'in_memory_storage_provider.dart';

class UnleashClient extends EventEmitter {
  String url;
  final String clientKey;
  final String appName;
  final int refreshInterval;
  final Future<http.Response> Function(http.Request) fetcher;
  Timer? timer;
  Map<String, ToggleConfig> toggles = {};
  StorageProvider storageProvider;
  String? etag;
  late Future<void> ready = init();

  UnleashClient(
      {required this.url,
      required this.clientKey,
      required this.appName,
      this.refreshInterval = 30,
      this.fetcher = get,
      storageProvider})
      : storageProvider = storageProvider ?? InMemoryStorageProvider();

  Future<Map<String, ToggleConfig>> fetchToggles() async {
    var headers = {
      'Accept': 'application/json',
      'Cache': 'no-cache',
      'Authorization': clientKey,
    };
    var localEtag = etag;
    if (localEtag != null) {
      headers.putIfAbsent('If-None-Match', () => localEtag);
    }
    var request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headers);
    var response = await fetcher(request);

    if (response.headers.containsKey('ETag') && response.statusCode == 200) {
      etag = response.headers['ETag'];
    }

    await storageProvider.save('unleash_repo', response.body);

    return parseToggleResponse(response.body);
  }

  Future<void> init() async {
    print('initializing started');
    await fetchTogglesFromStorage();
    print('fetched from storage');

    emit('initialized', 'unleash client initialized');
  }

  Future<Map<String, ToggleConfig>> fetchTogglesFromStorage() async {
    var toggles = await storageProvider.get('unleash_repo');

    if(toggles == null) {
      return {};
    }

    return parseToggleResponse(toggles);
  }

  Future<void> updateContext(UnleashContext unleashContext) async {
    var contextSnapshot = unleashContext.toSnapshot();
    var queryParams = Uri(queryParameters: contextSnapshot).query;
    url = '$url?$queryParams';
    await fetchToggles();
  }

  Variant getVariant(String featureName) {
    var toggle = toggles[featureName];

    if (toggle != null) {
      return toggle.variant;
    } else {
      return Variant.defaultVariant;
    }
  }

  Future<void> start() async {
    toggles = await fetchToggles();

    emit('ready', 'feature toggle ready');
    timer = Timer.periodic(Duration(seconds: refreshInterval), (timer) {
      fetchToggles();
    });
  }

  stop() {
    final Timer? localTimer = timer;
    if (localTimer != null && localTimer.isActive) {
      localTimer.cancel();
    }
  }

  bool isEnabled(String featureName) {
    return toggles[featureName]?.enabled ?? false;
  }
}
