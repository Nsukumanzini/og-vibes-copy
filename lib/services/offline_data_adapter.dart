import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'offline_mock_data.dart';

/// Local mock data adapter used while the app has no backend configured.
class OfflineData {
  OfflineData._();

  static final OfflineData instance = OfflineData._();
  final OfflineDataClient client = OfflineDataClient();
}

class OfflineDataClient {
  OfflineDataClient() : store = OfflineMockStore(), auth = OfflineAuthClient();

  final OfflineMockStore store;
  final OfflineAuthClient auth;
  OfflineStorageClient get storage => OfflineStorageClient(store);
  final OfflineFunctionsClient functions = OfflineFunctionsClient();
  final OfflineRealtimeClient realtime = OfflineRealtimeClient();

  OfflineMockQuery from(String table) => OfflineMockQuery(store, table);
  OfflineRpcQuery rpc(String function, {Map<String, dynamic>? params}) =>
      OfflineRpcQuery(store, function, params ?? const <String, dynamic>{});
  OfflineRealtimeChannel channel(
    String name, {
    OfflineRealtimeChannelConfig? opts,
  }) => OfflineRealtimeChannel();
  Future<void> removeChannel(OfflineRealtimeChannel channel) async {}
}

class OfflineMockStore {
  OfflineMockStore() : _tables = OfflineMockData.createTables();

  final Map<String, List<Map<String, dynamic>>> _tables;
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );
  final Map<String, Uint8List> files = <String, Uint8List>{};
  int _nextId = 0;

  List<Map<String, dynamic>> rows(String table) =>
      _tables.putIfAbsent(table, () => <Map<String, dynamic>>[]);
  Stream<String> get changes => _changes.stream;
  String newId(String table) => 'mock-' + table + '-' + (++_nextId).toString();
  void changed(String table) {
    if (!_changes.isClosed) _changes.add(table);
  }

  Future<dynamic> runRpc(String function, Map<String, dynamic> params) async {
    switch (function) {
      case 'get_mutual_friend_counts':
        final ids = List<dynamic>.from(
          params['candidate_ids'] as List? ?? const <dynamic>[],
        );
        return ids
            .map(
              (id) => <String, dynamic>{
                'candidate_id': id.toString(),
                'mutual_count': id == OfflineMockData.friendOneId ? 2 : 1,
              },
            )
            .toList();
      case 'accept_friend_request':
        final requestId = params['request_id']?.toString();
        for (final row in rows('friend_requests')) {
          if (row['id']?.toString() != requestId) continue;
          row['status'] = 'accepted';
          rows('friendships').add(<String, dynamic>{
            'id': newId('friendship'),
            'user_id': row['sender_id'],
            'friend_id': row['receiver_id'],
            'created_at': OfflineMockData.now,
          });
          changed('friend_requests');
          changed('friendships');
          break;
        }
        return null;
      case 'preview_module_invitation':
        final invitations = rows('module_invitations');
        if (invitations.isEmpty) return <Map<String, dynamic>>[];
        final invitation = invitations.first;
        final module = Map<String, dynamic>.from(
          invitation['modules'] as Map? ?? const <String, dynamic>{},
        );
        final lecturer = Map<String, dynamic>.from(
          invitation['profiles'] as Map? ?? const <String, dynamic>{},
        );
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'invitation_id': invitation['id'],
            'module_name': module['name'],
            'module_code': module['code'],
            'module_level': module['level'],
            'lecturer_name': lecturer['nickname'] ?? 'Lecturer',
            'academic_year': invitation['academic_year'],
            'semester': invitation['semester'],
            'expires_at': invitation['expires_at'],
          },
        ];
      case 'accept_module_invitation':
      case 'decline_module_invitation':
        final invitationId = params['invitation_id']?.toString();
        for (final invitation in rows('module_invitations')) {
          if (invitationId != null &&
              invitation['id']?.toString() != invitationId) {
            continue;
          }
          invitation['status'] = function == 'accept_module_invitation'
              ? 'accepted'
              : 'declined';
          if (function == 'accept_module_invitation') {
            final moduleId = invitation['module_id']?.toString();
            final registrations = rows('student_module_registrations');
            if (moduleId != null &&
                !registrations.any((row) => row['module_id'] == moduleId)) {
              registrations.add(<String, dynamic>{
                'id': newId('registration'),
                'student_id': OfflineMockData.studentId,
                'user_id': OfflineMockData.studentId,
                'module_id': moduleId,
                'programme_id': 'programme-business',
                'academic_year': DateTime.now().year,
                'semester': 1,
                'status': 'active',
                'registered_at': OfflineMockData.now,
              });
            }
          }
          break;
        }
        changed('module_invitations');
        changed('student_module_registrations');
        return null;
      case 'submit_quiz_attempt':
        final attemptId = params['p_attempt_id']?.toString();
        Map<String, dynamic>? attempt;
        for (final row in rows('quiz_attempts')) {
          if (row['id']?.toString() == attemptId) attempt = row;
        }
        attempt ??= <String, dynamic>{
          'id': attemptId ?? newId('quiz-attempt'),
          'student_id': OfflineMockData.studentId,
          'user_id': OfflineMockData.studentId,
          'quiz_id': 'quiz-demo-001',
        };
        attempt.addAll(<String, dynamic>{
          'status': 'completed',
          'percentage': 80,
          'passed': true,
          'score_points': 8,
          'total_points': 10,
          'reward_points': 10,
          'focus_violations': 0,
          'completed_at': OfflineMockData.now,
        });
        if (!rows('quiz_attempts').contains(attempt)) {
          rows('quiz_attempts').add(attempt);
        }
        changed('quiz_attempts');
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'score_points': attempt['score_points'],
            'total_points': attempt['total_points'],
            'percentage': attempt['percentage'],
            'passed': attempt['passed'],
            'reward_points': attempt['reward_points'],
            'focus_violations': attempt['focus_violations'],
          },
        ];
      case 'accept_group_invite':
        return params['p_token'] == 'DEMO-GROUP-INVITE'
            ? 'group-demo-001'
            : null;
      case 'create_group_invite':
        return <Map<String, dynamic>>[
          <String, dynamic>{'invite_token': 'DEMO-GROUP-INVITE'},
        ];
      case 'start_group_call':
      case 'upgrade_private_call_to_group':
      case 'join_group_call':
        final callId =
            params['target_call_id']?.toString() ?? newId('group-call');
        final call = <String, dynamic>{
          'id': callId,
          'group_id': params['target_group_id'],
          'room_name': 'BUS101 Study Circle',
          'call_type': params['target_call_type'] ?? 'audio',
          'started_by': OfflineMockData.studentId,
          'status': 'active',
          'created_at': OfflineMockData.now,
        };
        if (!rows('group_calls').any((row) => row['id'] == callId)) {
          rows('group_calls').add(call);
          rows('group_call_participants').add(<String, dynamic>{
            'id': newId('call-participant'),
            'call_id': callId,
            'user_id': OfflineMockData.studentId,
            'status': 'joined',
            'joined_at': OfflineMockData.now,
          });
          changed('group_calls');
          changed('group_call_participants');
        }
        return call;
      case 'create_group':
        return newId('group-chat');
      case 'end_group_call':
      case 'leave_group_call':
      case 'decline_group_call':
        final callId = params['target_call_id']?.toString();
        for (final call in rows('group_calls')) {
          if (call['id']?.toString() == callId) call['status'] = 'ended';
        }
        changed('group_calls');
        return null;
      default:
        return null;
    }
  }
}

class OfflineMockQuery implements Future<List<Map<String, dynamic>>> {
  OfflineMockQuery(this._store, this._table);

  final OfflineMockStore _store;
  final String _table;
  String? _operation;
  Object? _values;
  String? _onConflict;
  final List<_OfflineFilter> _filters = <_OfflineFilter>[];
  final List<_OfflineOrder> _orders = <_OfflineOrder>[];
  final List<String> _orExpressions = <String>[];
  int? _rangeFrom;
  int? _rangeTo;
  int? _limit;
  Future<List<Map<String, dynamic>>>? _result;

  OfflineMockQuery select([String? columns]) => this;
  OfflineMockQuery insert(Object values, {String? onConflict}) {
    _operation = 'insert';
    _values = values;
    return this;
  }

  OfflineMockQuery update(Object values, {String? onConflict}) {
    _operation = 'update';
    _values = values;
    return this;
  }

  OfflineMockQuery upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  }) {
    _operation = 'upsert';
    _values = values;
    _onConflict = onConflict;
    return this;
  }

  OfflineMockQuery delete() {
    _operation = 'delete';
    return this;
  }

  OfflineMockQuery eq(String column, Object? value) =>
      _filter(column, 'eq', value);
  OfflineMockQuery neq(String column, Object? value) =>
      _filter(column, 'neq', value);
  OfflineMockQuery gt(String column, Object? value) =>
      _filter(column, 'gt', value);
  OfflineMockQuery gte(String column, Object? value) =>
      _filter(column, 'gte', value);
  OfflineMockQuery lt(String column, Object? value) =>
      _filter(column, 'lt', value);
  OfflineMockQuery lte(String column, Object? value) =>
      _filter(column, 'lte', value);
  OfflineMockQuery inFilter(String column, List<Object?> values) =>
      _filter(column, 'in', values);
  OfflineMockQuery isFilter(String column, Object? value) =>
      _filter(column, 'eq', value);

  OfflineMockQuery _filter(String column, String operator, Object? value) {
    _filters.add(_OfflineFilter(column, operator, value));
    return this;
  }

  OfflineMockQuery match(Map<String, Object?> values) {
    for (final entry in values.entries) {
      eq(entry.key, entry.value);
    }
    return this;
  }

  OfflineMockQuery or(String expression, {String? referencedTable}) {
    _orExpressions.add(expression);
    return this;
  }

  OfflineMockQuery range(int from, int to, {String? referencedTable}) {
    _rangeFrom = from;
    _rangeTo = to;
    return this;
  }

  OfflineMockQuery order(
    String column, {
    bool ascending = true,
    Object? nullsFirst,
    String? referencedTable,
  }) {
    _orders.add(_OfflineOrder(column, ascending));
    return this;
  }

  OfflineMockQuery limit(int count, {String? referencedTable}) {
    _limit = count;
    return this;
  }

  bool _matchesOr(Map<String, dynamic> row, String expression) =>
      expression.split(',').any((alternative) {
        final match = RegExp(
          r'^([\w.]+)\.(eq|neq|is)\.(.*)$',
        ).firstMatch(alternative.trim());
        if (match == null) return false;
        final value = _mockField(row, match.group(1)!);
        final expected = match.group(3)!;
        return switch (match.group(2)) {
          'eq' => value?.toString() == expected,
          'neq' => value?.toString() != expected,
          'is' =>
            expected == 'null' ? value == null : value?.toString() == expected,
          _ => false,
        };
      });

  bool _matches(Map<String, dynamic> row) =>
      _filters.every((filter) => filter.matches(row)) &&
      (_orExpressions.isEmpty ||
          _orExpressions.any((expression) => _matchesOr(row, expression)));

  List<Map<String, dynamic>> _matchingRows() {
    final selected = _store.rows(_table).where(_matches).toList();
    selected.sort((left, right) {
      for (final order in _orders) {
        final comparison = _mockCompare(
          _mockField(left, order.column),
          _mockField(right, order.column),
        );
        if (comparison != 0) {
          return order.ascending ? comparison : -comparison;
        }
      }
      return 0;
    });
    final start = (_rangeFrom ?? 0).clamp(0, selected.length);
    final end = _rangeTo == null
        ? selected.length
        : (_rangeTo! + 1).clamp(start, selected.length);
    final ranged = selected.sublist(start, end);
    final limited = _limit == null
        ? ranged
        : ranged.take(_limit!).toList(growable: false);
    return limited.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  List<Map<String, dynamic>> _inputRows() {
    if (_values is Map) {
      return <Map<String, dynamic>>[Map<String, dynamic>.from(_values as Map)];
    }
    if (_values is Iterable) {
      return (_values as Iterable)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _withDefaults(Map<String, dynamic> values) {
    final row = <String, dynamic>{
      'id': values['id'] ?? _store.newId(_table),
      'created_at': values['created_at'] ?? OfflineMockData.now,
      ...values,
    };
    if (!row.containsKey('profiles') &&
        const <String>{
          'posts',
          'comments',
          'group_messages',
          'products',
        }.contains(_table)) {
      final userId =
          row['user_id'] ??
          row['author_id'] ??
          row['sender_id'] ??
          row['seller_id'];
      for (final profile in _store.rows('profiles')) {
        if (profile['id']?.toString() == userId?.toString()) {
          row['profiles'] = profile;
          break;
        }
      }
    }
    return row;
  }

  Future<List<Map<String, dynamic>>> _run() async {
    if (_operation == null) return _matchingRows();
    final rows = _store.rows(_table);
    final inputs = _inputRows();
    switch (_operation) {
      case 'insert':
        final inserted = inputs.map(_withDefaults).toList();
        rows.addAll(inserted);
        if (inserted.isNotEmpty) _store.changed(_table);
        return inserted.map((row) => Map<String, dynamic>.from(row)).toList();
      case 'upsert':
        final upserted = <Map<String, dynamic>>[];
        for (final input in inputs) {
          final keys = (_onConflict ?? 'id')
              .split(',')
              .map((key) => key.trim())
              .where((key) => key.isNotEmpty)
              .toList();
          Map<String, dynamic>? existing;
          for (final candidate in rows) {
            if (keys.every((key) => candidate[key] == input[key])) {
              existing = candidate;
              break;
            }
          }
          if (existing == null) {
            final inserted = _withDefaults(input);
            rows.add(inserted);
            upserted.add(inserted);
          } else {
            existing.addAll(input);
            upserted.add(existing);
          }
        }
        if (upserted.isNotEmpty) _store.changed(_table);
        return upserted.map((row) => Map<String, dynamic>.from(row)).toList();
      case 'update':
        final input = _inputRows();
        final patch = input.isEmpty ? <String, dynamic>{} : input.first;
        final updated = <Map<String, dynamic>>[];
        for (final row in rows) {
          if (_matches(row)) {
            row.addAll(patch);
            updated.add(Map<String, dynamic>.from(row));
          }
        }
        if (updated.isNotEmpty) _store.changed(_table);
        return updated;
      case 'delete':
        final removed = rows.where(_matches).toList();
        rows.removeWhere(_matches);
        if (removed.isNotEmpty) _store.changed(_table);
        return removed.map((row) => Map<String, dynamic>.from(row)).toList();
      default:
        return _matchingRows();
    }
  }

  Future<List<Map<String, dynamic>>> _future() => _result ??= _run();

  Future<Map<String, dynamic>?> maybeSingle() async {
    final rows = await _future();
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> single() async {
    final rows = await _future();
    return rows.isEmpty ? <String, dynamic>{} : rows.first;
  }

  OfflineMockStreamQuery stream({List<String>? primaryKey}) =>
      OfflineMockStreamQuery(_table, _store, _matchingRows);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) => _future().then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _future().catchError(onError, test: test);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => _future().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => _future().whenComplete(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class _OfflineFilter {
  const _OfflineFilter(this.column, this.operator, this.value);
  final String column;
  final String operator;
  final Object? value;

  bool matches(Map<String, dynamic> row) {
    final actual = _mockField(row, column);
    switch (operator) {
      case 'eq':
        return _mockEqual(actual, value);
      case 'neq':
        return !_mockEqual(actual, value);
      case 'gt':
        return _mockCompare(actual, value) > 0;
      case 'gte':
        return _mockCompare(actual, value) >= 0;
      case 'lt':
        return _mockCompare(actual, value) < 0;
      case 'lte':
        return _mockCompare(actual, value) <= 0;
      case 'in':
        final candidates = value;
        return candidates is Iterable &&
            candidates.any((candidate) => _mockEqual(actual, candidate));
      default:
        return true;
    }
  }
}

class _OfflineOrder {
  const _OfflineOrder(this.column, this.ascending);
  final String column;
  final bool ascending;
}

dynamic _mockField(Map<String, dynamic> row, String column) {
  if (row.containsKey(column)) return row[column];
  dynamic value = row;
  for (final part in column.split('.')) {
    if (value is! Map) return null;
    value = value[part];
  }
  return value;
}

bool _mockEqual(Object? left, Object? right) =>
    left == right ||
    (left != null && right != null && left.toString() == right.toString());

int _mockCompare(Object? left, Object? right) {
  if (left == null && right == null) return 0;
  if (left == null) return -1;
  if (right == null) return 1;
  final leftNumber = num.tryParse(left.toString());
  final rightNumber = num.tryParse(right.toString());
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  final leftDate = DateTime.tryParse(left.toString());
  final rightDate = DateTime.tryParse(right.toString());
  if (leftDate != null && rightDate != null) {
    return leftDate.compareTo(rightDate);
  }
  return left.toString().compareTo(right.toString());
}

class OfflineMockStreamQuery {
  OfflineMockStreamQuery(this._table, this._store, this._read);
  final String _table;
  final OfflineMockStore _store;
  final List<Map<String, dynamic>> Function() _read;
  final List<_OfflineFilter> _filters = <_OfflineFilter>[];
  final List<_OfflineOrder> _orders = <_OfflineOrder>[];

  OfflineMockStreamQuery eq(String column, Object? value) {
    _filters.add(_OfflineFilter(column, 'eq', value));
    return this;
  }

  OfflineMockStreamQuery order(String column, {bool ascending = true}) {
    _orders.add(_OfflineOrder(column, ascending));
    return this;
  }

  List<Map<String, dynamic>> _snapshot() {
    final rows = _read()
        .where((row) => _filters.every((filter) => filter.matches(row)))
        .toList();
    rows.sort((left, right) {
      for (final order in _orders) {
        final compared = _mockCompare(
          _mockField(left, order.column),
          _mockField(right, order.column),
        );
        if (compared != 0) return order.ascending ? compared : -compared;
      }
      return 0;
    });
    return rows;
  }

  Stream<List<Map<String, dynamic>>> _stream() async* {
    yield _snapshot();
    await for (final table in _store.changes) {
      if (table == _table) yield _snapshot();
    }
  }

  StreamSubscription<List<Map<String, dynamic>>> listen(
    void Function(List<Map<String, dynamic>> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class OfflineRpcQuery implements Future<dynamic> {
  OfflineRpcQuery(this._store, this._function, this._params);
  final OfflineMockStore _store;
  final String _function;
  final Map<String, dynamic> _params;
  Future<dynamic>? _result;
  Future<dynamic> _future() => _result ??= _store.runRpc(_function, _params);

  @override
  Stream<dynamic> asStream() => _future().asStream();

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) => _future().then(onValue, onError: onError);

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _future().catchError(onError, test: test);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) => _future().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _future().whenComplete(action);
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
  }) => this;
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
  }) => this;
  OfflineQuery limit(int count, {String? referencedTable}) => this;
  OfflineQuery isFilter(String column, Object? value) => this;

  Future<Map<String, dynamic>?> maybeSingle() async => null;
  Future<Map<String, dynamic>> single() async => <String, dynamic>{};
  OfflineStreamQuery stream({List<String>? primaryKey}) => OfflineStreamQuery();

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) => Future<List<Map<String, dynamic>>>.value(
    _empty,
  ).then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => Future<List<Map<String, dynamic>>>.value(
    _empty,
  ).catchError(onError, test: test);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => Future<List<Map<String, dynamic>>>.value(
    _empty,
  ).timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future<List<Map<String, dynamic>>>.value(_empty).whenComplete(action);

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
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  dynamic noSuchMethod(Invocation invocation) => this;
}

class OfflineAuthClient {
  OfflineAuthClient()
    : _user = OfflineUser(
        id: OfflineMockData.studentId,
        email: 'thando.student@example.test',
        createdAt: '2026-01-01T00:00:00Z',
        emailConfirmedAt: DateTime.utc(2026),
        userMetadata: const <String, dynamic>{
          'name': 'Thando',
          'surname': 'Mokoena',
          'nickname': 'Thando',
          'role': 'student',
        },
      );

  OfflineUser? _user;
  final StreamController<OfflineAuthState> _changes =
      StreamController<OfflineAuthState>.broadcast(sync: true);

  OfflineUser? get currentUser => _user;
  OfflineSession? get currentSession =>
      _user == null ? null : OfflineSession(user: _user);

  Stream<OfflineAuthState> get onAuthStateChange async* {
    yield OfflineAuthState(
      event: OfflineAuthChangeEvent.initialSession,
      session: currentSession,
    );
    yield* _changes.stream;
  }

  Future<void> signOut() async {
    _user = null;
    _changes.add(
      const OfflineAuthState(event: OfflineAuthChangeEvent.signedOut),
    );
  }

  Future<void> reauthenticate() async {}

  Future<void> updateUser(OfflineUserAttributes attributes) async {
    final oldUser = _user;
    if (oldUser == null) return;
    _user = OfflineUser(
      id: oldUser.id,
      email: oldUser.email,
      phone: oldUser.phone,
      createdAt: oldUser.createdAt,
      emailConfirmedAt: oldUser.emailConfirmedAt,
      userMetadata: <String, dynamic>{
        ...?oldUser.userMetadata,
        ...?attributes.data,
      },
    );
    _changes.add(
      OfflineAuthState(
        event: OfflineAuthChangeEvent.userUpdated,
        session: currentSession,
      ),
    );
  }

  Future<OfflineAuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _user = OfflineUser(
      id: OfflineMockData.studentId,
      email: email,
      createdAt: '2026-01-01T00:00:00Z',
      emailConfirmedAt: DateTime.utc(2026),
      userMetadata: const <String, dynamic>{
        'name': 'Thando',
        'surname': 'Mokoena',
        'nickname': 'Thando',
        'role': 'student',
      },
    );
    final session = currentSession;
    _changes.add(
      OfflineAuthState(
        event: OfflineAuthChangeEvent.signedIn,
        session: session,
      ),
    );
    return OfflineAuthResponse(user: _user, session: session);
  }
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
  OfflineStorageClient(this._store);
  final OfflineMockStore _store;
  OfflineStorageBucket from(String bucket) =>
      OfflineStorageBucket(_store, bucket);
}

class OfflineStorageBucket {
  OfflineStorageBucket(this._store, this._bucket);
  final OfflineMockStore _store;
  final String _bucket;

  String getPublicUrl(String path) => 'mock://$_bucket/$path';
  Future<String> createSignedUrl(String path, int expirySeconds) async =>
      'mock://$_bucket/$path?expires=$expirySeconds';

  Future<String> uploadBinary(
    String path,
    Uint8List bytes, {
    OfflineFileOptions? fileOptions,
  }) async {
    _store.files['$_bucket/$path'] = Uint8List.fromList(bytes);
    return path;
  }

  Future<String> upload(
    String path,
    Object file, {
    OfflineFileOptions? fileOptions,
  }) async {
    _store.files['$_bucket/$path'] = Uint8List.fromList(
      utf8.encode('Mock file: $file'),
    );
    return path;
  }

  Future<Uint8List> download(String path) async =>
      _store.files['$_bucket/$path'] ??
      Uint8List.fromList(utf8.encode('Local mock document: $path'));

  Future<void> remove(List<String> paths) async {
    for (final path in paths) {
      _store.files.remove('$_bucket/$path');
    }
  }

  Future<void> move(String from, String to) async {
    final data = _store.files.remove('$_bucket/$from');
    if (data != null) _store.files['$_bucket/$to'] = data;
  }

  Future<List<Map<String, dynamic>>> list([String path = '']) async => _store
      .files
      .keys
      .where((key) => key.startsWith('$_bucket/$path'))
      .map(
        (key) => <String, dynamic>{
          'name': key.split('/').last,
          'id': key,
          'metadata': <String, dynamic>{'size': _store.files[key]!.length},
        },
      )
      .toList(growable: false);
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
  }) async => function == 'get-turn-credentials'
      ? const OfflineFunctionResponse(
          data: <String, dynamic>{'iceServers': <dynamic>[]},
          status: 200,
        )
      : const OfflineFunctionResponse(
          data: <String, dynamic>{'ok': true, 'mock': true},
          status: 200,
        );
}

class OfflineFunctionResponse {
  const OfflineFunctionResponse({this.data, this.status = 200});
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
  }) => this;

  OfflineRealtimeChannel onBroadcast({
    required String event,
    required void Function(dynamic payload) callback,
  }) => this;

  OfflineRealtimeChannel onPresenceSync(
    void Function(dynamic payload) callback,
  ) => this;
  OfflineRealtimeChannel onPresenceJoin(
    void Function(dynamic payload) callback,
  ) => this;
  OfflineRealtimeChannel onPresenceLeave(
    void Function(dynamic payload) callback,
  ) => this;

  OfflineRealtimeChannel subscribe([
    void Function(OfflineRealtimeSubscribeStatus status, Object? error)?
    callback,
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

enum OfflineRealtimeSubscribeStatus {
  subscribed,
  channelError,
  timedOut,
  closed,
}

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
