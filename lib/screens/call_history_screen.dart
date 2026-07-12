import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<Map<String, dynamic>> _calls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCalls();
  }

  Future<void> _loadCalls() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final response = await Supabase.instance.client
        .from('calls')
        .select()
        .or('caller_id.eq.$userId,callee_id.eq.$userId')
        .order('started_at', ascending: false);

    setState(() {
      _calls = (response as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call history')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
              ? const Center(child: Text('No calls yet.'))
              : ListView.builder(
                  itemCount: _calls.length,
                  itemBuilder: (context, index) {
                    final call = _calls[index];
                    return ListTile(
                      title: Text(call['status']?.toString() ?? 'Unknown'),
                      subtitle: Text('Type: ${call['type'] ?? 'audio'} • ${call['started_at'] ?? ''}'),
                      trailing: Text(call['status'] ?? ''),
                    );
                  },
                ),
    );
  }
}
