import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'chat_detail_screen.dart';

class LostAndFoundScreen extends StatefulWidget {
  const LostAndFoundScreen({super.key});

  @override
  State<LostAndFoundScreen> createState() => _LostAndFoundScreenState();
}

class _LostAndFoundScreenState extends State<LostAndFoundScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final List<LostFoundReport> _reports = <LostFoundReport>[];
  final List<LostFoundClaim> _claims = <LostFoundClaim>[];

  late final TabController _tabController;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging && mounted) setState(() {});
      });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final user = _user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign in to use Lost & Found.';
      });
      return;
    }

    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _refreshing = true);
    }

    try {
      final responses = await Future.wait<dynamic>(<Future<dynamic>>[
        _supabase
            .from('lost_and_found_items')
            .select(
              'id, user_id, title, found_at, collect_at, requirements, '
              'image_url, image_path, status, report_type, description, '
              'category, incident_at, claim_question, reward_text, created_at, '
              'updated_at',
            )
            .order('created_at', ascending: false),
        _supabase
            .from('lost_and_found_claims')
            .select(
              'id, item_id, claimant_id, verification_answer, status, '
              'owner_note, created_at, responded_at',
            )
            .order('created_at', ascending: false),
      ]);

      final reportRows = List<Map<String, dynamic>>.from(
        responses[0] as List<dynamic>,
      );
      final signedUrls = <String, String>{};
      await Future.wait<void>(
        reportRows.map((row) async {
          final path = _optional(row['image_path']);
          if (path == null || signedUrls.containsKey(path)) return;
          try {
            signedUrls[path] = await _supabase.storage
                .from('lost-and-found')
                .createSignedUrl(path, 60 * 60);
          } catch (_) {
            // A report remains usable even when an old image is unavailable.
          }
        }),
      );

      final reports = reportRows
          .map((row) => LostFoundReport.fromRow(row, signedUrls))
          .toList();
      final claims = List<Map<String, dynamic>>.from(
        responses[1] as List<dynamic>,
      ).map(LostFoundClaim.fromRow).toList();

      if (!mounted) return;
      setState(() {
        _reports
          ..clear()
          ..addAll(reports);
        _claims
          ..clear()
          ..addAll(claims);
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = _friendlyError(error);
      });
    }
  }

  List<LostFoundReport> _reportsForTab(int index) {
    final userId = _user?.id;
    return _reports.where((report) {
      if (index == 2) return report.userId == userId;
      if (report.status == 'archived') return false;
      return report.reportType == (index == 0 ? 'lost' : 'found');
    }).toList();
  }

  List<LostFoundClaim> _claimsFor(String itemId) =>
      _claims.where((claim) => claim.itemId == itemId).toList();

  LostFoundClaim? _myClaimFor(String itemId) {
    final userId = _user?.id;
    for (final claim in _claims) {
      if (claim.itemId == itemId && claim.claimantId == userId) return claim;
    }
    return null;
  }

  int get _lostCount => _reports
      .where((report) => report.reportType == 'lost' && report.isDiscoverable)
      .length;
  int get _foundCount => _reports
      .where((report) => report.reportType == 'found' && report.isDiscoverable)
      .length;
  int get _returnedCount =>
      _reports.where((report) => report.status == 'returned').length;
  int get _myReportCount =>
      _reports.where((report) => report.userId == _user?.id).length;

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Lost & Found'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _refreshing ? null : () => _loadData(showLoader: false),
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Report a lost or found item',
        child: FloatingActionButton.extended(
          onPressed: _openReportWizard,
          backgroundColor: AppColors.vibeBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text(
            'Report item',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppStyles.auroraGradient),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _loadData)
            : RefreshIndicator(
                onRefresh: () => _loadData(showLoader: false),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      sliver: SliverToBoxAdapter(child: _buildHero()),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabsHeaderDelegate(child: _buildTabs()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
                      sliver: _buildReportGrid(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHero() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hero = Container(
      constraints: const BoxConstraints(minHeight: 210),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            right: -26,
            top: -34,
            child: _HeroOrb(size: 150, color: AppColors.electricCyan),
          ),
          const Positioned(
            right: 72,
            bottom: -52,
            child: _HeroOrb(size: 120, color: AppColors.ogGold),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: AppStyles.pillRadius,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.volunteer_activism_outlined,
                      color: AppColors.ogGold,
                      size: 16,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'OG COMMUNITY CARE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'Let’s get it back home.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Report carefully, verify privately, reconnect safely.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _HeroMetric(
                    icon: Icons.search_rounded,
                    value: '$_lostCount',
                    label: 'Lost',
                  ),
                  _HeroMetric(
                    icon: Icons.inventory_2_outlined,
                    value: '$_foundCount',
                    label: 'Found',
                  ),
                  _HeroMetric(
                    icon: Icons.favorite_rounded,
                    value: '$_returnedCount',
                    label: 'Returned',
                    highlight: true,
                  ),
                  _HeroMetric(
                    icon: Icons.person_outline_rounded,
                    value: '$_myReportCount',
                    label: 'Mine',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return reduceMotion
        ? hero
        : hero.animate().fadeIn(duration: 420.ms).slideY(begin: .05, end: 0);
  }

  Widget _buildTabs() {
    return Container(
      color: AppColors.auroraCanvas.withValues(alpha: .94),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: ClipRRect(
        borderRadius: AppStyles.controlRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .82),
              borderRadius: AppStyles.controlRadius,
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppStyles.softShadow,
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: AppStyles.brandGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              onTap: (_) {
                HapticFeedback.selectionClick();
                setState(() {});
              },
              tabs: const <Tab>[
                Tab(icon: Icon(Icons.search_rounded, size: 18), text: 'Lost'),
                Tab(
                  icon: Icon(Icons.inventory_2_outlined, size: 18),
                  text: 'Found',
                ),
                Tab(
                  icon: Icon(Icons.person_outline_rounded, size: 18),
                  text: 'My Reports',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportGrid() {
    final reports = _reportsForTab(_tabController.index);
    if (reports.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          isMine: _tabController.index == 2,
          type: _tabController.index == 0 ? 'lost' : 'found',
          onReport: _openReportWizard,
        ),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width >= 1080
            ? 3
            : width >= 680
            ? 2
            : 1;
        final aspectRatio = columns == 1 ? 1.45 : 1.02;
        return SliverGrid(
          delegate: SliverChildBuilderDelegate((context, index) {
            final report = reports[index];
            final card = _ReportCard(
              report: report,
              mine: report.userId == _user?.id,
              claim: _myClaimFor(report.id),
              claimCount: _claimsFor(report.id).length,
              onTap: () => _showReportDetails(report),
            );
            if (MediaQuery.disableAnimationsOf(context)) return card;
            return card
                .animate(delay: (45 * (index % 6)).ms)
                .fadeIn(duration: 320.ms)
                .slideY(begin: .06, end: 0);
          }, childCount: reports.length),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: aspectRatio,
          ),
        );
      },
    );
  }

  Future<void> _showReportDetails(LostFoundReport report) async {
    HapticFeedback.selectionClick();
    final mine = report.userId == _user?.id;
    final myClaim = _myClaimFor(report.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .84,
        minChildSize: .58,
        maxChildSize: .96,
        expand: false,
        builder: (context, controller) => Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: <Widget>[
              _DetailPhoto(report: report),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                report.title,
                                style: const TextStyle(
                                  color: AppColors.midnightInk,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${report.reportTypeLabel} • ${report.category}',
                                style: TextStyle(
                                  color: report.typeColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusPill(report: report),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _DetailChip(
                          icon: Icons.location_on_outlined,
                          label: report.location,
                        ),
                        _DetailChip(
                          icon: Icons.schedule_rounded,
                          label: report.formattedDate,
                        ),
                        if (mine)
                          const _DetailChip(
                            icon: Icons.verified_user_outlined,
                            label: 'Your report',
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _SectionTitle(
                      icon: Icons.notes_rounded,
                      title: 'Description',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report.description.isEmpty
                          ? 'No additional description was provided.'
                          : report.description,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle(
                      icon: Icons.shield_outlined,
                      title: 'Safe handover',
                    ),
                    const SizedBox(height: 8),
                    _InfoPanel(
                      children: <Widget>[
                        _InfoRow(
                          label: 'Meet / collect',
                          value: report.collectAt,
                        ),
                        _InfoRow(
                          label: 'Instructions',
                          value: report.requirements,
                        ),
                        if (!mine && report.reportType == 'found')
                          _InfoRow(
                            label: 'Verification',
                            value: report.claimQuestion,
                          ),
                      ],
                    ),
                    if (report.rewardText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              AppColors.ogGold.withValues(alpha: .18),
                              AppColors.electricCyan.withValues(alpha: .10),
                            ],
                          ),
                          borderRadius: AppStyles.controlRadius,
                          border: Border.all(
                            color: AppColors.ogGold.withValues(alpha: .45),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.card_giftcard_rounded,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                report.rewardText,
                                style: const TextStyle(
                                  color: AppColors.midnightInk,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (report.status == 'returned') ...<Widget>[
                      const SizedBox(height: 20),
                      const _CommunityHeroBadge(),
                    ],
                    const SizedBox(height: 24),
                    if (mine)
                      _buildOwnerActions(sheetContext, report)
                    else
                      _buildVisitorActions(sheetContext, report, myClaim),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisitorActions(
    BuildContext sheetContext,
    LostFoundReport report,
    LostFoundClaim? claim,
  ) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openChat(report);
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat safely'),
              ),
            ),
            if (report.reportType == 'found') ...<Widget>[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: claim == null && report.acceptsClaims
                      ? () {
                          Navigator.pop(sheetContext);
                          _openClaimDialog(report);
                        }
                      : null,
                  icon: Icon(
                    claim == null
                        ? Icons.verified_user_outlined
                        : Icons.hourglass_top_rounded,
                  ),
                  label: Text(claim == null ? 'Claim item' : claim.label),
                ),
              ),
            ],
          ],
        ),
        if (claim != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            claim.status == 'approved'
                ? 'Your ownership response was approved. Use chat to arrange a safe handover.'
                : claim.status == 'rejected'
                ? 'The report owner could not verify this claim.'
                : 'Your private verification response is awaiting review.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildOwnerActions(BuildContext sheetContext, LostFoundReport report) {
    final itemClaims = _claimsFor(report.id);
    return Column(
      children: <Widget>[
        if (report.reportType == 'found')
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _manageClaims(report);
              },
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                itemClaims.isEmpty
                    ? 'No ownership claims yet'
                    : 'Review ${itemClaims.length} claim${itemClaims.length == 1 ? '' : 's'}',
              ),
            ),
          ),
        if (report.status != 'returned') ...<Widget>[
          if (report.reportType == 'found') const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _markReturned(report);
              },
              icon: const Icon(Icons.favorite_rounded),
              label: const Text('Mark as returned'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openClaimDialog(LostFoundReport report) async {
    final answerController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.verified_user_outlined,
          color: AppColors.vibeBlue,
          size: 32,
        ),
        title: const Text('Verify ownership'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Your response is private. Only the person who reported this item can read it.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                report.claimQuestion,
                style: const TextStyle(
                  color: AppColors.midnightInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: answerController,
                minLines: 3,
                maxLines: 5,
                maxLength: 700,
                decoration: const InputDecoration(
                  labelText: 'Private verification answer',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (answerController.text.trim().length < 4) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Submit securely'),
          ),
        ],
      ),
    );

    final answer = answerController.text.trim();
    answerController.dispose();
    if (submitted != true || answer.isEmpty || _user == null) return;

    try {
      HapticFeedback.mediumImpact();
      await _supabase.from('lost_and_found_claims').insert(<String, dynamic>{
        'item_id': report.id,
        'claimant_id': _user!.id,
        'verification_answer': answer,
        'status': 'pending',
      });
      await _loadData(showLoader: false);
      _showSnack('Verification sent privately to the report owner.');
    } on PostgrestException catch (error) {
      _showSnack(
        error.code == '23505'
            ? 'You already submitted a claim for this item.'
            : _friendlyError(error),
      );
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _manageClaims(LostFoundReport report) async {
    final itemClaims = _claimsFor(report.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Ownership claims • ${report.title}',
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Never approve a claim unless the private detail convincingly matches the item.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: (MediaQuery.sizeOf(sheetContext).height * .52)
                  .clamp(220.0, 520.0)
                  .toDouble(),
              child: itemClaims.isEmpty
                  ? const Center(
                      child: Text(
                        'No claims have been submitted yet.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: itemClaims.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final claim = itemClaims[index];
                        return Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FC),
                            borderRadius: AppStyles.controlRadius,
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const CircleAvatar(
                                    backgroundColor: Color(0xFFE8EEFF),
                                    child: Icon(
                                      Icons.person_outline_rounded,
                                      color: AppColors.vibeBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Claim ${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  _ClaimStatusPill(status: claim.status),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                claim.verificationAnswer,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  height: 1.45,
                                ),
                              ),
                              if (claim.status == 'pending') ...<Widget>[
                                const SizedBox(height: 12),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () async {
                                          Navigator.pop(sheetContext);
                                          await _respondToClaim(
                                            report,
                                            claim,
                                            approved: false,
                                          );
                                        },
                                        child: const Text('Decline'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () async {
                                          Navigator.pop(sheetContext);
                                          await _respondToClaim(
                                            report,
                                            claim,
                                            approved: true,
                                          );
                                        },
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _respondToClaim(
    LostFoundReport report,
    LostFoundClaim claim, {
    required bool approved,
  }) async {
    try {
      await _supabase
          .from('lost_and_found_claims')
          .update(<String, dynamic>{
            'status': approved ? 'approved' : 'rejected',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', claim.id);
      if (approved) {
        await _supabase
            .from('lost_and_found_items')
            .update(<String, dynamic>{
              'status': 'claimed',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', report.id);
      }
      HapticFeedback.mediumImpact();
      await _loadData(showLoader: false);
      _showSnack(approved ? 'Claim approved.' : 'Claim declined.');
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _markReturned(LostFoundReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.favorite_rounded,
          color: AppColors.success,
          size: 34,
        ),
        title: const Text('Item safely returned?'),
        content: const Text(
          'This celebrates the successful return and closes further ownership claims.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, returned'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase
          .from('lost_and_found_items')
          .update(<String, dynamic>{
            'status': 'returned',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', report.id);
      HapticFeedback.heavyImpact();
      await _loadData(showLoader: false);
      _showSnack('Beautiful work — this item is back home.');
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  void _openChat(LostFoundReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatDetailScreen(
          chatId: report.userId,
          chatTitle: 'Lost & Found • ${report.title}',
        ),
      ),
    );
  }

  Future<void> _openReportWizard() async {
    final user = _user;
    if (user == null) {
      _showSnack('Please sign in before reporting an item.');
      return;
    }

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    final collectController = TextEditingController();
    final instructionsController = TextEditingController();
    final claimQuestionController = TextEditingController(
      text: 'Describe a unique detail that proves this item belongs to you.',
    );
    final rewardController = TextEditingController();
    final pageController = PageController();
    var page = 0;
    var reportType = 'lost';
    var category = 'Personal item';
    var incidentAt = DateTime.now();
    Uint8List? imageBytes;
    var submitting = false;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickPhoto() async {
            final image = await _picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              imageQuality: 86,
            );
            if (image == null) return;
            final bytes = await image.readAsBytes();
            setSheetState(() => imageBytes = bytes);
          }

          Future<void> pickDate() async {
            final value = await showDatePicker(
              context: context,
              initialDate: incidentAt,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (value != null) setSheetState(() => incidentAt = value);
          }

          bool stepValid() {
            if (page == 0) return titleController.text.trim().isNotEmpty;
            if (page == 1) {
              return locationController.text.trim().isNotEmpty &&
                  descriptionController.text.trim().isNotEmpty;
            }
            return reportType == 'lost' ||
                claimQuestionController.text.trim().length >= 4;
          }

          Future<void> next() async {
            if (!stepValid()) {
              _showSnack('Complete the required details before continuing.');
              return;
            }
            if (page < 2) {
              HapticFeedback.selectionClick();
              setSheetState(() => page += 1);
              await pageController.animateToPage(
                page,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              );
              return;
            }

            setSheetState(() => submitting = true);
            try {
              String? imagePath;
              if (imageBytes != null) {
                imagePath =
                    'lost_and_found/${user.id}/${DateTime.now().microsecondsSinceEpoch}.jpg';
                await _supabase.storage
                    .from('lost-and-found')
                    .uploadBinary(
                      imagePath,
                      imageBytes!,
                      fileOptions: const FileOptions(
                        contentType: 'image/jpeg',
                        upsert: false,
                      ),
                    );
              }

              await _supabase
                  .from('lost_and_found_items')
                  .insert(<String, dynamic>{
                    'user_id': user.id,
                    'report_type': reportType,
                    'title': titleController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'category': category,
                    'found_at': locationController.text.trim(),
                    'collect_at': collectController.text.trim().isEmpty
                        ? 'Arrange a safe handover in chat'
                        : collectController.text.trim(),
                    'requirements': instructionsController.text.trim().isEmpty
                        ? 'Meet in a public campus location.'
                        : instructionsController.text.trim(),
                    'claim_question': claimQuestionController.text.trim(),
                    'reward_text': rewardController.text.trim(),
                    'incident_at': incidentAt.toUtc().toIso8601String(),
                    'image_path': imagePath,
                    'status': 'open',
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  });
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext, true);
            } catch (error) {
              setSheetState(() => submitting = false);
              _showSnack(_friendlyError(error));
            }
          }

          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .88,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Create a careful report',
                                style: TextStyle(
                                  color: AppColors.midnightInk,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Step ${page + 1} of 3',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close report',
                          onPressed: submitting
                              ? null
                              : () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: List<Widget>.generate(
                        3,
                        (index) => Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 5,
                            margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                            decoration: BoxDecoration(
                              color: index <= page
                                  ? AppColors.vibeBlue
                                  : AppColors.glassBorder,
                              borderRadius: AppStyles.pillRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: PageView(
                      controller: pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: <Widget>[
                        _ReportBasicsStep(
                          reportType: reportType,
                          category: category,
                          titleController: titleController,
                          onTypeChanged: (value) =>
                              setSheetState(() => reportType = value),
                          onCategoryChanged: (value) =>
                              setSheetState(() => category = value),
                        ),
                        _ReportStoryStep(
                          reportType: reportType,
                          descriptionController: descriptionController,
                          locationController: locationController,
                          incidentAt: incidentAt,
                          onPickDate: pickDate,
                        ),
                        _ReportSafetyStep(
                          reportType: reportType,
                          imageBytes: imageBytes,
                          collectController: collectController,
                          instructionsController: instructionsController,
                          claimQuestionController: claimQuestionController,
                          rewardController: rewardController,
                          onPickPhoto: pickPhoto,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    child: Row(
                      children: <Widget>[
                        if (page > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      setSheetState(() => page -= 1);
                                      await pageController.animateToPage(
                                        page,
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      );
                                    },
                              child: const Text('Back'),
                            ),
                          ),
                        if (page > 0) const SizedBox(width: 10),
                        Expanded(
                          flex: page == 0 ? 1 : 2,
                          child: FilledButton.icon(
                            onPressed: submitting ? null : next,
                            icon: submitting
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    page == 2
                                        ? Icons.publish_rounded
                                        : Icons.arrow_forward_rounded,
                                  ),
                            label: Text(
                              submitting
                                  ? 'Publishing…'
                                  : page == 2
                                  ? 'Publish report'
                                  : 'Continue',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    pageController.dispose();
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    collectController.dispose();
    instructionsController.dispose();
    claimQuestionController.dispose();
    rewardController.dispose();

    if (submitted == true) {
      HapticFeedback.mediumImpact();
      _tabController.animateTo(2);
      await _loadData(showLoader: false);
      _showSnack('Your report is live in Lost & Found.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission') || raw.contains('row-level')) {
      return 'This action is not permitted for your account.';
    }
    if (raw.contains('network') || raw.contains('socket')) {
      return 'Check your connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}

class _ReportBasicsStep extends StatelessWidget {
  const _ReportBasicsStep({
    required this.reportType,
    required this.category,
    required this.titleController,
    required this.onTypeChanged,
    required this.onCategoryChanged,
  });

  final String reportType;
  final String category;
  final TextEditingController titleController;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    const categories = <String>[
      'Personal item',
      'Electronics',
      'Documents',
      'Clothing',
      'Keys',
      'Bags',
      'Other',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: <Widget>[
        const _StepHeading(
          title: 'What happened?',
          subtitle: 'Choose the report type and name the item clearly.',
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _TypeChoice(
                selected: reportType == 'lost',
                icon: Icons.search_rounded,
                title: 'I lost it',
                subtitle: 'Ask the community to look out',
                color: AppColors.danger,
                onTap: () => onTypeChanged('lost'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeChoice(
                selected: reportType == 'found',
                icon: Icons.inventory_2_outlined,
                title: 'I found it',
                subtitle: 'Help reunite it safely',
                color: AppColors.success,
                onTap: () => onTypeChanged('found'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: titleController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 90,
          decoration: const InputDecoration(
            labelText: 'Item name *',
            hintText: 'e.g. Black scientific calculator',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: categories
              .map(
                (value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onCategoryChanged(value);
          },
        ),
      ],
    );
  }
}

class _ReportStoryStep extends StatelessWidget {
  const _ReportStoryStep({
    required this.reportType,
    required this.descriptionController,
    required this.locationController,
    required this.incidentAt,
    required this.onPickDate,
  });

  final String reportType;
  final TextEditingController descriptionController;
  final TextEditingController locationController;
  final DateTime incidentAt;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: <Widget>[
        const _StepHeading(
          title: 'Tell the story',
          subtitle: 'Specific details help students recognise the right item.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: descriptionController,
          minLines: 4,
          maxLines: 6,
          maxLength: 700,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Description *',
            alignLabelWithHint: true,
            hintText: reportType == 'lost'
                ? 'Colour, brand, distinguishing marks…'
                : 'Describe it without revealing the private proof detail…',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: locationController,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: reportType == 'lost'
                ? 'Last seen location *'
                : 'Found at *',
            prefixIcon: const Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPickDate,
          borderRadius: AppStyles.controlRadius,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            child: Text(_formatDate(incidentAt)),
          ),
        ),
      ],
    );
  }
}

class _ReportSafetyStep extends StatelessWidget {
  const _ReportSafetyStep({
    required this.reportType,
    required this.imageBytes,
    required this.collectController,
    required this.instructionsController,
    required this.claimQuestionController,
    required this.rewardController,
    required this.onPickPhoto,
  });

  final String reportType;
  final Uint8List? imageBytes;
  final TextEditingController collectController;
  final TextEditingController instructionsController;
  final TextEditingController claimQuestionController;
  final TextEditingController rewardController;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: <Widget>[
        const _StepHeading(
          title: 'Photo & safe handover',
          subtitle:
              'A clear photo improves recognition. Keep sensitive proof private.',
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: imageBytes == null
              ? 'Attach item photo'
              : 'Replace item photo',
          child: InkWell(
            onTap: onPickPhoto,
            borderRadius: AppStyles.controlRadius,
            child: Container(
              height: 180,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5FC),
                borderRadius: AppStyles.controlRadius,
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: imageBytes == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.vibeBlue,
                          size: 34,
                        ),
                        SizedBox(height: 9),
                        Text(
                          'Add a clear photo',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Optional but recommended',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Image.memory(imageBytes!, fit: BoxFit.cover),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.midnightInk.withValues(
                                alpha: .8,
                              ),
                              borderRadius: AppStyles.pillRadius,
                            ),
                            child: const Text(
                              'Change photo',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: collectController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: reportType == 'found'
                ? 'Safe collection location'
                : 'Preferred safe meeting place',
            prefixIcon: const Icon(Icons.handshake_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: instructionsController,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Handover instructions',
            alignLabelWithHint: true,
          ),
        ),
        if (reportType == 'found') ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            controller: claimQuestionController,
            maxLines: 2,
            maxLength: 240,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Private ownership question *',
              alignLabelWithHint: true,
              helperText: 'Do not include the correct answer here.',
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: rewardController,
          maxLength: 140,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Optional reward or thank-you',
            hintText: 'e.g. Coffee voucher and a huge thank-you',
            prefixIcon: Icon(Icons.card_giftcard_rounded),
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.mine,
    required this.claim,
    required this.claimCount,
    required this.onTap,
  });

  final LostFoundReport report;
  final bool mine;
  final LostFoundClaim? claim;
  final int claimCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${report.reportTypeLabel} item: ${report.title}, ${report.statusLabel}',
      child: ClipRRect(
        borderRadius: AppStyles.bentoRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: Colors.white.withValues(alpha: .86),
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppStyles.bentoRadius,
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: AppStyles.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          _Photo(report: report),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Colors.transparent,
                                  AppColors.midnightInk.withValues(alpha: .66),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: _TypePill(report: report),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: _StatusPill(report: report),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: Text(
                              report.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _CompactDetail(
                              icon: Icons.location_on_outlined,
                              value: report.location,
                            ),
                            const SizedBox(height: 7),
                            _CompactDetail(
                              icon: Icons.schedule_rounded,
                              value:
                                  '${report.formattedDate} • ${report.category}',
                            ),
                            const Spacer(),
                            Row(
                              children: <Widget>[
                                if (report.rewardText.isNotEmpty)
                                  const _MiniBadge(
                                    icon: Icons.card_giftcard_rounded,
                                    label: 'Reward',
                                    color: AppColors.warning,
                                  ),
                                if (mine && claimCount > 0) ...<Widget>[
                                  if (report.rewardText.isNotEmpty)
                                    const SizedBox(width: 6),
                                  _MiniBadge(
                                    icon: Icons.fact_check_outlined,
                                    label:
                                        '$claimCount claim${claimCount == 1 ? '' : 's'}',
                                    color: AppColors.vibeBlue,
                                  ),
                                ],
                                if (claim != null) ...<Widget>[
                                  if (report.rewardText.isNotEmpty)
                                    const SizedBox(width: 6),
                                  _MiniBadge(
                                    icon: Icons.verified_user_outlined,
                                    label: claim!.label,
                                    color: claim!.color,
                                  ),
                                ],
                                const Spacer(),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: AppColors.vibeBlue,
                                  size: 19,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.report});

  final LostFoundReport report;

  @override
  Widget build(BuildContext context) {
    if (report.imageUrl != null) {
      return Image.network(
        report.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PhotoFallback(report: report),
      );
    }
    return _PhotoFallback(report: report);
  }
}

class _DetailPhoto extends StatelessWidget {
  const _DetailPhoto({required this.report});

  final LostFoundReport report;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _Photo(report: report),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Colors.black38, Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.center,
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: 'Close details',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.report});

  final LostFoundReport report;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            report.typeColor.withValues(alpha: .74),
            AppColors.midnightInk,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          report.categoryIcon,
          color: Colors.white.withValues(alpha: .88),
          size: 66,
        ),
      ),
    );
  }
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabsHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 82;

  @override
  double get maxExtent => 82;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: .16),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: highlight ? AppColors.ogGold : AppColors.electricCyan,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.report});

  final LostFoundReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: report.typeColor,
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            report.reportType == 'lost'
                ? Icons.search_rounded
                : Icons.inventory_2_outlined,
            color: Colors.white,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            report.reportTypeLabel.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              letterSpacing: .7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.report});

  final LostFoundReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: report.statusColor,
        borderRadius: AppStyles.pillRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 8),
        ],
      ),
      child: Text(
        report.statusLabel.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ClaimStatusPill extends StatelessWidget {
  const _ClaimStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FC),
        borderRadius: AppStyles.pillRadius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: AppColors.vibeBlue),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactDetail extends StatelessWidget {
  const _CompactDetail({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.textMuted, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.vibeBlue, size: 19),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.midnightInk,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: AppStyles.controlRadius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityHeroBadge extends StatelessWidget {
  const _CommunityHeroBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0C9B70), Color(0xFF24B9AE)],
        ),
        borderRadius: AppStyles.controlRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.success.withValues(alpha: .2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.workspace_premium_rounded, color: AppColors.ogGold),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'COMMUNITY HERO',
                  style: TextStyle(
                    color: Colors.white,
                    letterSpacing: 1,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'This report helped an item find its way home.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChoice extends StatelessWidget {
  const _TypeChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppStyles.controlRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .1) : Colors.white,
          borderRadius: AppStyles.controlRadius,
          border: Border.all(
            color: selected ? color : AppColors.glassBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, color: color, size: 29),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: AppColors.midnightInk,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isMine,
    required this.type,
    required this.onReport,
  });

  final bool isMine;
  final String type;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: .09),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMine
                  ? Icons.inventory_2_outlined
                  : type == 'lost'
                  ? Icons.search_rounded
                  : Icons.checkroom_outlined,
              color: AppColors.vibeBlue,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isMine
                ? 'Your reports will live here'
                : 'No $type items reported yet',
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            isMine
                ? 'Create a careful report and track claims from one place.'
                : 'That is good news. You can still help by keeping an eye out.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create report'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class LostFoundReport {
  const LostFoundReport({
    required this.id,
    required this.userId,
    required this.title,
    required this.location,
    required this.collectAt,
    required this.requirements,
    required this.imageUrl,
    required this.status,
    required this.reportType,
    required this.description,
    required this.category,
    required this.incidentAt,
    required this.claimQuestion,
    required this.rewardText,
  });

  factory LostFoundReport.fromRow(
    Map<String, dynamic> row,
    Map<String, String> signedUrls,
  ) {
    final path = _optional(row['image_path']);
    return LostFoundReport(
      id: row['id'].toString(),
      userId: row['user_id'].toString(),
      title: row['title']?.toString().trim() ?? 'Untitled item',
      location: row['found_at']?.toString().trim() ?? 'Unknown location',
      collectAt:
          row['collect_at']?.toString().trim() ?? 'Arrange safely in chat',
      requirements:
          row['requirements']?.toString().trim() ?? 'Meet in a public place.',
      imageUrl: path == null ? _optional(row['image_url']) : signedUrls[path],
      status: row['status']?.toString() ?? 'open',
      reportType: row['report_type']?.toString() ?? 'found',
      description: row['description']?.toString().trim() ?? '',
      category: row['category']?.toString().trim() ?? 'Other',
      incidentAt:
          DateTime.tryParse(row['incident_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      claimQuestion:
          row['claim_question']?.toString().trim() ??
          'Describe a detail that proves ownership.',
      rewardText: row['reward_text']?.toString().trim() ?? '',
    );
  }

  final String id;
  final String userId;
  final String title;
  final String location;
  final String collectAt;
  final String requirements;
  final String? imageUrl;
  final String status;
  final String reportType;
  final String description;
  final String category;
  final DateTime incidentAt;
  final String claimQuestion;
  final String rewardText;

  bool get isDiscoverable => status == 'open' || status == 'matched';
  bool get acceptsClaims =>
      reportType == 'found' && (status == 'open' || status == 'matched');
  String get reportTypeLabel => reportType == 'lost' ? 'Lost' : 'Found';
  String get statusLabel => switch (status) {
    'matched' => 'Potential match',
    'claimed' => 'Claimed',
    'returned' => 'Returned',
    'archived' => 'Archived',
    _ => 'Open',
  };
  Color get typeColor =>
      reportType == 'lost' ? AppColors.danger : AppColors.success;
  Color get statusColor => switch (status) {
    'matched' => AppColors.warning,
    'claimed' => AppColors.vibeBlue,
    'returned' => AppColors.success,
    'archived' => AppColors.textMuted,
    _ => AppColors.midnightInk,
  };
  IconData get categoryIcon => switch (category.toLowerCase()) {
    'electronics' => Icons.devices_other_outlined,
    'documents' => Icons.badge_outlined,
    'clothing' => Icons.checkroom_outlined,
    'keys' => Icons.key_outlined,
    'bags' => Icons.backpack_outlined,
    _ => Icons.inventory_2_outlined,
  };
  String get formattedDate => _formatDate(incidentAt);
}

class LostFoundClaim {
  const LostFoundClaim({
    required this.id,
    required this.itemId,
    required this.claimantId,
    required this.verificationAnswer,
    required this.status,
  });

  factory LostFoundClaim.fromRow(Map<String, dynamic> row) => LostFoundClaim(
    id: row['id'].toString(),
    itemId: row['item_id'].toString(),
    claimantId: row['claimant_id'].toString(),
    verificationAnswer: row['verification_answer']?.toString() ?? '',
    status: row['status']?.toString() ?? 'pending',
  );

  final String id;
  final String itemId;
  final String claimantId;
  final String verificationAnswer;
  final String status;

  String get label => switch (status) {
    'approved' => 'Approved',
    'rejected' => 'Declined',
    _ => 'Pending',
  };
  Color get color => switch (status) {
    'approved' => AppColors.success,
    'rejected' => AppColors.danger,
    _ => AppColors.warning,
  };
}

String _formatDate(DateTime value) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String? _optional(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
