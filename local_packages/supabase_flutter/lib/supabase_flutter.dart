library supabase_flutter;

import 'dart:async';

class Supabase {
  Supabase._();

  static final Supabase instance = Supabase._();
  final SupabaseClient client = SupabaseClient();

  static Future<void> initialize({required String url, required String anonKey}) async {}
}

class SupabaseClient {
  final Auth auth = Auth();
  final StorageClient storage = StorageClient();
  final FunctionsClient functions = FunctionsClient();

  PostgrestQueryBuilder from(String table) => PostgrestQueryBuilder(table);
  RealtimeChannel channel(String channel, {RealtimeChannelConfig? opts}) => RealtimeChannel(channel);
}

class Auth {
  User? currentUser;
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();
  Session? get currentSession => null;

  Future<AuthResponse> signInWithOtp({required String email}) async => AuthResponse();
  Future<AuthResponse> signInWithPassword({required String email, required String password}) async => AuthResponse();
  Future<AuthResponse> signUp({required String email, required String password}) async => AuthResponse();
  Future<void> signOut() async {}
}

class User {
  final String id;
  final String? email;
  final Map<String, dynamic>? userMetadata;

  User({this.id = '', this.email, this.userMetadata});
}

class Session {
  final User? user;
  Session({this.user});
}

class AuthState {
  final Session? session;
  AuthState({this.session});
}

class AuthResponse {
  final User? user;
  final Session? session;

  AuthResponse({this.user, this.session});
}

class PostgrestQueryBuilder {
  PostgrestQueryBuilder(this.table);

  final String table;
  final Map<String, dynamic> _filters = <String, dynamic>{};
  String? _columns;
  int? _limit;
  bool _single = false;

  PostgrestQueryBuilder select([String? columns]) {
    _columns = columns;
    return this;
  }

  PostgrestQueryBuilder eq(String column, dynamic value) {
    _filters[column] = value;
    return this;
  }

  PostgrestQueryBuilder order(String column, {bool ascending = true}) {
    return this;
  }

  PostgrestQueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  PostgrestQueryBuilder single() {
    _single = true;
    return this;
  }

  PostgrestQueryBuilder maybeSingle() {
    _single = true;
    return this;
  }

  Future<dynamic> insert(Map<String, dynamic> values) async => null;
  Future<dynamic> update(Map<String, dynamic> values) async => null;
  Future<dynamic> delete() async => null;
  Future<dynamic> upsert(Map<String, dynamic> values) async => null;
}

class RealtimeChannelConfig {}

class RealtimeChannel {
  RealtimeChannel(this.name);

  final String name;

  StreamSubscription<List<Map<String, dynamic>>> on(String event, void Function(List<Map<String, dynamic>> payload) callback) {
    return const Stream<List<Map<String, dynamic>>>.empty().listen((_) {});
  }

  Future<void> unsubscribe() async {}
}

class StorageClient {
  StorageBucket from(String bucket) => StorageBucket();
}

class StorageBucket {
  Future<void> uploadBinary(String fileName, List<int> bytes) async {}
  Future<String?> getPublicUrl(String fileName) async => null;
  Future<String?> createSignedUrl(String fileName, int expiresIn) async => null;
  Future<void> remove(List<String> paths) async {}
}

class FunctionsClient {
  Future<dynamic> invoke(String name, {Map<String, dynamic>? body}) async => null;
}
