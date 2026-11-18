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

/// Deterministic academic passages for the offline build.
class OgAssistantService {
  const OgAssistantService();

  static const _sources = <OgAssistantSource>[
    OgAssistantSource(
      documentId: 'mock-bus101-management',
      title: 'Management foundations',
      moduleName: 'Introduction to Business Management',
      moduleCode: 'BUS101',
      sourceType: 'Lecture notes',
      pageNumber: 2,
      content:
          'Management is the process of planning, organising, leading, and controlling resources to achieve an organisation’s goals. Managers coordinate people, information, and materials while responding to changes in the organisation’s environment.',
      similarity: 0.94,
      storagePath: 'mock/BUS101-management-notes.pdf',
    ),
    OgAssistantSource(
      documentId: 'mock-bus101-planning',
      title: 'Planning and decision making',
      moduleName: 'Introduction to Business Management',
      moduleCode: 'BUS101',
      sourceType: 'Lecture notes',
      pageNumber: 4,
      content:
          'Planning sets objectives and identifies actions, responsibilities, and resources. A useful plan states the intended outcome, considers available options, and includes a way to review progress.',
      similarity: 0.82,
      storagePath: 'mock/BUS101-management-notes.pdf',
    ),
    OgAssistantSource(
      documentId: 'mock-com101-communication',
      title: 'Principles of clear communication',
      moduleName: 'Communication Skills',
      moduleCode: 'COM101',
      sourceType: 'Study notes',
      pageNumber: 1,
      content:
          'Effective communication uses a clear purpose, an appropriate channel, and language suited to the audience. Feedback helps the sender check that the message was understood.',
      similarity: 0.86,
      storagePath: 'mock/COM101-communication-notes.pdf',
    ),
  ];

  Future<List<OgAssistantSource>> search(
    String question, {
    String? moduleId,
  }) async {
    final terms = question
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((term) => term.length > 2)
        .toSet();
    if (terms.isEmpty) return const [];
    final ranked =
        _sources
            .where(
              (source) =>
                  moduleId == null ||
                  moduleId.isEmpty ||
                  (moduleId == 'module-bus101' &&
                      source.moduleCode == 'BUS101') ||
                  (moduleId == 'module-com101' &&
                      source.moduleCode == 'COM101'),
            )
            .map((source) {
              final text =
                  '${source.title} ${source.moduleName} ${source.content}'
                      .toLowerCase();
              final matches = terms.where(text.contains).length;
              return (source: source, matches: matches);
            })
            .where((item) => item.matches > 0)
            .toList()
          ..sort((a, b) => b.matches.compareTo(a.matches));
    return ranked.take(3).map((item) => item.source).toList();
  }

  Future<String> createSourceUrl(OgAssistantSource source) async => '';
}
