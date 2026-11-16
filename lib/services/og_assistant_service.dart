import 'package:supabase_flutter/supabase_flutter.dart';

class OgAssistantSource {
  const OgAssistantSource({
    required this.documentId,
    required this.title,
    required this.moduleName,
    required this.moduleCode,
    required this.sourceType,
    required this.pageNumber,
    required this.content,
    required this.similarity,
    required this.storagePath,
  });

  final String documentId;
  final String title;
  final String moduleName;
  final String moduleCode;
  final String sourceType;
  final int pageNumber;
  final String content;
  final double similarity;
  final String storagePath;

  factory OgAssistantSource.fromJson(Map<String, dynamic> json) {
    return OgAssistantSource(
      documentId: json['document_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Academic material',
      moduleName: json['module_name']?.toString() ?? 'Module',
      moduleCode: json['module_code']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? 'document',
      pageNumber: (json['page_number'] as num?)?.toInt() ?? 1,
      content: json['content']?.toString().trim() ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      storagePath: json['storage_path']?.toString() ?? '',
    );
  }
}

class OgAssistantService {
  const OgAssistantService();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<OgAssistantSource>> search(
    String question, {
    String? moduleId,
  }) async {
    final normalized = question.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_client.auth.currentUser == null) {
      throw const AuthException('Sign in to use OG Assistant.');
    }
    if (normalized.length < 3) {
      throw const FormatException('Enter a complete study question.');
    }

    final response = await _client.functions.invoke(
      'og-assistant-search',
      body: <String, dynamic>{
        'question': normalized,
        if (moduleId?.isNotEmpty == true) 'moduleId': moduleId,
        'limit': 6,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw StateError(message ?? 'OG Assistant search is unavailable.');
    }

    final data = response.data;
    if (data is! Map) return const [];
    final rawResults = data['results'];
    if (rawResults is! List) return const [];
    return rawResults
        .whereType<Map>()
        .map(
          (row) => OgAssistantSource.fromJson(Map<String, dynamic>.from(row)),
        )
        .where((source) => source.content.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> createSourceUrl(OgAssistantSource source) async {
    if (source.storagePath.isEmpty) {
      throw StateError('This source file is not available.');
    }
    return _client.storage
        .from('academic-content')
        .createSignedUrl(source.storagePath, 3600);
  }
}
