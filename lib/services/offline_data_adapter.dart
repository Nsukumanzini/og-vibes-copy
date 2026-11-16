import 'dart:async';
import 'dart:typed_data';

/// Local, empty data adapter retained while the application has no backend.
/// All requests resolve locally and never contact a service.
class OfflineData {
  OfflineData._();

  static final OfflineData instance = OfflineData._();
  final OfflineDataClient client = OfflineDataClient();
}

class OfflineDataClient {
  final OfflineAuthClient auth = OfflineAuthClient();
  final OfflineStorageClient storage = OfflineStorageClient();
  final OfflineFunctionsClient functions = OfflineFunctionsClient();
  final OfflineRealtimeClient realtime = OfflineRealtimeClient();

  OfflineQuery from(String table) => OfflineQuery();
  OfflineQuery rpc(String function, {Map<String, dynamic>? params}) =>
      OfflineQuery();
  OfflineRealtimeChannel channel(
    String name, {
    OfflineRealtimeChannelConfig? opts,
  }) =>
      OfflineRealtimeChannel();
  Future<void> removeChannel(OfflineRealtimeChannel channel) async {}
}

class OfflineQuery implements Future<List<Map<String, dynamic>>> {
  static const List<Map<String, dynamic>> _empty = [];

  OfflineQuery select([String? columns]) => this;
  OfflineQuery insert(Object values, {String? onConflict}) => this;
  OfflineQuery update(Object values, {String? onConflict}) => this;
  OfflineQuery upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  }) =>
      this;
  OfflineQuery delete() => this;
  OfflineQuery eq(String column, Object? value) => this;
  OfflineQuery neq(String column, Object? value) => this;
  OfflineQuery gt(String column, Object? value) => this;
  OfflineQuery gte(String column, Object? value) => this;
  OfflineQuery lt(String column, Object? value) => this;
  OfflineQuery lte(String column, Object? value) => this;
  OfflineQuery inFilter(String column, List<Object?> values) => this;
  OfflineQuery or(String expression, {String? referencedTable}) => this;
  OfflineQuery match(Map<String, Object?> values) => this;
  OfflineQuery range(int from, int to, {String? referencedTable}) => this;
  OfflineQuery order(
    String column, {
    bool ascending = true,
    Object? nullsFirst,
    String? referencedTable,
  }) =>
      this;
  OfflineQuery limit(int count, {String? referencedTable}) => this;
  OfflineQuery isFilter(String column, Object? value) => this;

  Future<Map<String, dynamic>?> maybeSingle() async => null;
  Future<Map<String, dynamic>> single() async => <String, dynamic>{};
  OfflineStreamQuery stream({List<String>? primaryKey}) => OfflineStreamQuery();

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) =>
      Future<List<Map<String, dynamic>>>.value(_empty).then(
        onValue,
        onError: onError,
      );

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) =>
      Future<List<Map<String, dynamic>>>.value(_empty).catchError(
        onError,
        test: test,
      );

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) =>
      Future<List<Map<String, dynamic>>>.value(_empty).timeout(
        timeLimit,
        onTimeout: onTimeout,
      );

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) =>
      Future<List<Map<String, dynamic>>>.value(_empty).whenComplete(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class OfflineStreamQuery {
  final Stream<List<Map<String, dynamic>>> _stream =
      const Stream<List<Map<String, dynamic>>>.empty();

  OfflineStreamQuery eq(String column, Object? value) => this;
  OfflineStreamQuery order(String column, {bool ascending = true}) => this;

  StreamSubscription<List<Map<String, dynamic>>> listen(
    void Function(List<Map<String, dynamic>> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  dynamic noSuchMethod(Invocation invocation) => this;
}

class OfflineAuthClient {
  OfflineUser? get currentUser => null;
  OfflineSession? get currentSession => null;
  Stream<OfflineAuthState> get onAuthStateChange =>
      const Stream<OfflineAuthState>.empty();

  Future<void> signOut() async {}
  Future<void> reauthenticate() async {}
  Future<void> updateUser(OfflineUserAttributes attributes) async {}
  Future<OfflineAuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async =>
      const OfflineAuthResponse();
}

class OfflineAuthResponse {
  const OfflineAuthResponse({this.user, this.session});
  final OfflineUser? user;
  final OfflineSession? session;
}

class OfflineUserAttributes {
  const OfflineUserAttributes({this.password, this.data});
  final String? password;
  final Map<String, dynamic>? data;
}

class OfflineUser {
  const OfflineUser({
    this.id = '',
    this.email,
    this.phone,
    this.createdAt = '',
    this.emailConfirmedAt,
    this.userMetadata,
  });

  final String id;
  final String? email;
  final String? phone;
  final String createdAt;
  final DateTime? emailConfirmedAt;
  final Map<String, dynamic>? userMetadata;
}

typedef User = OfflineUser;

class OfflineSession {
  const OfflineSession({this.user});
  final OfflineUser? user;
}

enum OfflineAuthChangeEvent { initialSession, signedIn, signedOut, userUpdated }

class OfflineAuthState {
  const OfflineAuthState({
    this.event = OfflineAuthChangeEvent.initialSession,
    this.session,
  });
  final OfflineAuthChangeEvent event;
  final OfflineSession? session;
}

class OfflineStorageClient {
  OfflineStorageBucket from(String bucket) => OfflineStorageBucket();
}

class OfflineStorageBucket {
  String getPublicUrl(String path) => '';
  Future<String> createSignedUrl(String path, int expirySeconds) async => '';
  Future<String> uploadBinary(
    String path,
    Uint8List bytes, {
    OfflineFileOptions? fileOptions,
  }) async =>
      path;
  Future<String> upload(
    String path,
    Object file, {
    OfflineFileOptions? fileOptions,
  }) async =>
      path;
  Future<Uint8List> download(String path) async => Uint8List(0);
  Future<void> remove(List<String> paths) async {}
  Future<void> move(String from, String to) async {}
  Future<List<Map<String, dynamic>>> list([String path = '']) async =>
      const <Map<String, dynamic>>[];
}

class OfflineFileOptions {
  const OfflineFileOptions({this.cacheControl, this.contentType, this.upsert});
  final String? cacheControl;
  final String? contentType;
  final bool? upsert;
}

class OfflineFunctionsClient {
  Future<OfflineFunctionResponse> invoke(
    String function, {
    Map<String, dynamic>? body,
  }) async =>
      const OfflineFunctionResponse();
}

class OfflineFunctionResponse {
  const OfflineFunctionResponse({this.data, this.status = 503});
  final dynamic data;
  final int status;
}

class OfflineRealtimeClient {
  Future<void> disconnect() async {}
}

class OfflineRealtimeChannelConfig {
  const OfflineRealtimeChannelConfig({this.key, this.enabled = true});
  final String? key;
  final bool enabled;
}

class OfflineRealtimeChannel {
  OfflineRealtimeChannel onPostgresChanges({
    required OfflinePostgresChangeEvent event,
    String? schema,
    String? table,
    OfflinePostgresChangeFilter? filter,
    required void Function(dynamic payload) callback,
  }) =>
      this;

  OfflineRealtimeChannel onBroadcast({
    required String event,
    required void Function(dynamic payload) callback,
  }) =>
      this;

  OfflineRealtimeChannel onPresenceSync(
    void Function(dynamic payload) callback,
  ) =>
      this;
  OfflineRealtimeChannel onPresenceJoin(void Function(dynamic payload) callback) =>
      this;
  OfflineRealtimeChannel onPresenceLeave(void Function(dynamic payload) callback) =>
      this;

  OfflineRealtimeChannel subscribe([
    void Function(OfflineRealtimeSubscribeStatus status, Object? error)? callback,
  ]) {
    callback?.call(OfflineRealtimeSubscribeStatus.subscribed, null);
    return this;
  }

  Future<void> track(Map<String, dynamic> payload) async {}
  Future<void> untrack() async {}
  Future<void> unsubscribe() async {}
  Future<void> sendBroadcastMessage({
    required String event,
    required Map<String, dynamic> payload,
  }) async {}
  List<OfflinePresenceState> presenceState() => const [];
}

class OfflinePresenceState {
  const OfflinePresenceState({this.presences = const []});
  final List<OfflinePresence> presences;
}

class OfflinePresence {
  const OfflinePresence({this.payload = const {}});
  final Map<String, dynamic> payload;
}

enum OfflineRealtimeSubscribeStatus { subscribed, channelError, timedOut, closed }
enum OfflinePostgresChangeEvent { all, insert, update, delete }
enum OfflinePostgresChangeFilterType { eq }

class OfflinePostgresChangeFilter {
  const OfflinePostgresChangeFilter({
    required this.type,
    required this.column,
    required this.value,
  });
  final OfflinePostgresChangeFilterType type;
  final String column;
  final Object value;
}

class OfflineAuthException implements Exception {
  const OfflineAuthException(this.message);
  final String message;
  @override
  String toString() => 'OfflineAuthException: $message';
}

class OfflinePostgrestException implements Exception {
  const OfflinePostgrestException({
    this.message = 'Offline data is unavailable.',
    this.code,
    this.details,
    this.hint,
  });
  final String message;
  final String? code;
  final String? details;
  final String? hint;
  @override
  String toString() => 'OfflinePostgrestException(message: $message)';
}

class OfflineStorageException implements Exception {
  const OfflineStorageException(this.message);
  final String message;
}
