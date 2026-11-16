import 'offline_data_adapter.dart';

class IceServers {
  static const Map<String, dynamic> fallback = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  static Future<Map<String, dynamic>> fetch() async {
    try {
      final response = await OfflineData.instance.client.functions.invoke('get-turn-credentials');
      final data = response.data;
      if (data == null) {
        throw Exception('Failed to fetch TURN credentials: no data returned');
      }
      if (data is Map<String, dynamic> && data['iceServers'] != null) {
        return {'iceServers': data['iceServers']};
      }

      throw Exception('Unexpected get-turn-credentials response format.');
    } catch (exception) {
      // ignore: avoid_print
      print('Error fetching ICE servers: $exception');
      return fallback;
    }
  }
}
