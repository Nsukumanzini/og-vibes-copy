import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/og_assistant_service.dart';
import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'pdf_viewer_screen.dart';

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
  List<_StudentModule> _modules = const [];
  String? _selectedModuleId;
  bool _loadingModules = true;
  bool _searching = false;

  bool get _signedIn => Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _loadModules();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadModules() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingModules = false);
      return;
    }
    try {
      final raw =
          await Supabase.instance.client
                  .from('student_module_registrations')
                  .select(
                    'module_id, modules!student_module_registrations_module_id_fkey(id,name,code)',
                  )
                  .eq('student_id', user.id)
                  .eq('status', 'active')
              as List<dynamic>;
      final modules = raw
          .whereType<Map>()
          .map((row) => _StudentModule.fromRow(Map<String, dynamic>.from(row)))
          .where((module) => module.id.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _loadingModules = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingModules = false);
    }
  }

  Future<void> _ask([String? suggestedQuestion]) async {
    if (_searching || !_signedIn) return;
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
          _AssistantTurn(question: question, error: _friendlyError(error)),
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

  Future<void> _openSource(OgAssistantSource source) async {
    try {
      final url = await _service.createSourceUrl(source);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(url: url, title: source.title),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  String _friendlyError(Object error) {
    if (error is AuthException) return 'Sign in to use OG Assistant.';
    if (error is FormatException) return error.message;
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('Failed host lookup') ||
        text.contains('SocketException')) {
      return 'Connect to the internet to search your approved material.';
    }
    return text.isEmpty ? 'OG Assistant is temporarily unavailable.' : text;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : AppColors.midnightInk;
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('OG Assistant'),
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
                _buildHero(),
                const SizedBox(height: 14),
                _buildModuleFilter(),
                const SizedBox(height: 14),
                if (!_signedIn)
                  _buildSignInCard()
                else if (_turns.isEmpty)
                  _buildWelcome(foreground)
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.vibeBlue.withValues(alpha: 0.2),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'OG Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 7),
                    _GroundedBadge(),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Answers extracted only from approved academic material.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleFilter() {
    return _GlassPanel(
      child: Row(
        children: [
          const Icon(Icons.school_rounded, color: AppColors.vibeBlue),
          const SizedBox(width: 12),
          Expanded(
            child: _loadingModules
                ? const LinearProgressIndicator(minHeight: 3)
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedModuleId,
                      isExpanded: true,
                      hint: const Text('Search all my modules'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All my modules'),
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
          ),
        ],
      ),
    );
  }

  Widget _buildSignInCard() {
    return const _GlassPanel(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.lock_person_rounded, size: 44, color: AppColors.vibeBlue),
          SizedBox(height: 12),
          Text(
            'Sign in required',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 7),
          Text(
            'Your account determines which registered-module material OG Assistant may search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(Color foreground) {
    const prompts = <String>[
      'Define the main concept from the latest lecture',
      'Find the section that explains this topic',
      'Show me relevant past-paper guidance',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ResultNotice(
          icon: Icons.verified_user_rounded,
          color: AppColors.success,
          text:
              'No web results and no invented answers. If the approved documents do not support an answer, I will tell you.',
        ),
        const SizedBox(height: 18),
        Text(
          'TRY ASKING',
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 9),
        ...prompts.map(
          (prompt) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _ask(prompt),
              child: _GlassPanel(
                child: Row(
                  children: [
                    const Icon(
                      Icons.north_east_rounded,
                      size: 19,
                      color: AppColors.vibeBlue,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        prompt,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                  'I could not find a supported answer in your approved academic material. Try different wording or ask your lecturer to upload more material.',
            )
          else ...[
            _ResultNotice(
              icon: Icons.fact_check_rounded,
              color: AppColors.success,
              text:
                  'I found ${turn.sources.length} supported ${turn.sources.length == 1 ? 'passage' : 'passages'}. The strongest match appears first.',
            ),
            const SizedBox(height: 9),
            ...turn.sources.asMap().entries.map(
              (entry) => _SourceCard(
                number: entry.key + 1,
                source: entry.value,
                onOpen: () => _openSource(entry.value),
              ),
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
                'Searching approved material…',
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.88),
            border: const Border(top: BorderSide(color: AppColors.glassBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    enabled: _signedIn && !_searching,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: const InputDecoration(
                      hintText: 'Ask from your academic material…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                IconButton.filled(
                  tooltip: 'Search approved material',
                  onPressed: _signedIn && !_searching ? _ask : null,
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  icon: const Icon(Icons.arrow_upward_rounded),
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

  factory _StudentModule.fromRow(Map<String, dynamic> row) {
    final module = row['modules'] is Map
        ? Map<String, dynamic>.from(row['modules'] as Map)
        : <String, dynamic>{};
    return _StudentModule(
      id: (module['id'] ?? row['module_id'])?.toString() ?? '',
      name: module['name']?.toString() ?? 'Module',
      code: module['code']?.toString() ?? '',
    );
  }
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

class _GroundedBadge extends StatelessWidget {
  const _GroundedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: AppStyles.pillRadius,
      ),
      child: const Text(
        'GROUNDED',
        style: TextStyle(
          color: Colors.white,
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
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: padding, child: child),
    );
  }
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
  const _SourceCard({
    required this.number,
    required this.source,
    required this.onOpen,
  });

  final int number;
  final OgAssistantSource source;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final confidence = (source.similarity * 100).clamp(0, 100).round();
    final module = source.moduleCode.isEmpty
        ? source.moduleName
        : '${source.moduleCode} • ${source.moduleName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _GlassPanel(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.vibeBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    source.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '$confidence%',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
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
            SelectableText(
              source.content,
              style: const TextStyle(height: 1.55),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text('Open page ${source.pageNumber}'),
              ),
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
