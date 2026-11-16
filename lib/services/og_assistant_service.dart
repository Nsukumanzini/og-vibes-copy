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
}

/// The assistant has no remote search provider in the offline build.
class OgAssistantService {
  const OgAssistantService();

  Future<List<OgAssistantSource>> search(String question, {String? moduleId}) async =>
      const [];

  Future<String> createSourceUrl(OgAssistantSource source) async => '';
}
