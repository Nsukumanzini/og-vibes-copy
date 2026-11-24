import 'dart:ui';
import '../widgets/glass_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/og_assistant_service.dart';
import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class OgAssistantScreen extends StatefulWidget {
  const OgAssistantScreen({super.key});

  @override
  State<OgAssistantScreen> createState() => _OgAssistantScreenState();
}

class _OgAssistantScreenState extends State<OgAssistantScreen> {
  final _service = const OgAssistantService();
  final _questionController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AssistantTurn> _turns = [];
  List<_StudentModule> _modules = const [
    _StudentModule(
      id: 'module-bus101',
      name: 'Introduction to Business Management',
      code: 'BUS101',
    ),
    _StudentModule(
      id: 'module-com101',
      name: 'Communication Skills',
      code: 'COM101',
    ),
  ];
  String? _selectedModuleId;
  bool _loadingModules = false;
  bool _searching = false;

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ask([String? suggestedQuestion]) async {
    if (_searching) return;
    if (suggestedQuestion != null) {
      _questionController.text = suggestedQuestion;
    }
    final question = _questionController.text.trim();
    if (question.length < 3) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _questionController.clear();
    });
    try {
      final sources = await _service.search(
        question,
        moduleId: _selectedModuleId,
      );
      if (!mounted) return;
      setState(
        () => _turns.add(_AssistantTurn(question: question, sources: sources)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _turns.add(
          _AssistantTurn(
            question: question,
            error: 'The local study library could not be searched: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _searching = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    }
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.vibeBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('OG Assistant'),
                Text(
                  'STUDY SPACE',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            onPressed: _turns.isEmpty ? null : () => setState(_turns.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              children: [
                if (_turns.isEmpty) ...[
                  _buildHero(),
                  const SizedBox(height: 16),
                ],
                _buildModuleFilter(),
                SizedBox(height: _turns.isEmpty ? 20 : 14),
                if (_turns.isEmpty)
                  _buildWelcome()
                else
                  ..._turns.map(_buildTurn),
                if (_searching) _buildSearching(),
              ],
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102B58), Color(0xFF1557C0), Color(0xFF3978E9)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              const _LocalDemoBadge(),
              const Spacer(),
              Icon(
                Icons.school_rounded,
                color: Colors.white.withValues(alpha: .38),
                size: 27,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Study smarter,\none passage at a time.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              height: 1.12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Search local sample notes and find useful passages for your next study session.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleFilter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppStyles.glassShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppColors.vibeBlue,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEARCH WITHIN',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                _loadingModules
                    ? const LinearProgressIndicator(minHeight: 3)
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedModuleId,
                          isExpanded: true,
                          isDense: true,
                          hint: const Text('All available modules'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All available modules'),
                            ),
                            ..._modules.map(
                              (module) => DropdownMenuItem<String?>(
                                value: module.id,
                                child: Text(
                                  module.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedModuleId = value);
                          },
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.tune_rounded, color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    const prompts = <({IconData icon, String title, String prompt})>[
      (
        icon: Icons.lightbulb_outline_rounded,
        title: 'Explain a concept',
        prompt: 'Define the main concept from the latest lecture',
      ),
      (
        icon: Icons.manage_search_rounded,
        title: 'Find a topic',
        prompt: 'Find the section that explains this topic',
      ),
      (
        icon: Icons.assignment_outlined,
        title: 'Past-paper help',
        prompt: 'Show me relevant past-paper guidance',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'What are you\nworking on today?',
                style: TextStyle(
                  fontSize: 23,
                  height: 1.14,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.ogGold.withValues(alpha: .15),
                borderRadius: AppStyles.pillRadius,
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.offline_bolt_rounded,
                    size: 13,
                    color: AppColors.deepBlue,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'OFFLINE',
                    style: TextStyle(
                      color: AppColors.deepBlue,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Try one of these to get started',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 15),
        ...prompts.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .88),
              borderRadius: BorderRadius.circular(19),
              child: InkWell(
                borderRadius: BorderRadius.circular(19),
                onTap: () => _ask(item.prompt),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: AppStyles.glassShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.vibeBlue.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          item.icon,
                          color: AppColors.vibeBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.prompt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: AppColors.vibeBlue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const _ResultNotice(
          icon: Icons.info_outline_rounded,
          color: AppColors.deepBlue,
          text:
              'This offline version searches sample study notes stored in the app. No sign-in or internet is needed.',
        ),
      ],
    );
  }

  Widget _buildTurn(_AssistantTurn turn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.vibeBlue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(
                turn.question,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (turn.error != null)
            _ResultNotice(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              text: turn.error!,
            )
          else if (turn.sources.isEmpty)
            const _ResultNotice(
              icon: Icons.manage_search_rounded,
              color: AppColors.warning,
              text:
                  'No matching sample passage found. Try different wording or another available module.',
            )
          else ...[
            _ResultNotice(
              icon: Icons.fact_check_rounded,
              color: AppColors.success,
              text:
                  'Found ${turn.sources.length} matching ${turn.sources.length == 1 ? 'passage' : 'passages'} in the sample study library.',
            ),
            const SizedBox(height: 9),
            ...turn.sources.asMap().entries.map(
              (entry) =>
                  _SourceCard(number: entry.key + 1, source: entry.value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearching() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: _GlassPanel(
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Searching sample study passages…',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
            border: const Border(top: BorderSide(color: AppColors.glassBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 3, bottom: 8),
                  child: Text(
                    'ASK YOUR STUDY LIBRARY',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questionController,
                        enabled: !_searching,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _ask(),
                        decoration: InputDecoration(
                          hintText: 'Ask a question or search a topic…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: AppColors.vibeBlue.withValues(alpha: .055),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 15,
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: AppColors.glassBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: AppColors.vibeBlue,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: IconButton.filled(
                        tooltip: 'Search study library',
                        onPressed: !_searching ? _ask : null,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.vibeBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentModule {
  const _StudentModule({
    required this.id,
    required this.name,
    required this.code,
  });

  final String id;
  final String name;
  final String code;

  String get label => code.isEmpty ? name : '$code • $name';
}

class _AssistantTurn {
  const _AssistantTurn({
    required this.question,
    this.sources = const [],
    this.error,
  });

  final String question;
  final List<OgAssistantSource> sources;
  final String? error;
}

class _LocalDemoBadge extends StatelessWidget {
  const _LocalDemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ogGold,
        borderRadius: AppStyles.pillRadius,
      ),
      child: const Text(
        'LOCAL DEMO',
        style: TextStyle(
          color: AppColors.deepBlue,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(15),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      GlassPanel(padding: padding, child: child);
}

class _ResultNotice extends StatelessWidget {
  const _ResultNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.number, required this.source});

  final int number;
  final OgAssistantSource source;

  @override
  Widget build(BuildContext context) {
    final confidence = (source.similarity * 100).clamp(0, 100).round();
    final module = source.moduleCode.isEmpty
        ? source.moduleName
        : '${source.moduleCode} • ${source.moduleName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppStyles.glassShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.vibeBlue.withValues(alpha: .09),
                    borderRadius: AppStyles.pillRadius,
                  ),
                  child: Text(
                    'PASSAGE $number',
                    style: const TextStyle(
                      color: AppColors.vibeBlue,
                      fontSize: 9,
                      letterSpacing: .5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.bolt_rounded,
                  size: 15,
                  color: AppColors.ogGold,
                ),
                const SizedBox(width: 3),
                Text(
                  '$confidence% match',
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              source.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _MetaChip(icon: Icons.school_outlined, label: module),
                _MetaChip(
                  icon: Icons.description_outlined,
                  label: 'Page ${source.pageNumber}',
                ),
              ],
            ),
            const SizedBox(height: 13),
            Container(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .045),
                borderRadius: BorderRadius.circular(15),
                border: const Border(
                  left: BorderSide(color: AppColors.ogGold, width: 3),
                ),
              ),
              child: SelectableText(
                source.content,
                style: const TextStyle(height: 1.55),
              ),
            ),
            const SizedBox(height: 9),
            const Row(
              children: [
                Icon(
                  Icons.offline_bolt_rounded,
                  size: 13,
                  color: AppColors.textMuted,
                ),
                SizedBox(width: 5),
                Text(
                  'Sample passage from the offline library',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.vibeBlue.withValues(alpha: .08),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.vibeBlue),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
