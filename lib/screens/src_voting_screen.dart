import 'dart:async';

import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class SrcVotingScreen extends StatefulWidget {
  const SrcVotingScreen({super.key});

  @override
  State<SrcVotingScreen> createState() => _SrcVotingScreenState();
}

class _SrcVotingScreenState extends State<SrcVotingScreen> {
  static const _positions = <_ElectionPosition>[
    _ElectionPosition(
      id: 'president',
      title: 'SRC President',
      candidates: [
        _ElectionCandidate(
          id: 'president-thabo',
          name: 'Thabo Mokoena',
          course: 'IT NC(V) L4',
          slogan: 'Better Wi-Fi, Better Grades!',
          manifesto:
              'Improve campus connectivity, extend study support, and publish '
              'clear progress updates each term.',
          color: Color(0xFF2457F5),
          sampleResult: 42,
        ),
        _ElectionCandidate(
          id: 'president-lerato',
          name: 'Lerato Khumalo',
          course: 'Business Management N5',
          slogan: 'Student Safety First.',
          manifesto:
              'Strengthen campus safety communication and make student '
              'support services easier to find.',
          color: Color(0xFF0D47A1),
          sampleResult: 33,
        ),
        _ElectionCandidate(
          id: 'president-sibusiso',
          name: 'Sibusiso Nkosi',
          course: 'Engineering N4',
          slogan: 'Fix Our NSFAS Allowances.',
          manifesto:
              'Coordinate regular funding updates and help students find the '
              'right support contacts.',
          color: Color(0xFFB94B20),
          sampleResult: 25,
        ),
      ],
    ),
    _ElectionPosition(
      id: 'deputy',
      title: 'Deputy President',
      candidates: [
        _ElectionCandidate(
          id: 'deputy-ayanda',
          name: 'Ayanda Mthembu',
          course: 'Hospitality N5',
          slogan: 'A campus that listens.',
          manifesto:
              'Create regular feedback sessions and share clear follow-up '
              'notes after student meetings.',
          color: Color(0xFF2457F5),
          sampleResult: 38,
        ),
        _ElectionCandidate(
          id: 'deputy-kabelo',
          name: 'Kabelo Dube',
          course: 'Electrical Engineering N4',
          slogan: 'Make every voice count.',
          manifesto:
              'Bring student representatives closer to classrooms and '
              'communicate decisions in plain language.',
          color: Color(0xFF2457F5),
          sampleResult: 35,
        ),
        _ElectionCandidate(
          id: 'deputy-nomfundo',
          name: 'Nomfundo Zulu',
          course: 'Public Management N5',
          slogan: 'Reliable support, every term.',
          manifesto:
              'Help students navigate support services and raise common '
              'issues with the right teams.',
          color: Color(0xFF0D47A1),
          sampleResult: 27,
        ),
      ],
    ),
    _ElectionPosition(
      id: 'secretary',
      title: 'SRC Secretary',
      candidates: [
        _ElectionCandidate(
          id: 'secretary-nandi',
          name: 'Nandi Maseko',
          course: 'Office Administration N6',
          slogan: 'Clear minutes. Clear answers.',
          manifesto:
              'Publish accessible meeting summaries and keep an organized '
              'record of student requests.',
          color: Color(0xFF0D47A1),
          sampleResult: 45,
        ),
        _ElectionCandidate(
          id: 'secretary-lunga',
          name: 'Lunga Mkhize',
          course: 'Financial Management N5',
          slogan: 'Keep students in the loop.',
          manifesto: 'Share notices on time and make SRC updates easy to find.',
          color: Color(0xFFB94B20),
          sampleResult: 31,
        ),
        _ElectionCandidate(
          id: 'secretary-zinhle',
          name: 'Zinhle Dlamini',
          course: 'Tourism N5',
          slogan: 'Communication you can count on.',
          manifesto:
              'Use consistent updates so students know what was raised and '
              'what happens next.',
          color: Color(0xFF2457F5),
          sampleResult: 24,
        ),
      ],
    ),
  ];

  final _searchController = TextEditingController();
  final _ballotSelections = <String, String>{};
  final _compareSelections = <String>{};
  final DateTime _demoClosesAt = DateTime.now().add(
    const Duration(days: 3, hours: 4),
  );

  String _positionId = _positions.first.id;
  String _searchQuery = '';
  _CandidateLayout _layout = _CandidateLayout.gallery;
  int _ballotStep = 0;
  bool _ballotReviewed = false;
  Timer? _countdownTimer;

  _ElectionPosition get _position =>
      _positions.firstWhere((position) => position.id == _positionId);

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: VibeScaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SRC election'),
            SizedBox(height: 2),
            Text(
              'Student representative ballot',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Candidates'),
            Tab(icon: Icon(Icons.ballot_outlined), text: 'Ballot'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Results'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _buildCandidatesTab(context),
          _buildBallotTab(context),
          _buildResultsTab(context),
        ],
      ),
    ),
  );

  Widget _buildCandidatesTab(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final candidates = _position.candidates
        .where((candidate) {
          if (query.isEmpty) return true;
          return candidate.name.toLowerCase().contains(query) ||
              candidate.course.toLowerCase().contains(query) ||
              candidate.slogan.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _DemoNotice(
          text:
              'Preview only. Candidate details, schedule, turnout, and results '
              'are sample data. No official vote is submitted.',
        ),
        const SizedBox(height: 12),
        _buildElectionOverview(context),
        const SizedBox(height: 20),
        Text(
          'Meet the candidates',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF07172F),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Review each candidate before choosing a sample ballot selection.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF2457F5)),
        ),
        const SizedBox(height: 14),
        _buildPositionPicker(context, _positionId, (value) {
          setState(() {
            _positionId = value;
            _compareSelections.clear();
          });
        }),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Search name, course, or slogan',
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE8F0FF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE8F0FF)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildCandidateToolbar(context),
        if (_compareSelections.length >= 2) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _showComparison(context),
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text('Compare ${_compareSelections.length} candidates'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (candidates.isEmpty)
          _buildEmptySearchState(context)
        else if (_layout == _CandidateLayout.compact)
          ...candidates.map(
            (candidate) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CandidateCard(
                candidate: candidate,
                compact: true,
                selectedForBallot:
                    _ballotSelections[_position.id] == candidate.id,
                selectedForComparison: _compareSelections.contains(
                  candidate.id,
                ),
                onSelectForBallot: () => _selectForBallot(candidate),
                onToggleComparison: () => _toggleComparison(candidate),
                onOpenProfile: () => _showCandidateProfile(context, candidate),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              return GridView.builder(
                itemCount: candidates.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 288,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  final candidate = candidates[index];
                  return _CandidateCard(
                    candidate: candidate,
                    compact: false,
                    selectedForBallot:
                        _ballotSelections[_position.id] == candidate.id,
                    selectedForComparison: _compareSelections.contains(
                      candidate.id,
                    ),
                    onSelectForBallot: () => _selectForBallot(candidate),
                    onToggleComparison: () => _toggleComparison(candidate),
                    onOpenProfile: () =>
                        _showCandidateProfile(context, candidate),
                  );
                },
              );
            },
          ),
        const SizedBox(height: 18),
        _buildGuidanceCard(context),
        const SizedBox(height: 10),
        _buildPrivacyCard(context),
      ],
    );
  }

  Widget _buildElectionOverview(BuildContext context) {
    final remaining = _demoClosesAt.difference(DateTime.now());
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final days = safeRemaining.inDays;
    final hours = safeRemaining.inHours.remainder(24);
    final minutes = safeRemaining.inMinutes.remainder(60);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8F0FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_vote_rounded, color: Color(0xFF2457F5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ermelo TVET College · SRC elections',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF07172F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const _SampleBadge(),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _OverviewMetric(
                    icon: Icons.how_to_vote_outlined,
                    label: 'Positions',
                    value: '${_positions.length}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OverviewMetric(
                    icon: Icons.people_outline_rounded,
                    label: 'Candidates',
                    value:
                        '${_positions.fold<int>(0, (total, p) => total + p.candidates.length)}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OverviewMetric(
                    icon: Icons.timer_outlined,
                    label: 'Sample closes',
                    value: '${days}d ${hours}h ${minutes}m',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                value: .62,
                minHeight: 7,
                backgroundColor: Color(0xFFE8F0FF),
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2457F5)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sample turnout: 62% · sample schedule only',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF2457F5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionPicker(
    BuildContext context,
    String value,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: 'Election position',
      prefixIcon: const Icon(Icons.badge_outlined),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    items: _positions
        .map(
          (position) =>
              DropdownMenuItem(value: position.id, child: Text(position.title)),
        )
        .toList(growable: false),
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );

  Widget _buildCandidateToolbar(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          '${_position.candidates.length} candidates',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF2457F5),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      SegmentedButton<_CandidateLayout>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _CandidateLayout.gallery,
            icon: Icon(Icons.grid_view_rounded),
            label: Text('Gallery'),
          ),
          ButtonSegment(
            value: _CandidateLayout.compact,
            icon: Icon(Icons.view_list_rounded),
            label: Text('Compact'),
          ),
        ],
        selected: {_layout},
        onSelectionChanged: (selection) =>
            setState(() => _layout = selection.first),
      ),
    ],
  );

  Widget _buildEmptySearchState(BuildContext context) => Card(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.person_search_rounded, size: 36),
          const SizedBox(height: 8),
          Text(
            'No candidates match your search.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
            child: const Text('Clear search'),
          ),
        ],
      ),
    ),
  );

  Widget _buildGuidanceCard(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE8F0FF)),
    ),
    child: ExpansionTile(
      leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF2457F5)),
      title: const Text('How the ballot works'),
      subtitle: const Text('Review candidates, then choose by position.'),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      children: const [
        _GuidanceRow(
          number: '1',
          text: 'Review candidate profiles and manifestos.',
        ),
        _GuidanceRow(
          number: '2',
          text: 'Choose one candidate for each position.',
        ),
        _GuidanceRow(
          number: '3',
          text: 'Review your sample choices before finishing.',
        ),
      ],
    ),
  );

  Widget _buildPrivacyCard(BuildContext context) => Card(
    color: const Color(0xFFF7F9FD),
    elevation: 0,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: Color(0xFF2457F5)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Privacy preview. This screen stores sample selections only in '
              'memory. It does not verify voter eligibility, save a ballot, '
              'or send data to an election service.',
              style: TextStyle(color: Color(0xFF0D47A1), height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildBallotTab(BuildContext context) {
    final position = _positions[_ballotStep];
    final selection = _ballotSelections[position.id];
    final completed = _ballotSelections.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _DemoNotice(
          text:
              'Demo ballot only. Choices stay in this screen session and are '
              'not submitted or saved as an official vote.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Position ${_ballotStep + 1} of ${_positions.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF07172F),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$completed selected',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: const Color(0xFF2457F5)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (_ballotStep + 1) / _positions.length,
            minHeight: 8,
            backgroundColor: const Color(0xFFE8F0FF),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2457F5)),
          ),
        ),
        const SizedBox(height: 18),
        _buildPositionPicker(context, position.id, (value) {
          final index = _positions.indexWhere((item) => item.id == value);
          if (index >= 0) setState(() => _ballotStep = index);
        }),
        const SizedBox(height: 18),
        Text(
          position.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF07172F),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose one candidate for this position. You can change it before review.',
          style: TextStyle(color: Color(0xFF2457F5), height: 1.4),
        ),
        const SizedBox(height: 12),
        ...position.candidates.map(
          (candidate) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BallotChoiceTile(
              candidate: candidate,
              selected: selection == candidate.id,
              onTap: () => setState(() {
                _ballotSelections[position.id] = candidate.id;
                _ballotReviewed = false;
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_ballotStep > 0)
              OutlinedButton.icon(
                onPressed: () => setState(() => _ballotStep--),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Previous'),
              ),
            const Spacer(),
            if (_ballotStep < _positions.length - 1)
              FilledButton.icon(
                onPressed: selection == null
                    ? null
                    : () => setState(() => _ballotStep++),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Next position'),
              )
            else
              FilledButton.icon(
                onPressed: _ballotSelections.length == _positions.length
                    ? () => _reviewBallot(context)
                    : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  _ballotReviewed ? 'Review again' : 'Review choices',
                ),
              ),
          ],
        ),
        if (_ballotStep == _positions.length - 1 &&
            _ballotSelections.length < _positions.length) ...[
          const SizedBox(height: 8),
          const Text(
            'Choose a candidate for each position to review the demo ballot.',
            style: TextStyle(color: Color(0xFF2457F5)),
            textAlign: TextAlign.end,
          ),
        ],
        if (_ballotReviewed) ...[
          const SizedBox(height: 12),
          const _DemoNotice(
            text:
                'Your sample choices were reviewed. No official ballot was sent.',
            success: true,
          ),
        ],
      ],
    );
  }

  Widget _buildResultsTab(BuildContext context) {
    final totalCandidates = _positions.fold<int>(
      0,
      (total, position) => total + position.candidates.length,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const _DemoNotice(
          text:
              'Sample results only. These figures are illustrative and are '
              'not connected to an election or live vote count.',
        ),
        const SizedBox(height: 14),
        Text(
          'Election overview',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF07172F),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'A sample dashboard for reviewing positions and candidate totals.',
          style: TextStyle(color: Color(0xFF2457F5)),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ResultSummaryCard(
              label: 'Sample turnout',
              value: '62%',
              icon: Icons.groups_outlined,
            ),
            _ResultSummaryCard(
              label: 'Positions',
              value: '${_positions.length}',
              icon: Icons.badge_outlined,
            ),
            _ResultSummaryCard(
              label: 'Candidates',
              value: '$totalCandidates',
              icon: Icons.people_alt_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        ..._positions.map(
          (position) => _buildPositionResults(context, position),
        ),
        const SizedBox(height: 8),
        const Text(
          'Results are sample percentages for this prototype. They do not '
          'represent official election results.',
          style: TextStyle(color: Color(0xFF2457F5), height: 1.4),
        ),
      ],
    );
  }

  Widget _buildPositionResults(
    BuildContext context,
    _ElectionPosition position,
  ) {
    final ranked = [...position.candidates]
      ..sort((left, right) => right.sampleResult.compareTo(left.sampleResult));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE8F0FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              position.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF07172F),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            ...ranked.map(
              (candidate) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ResultBar(candidate: candidate),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCandidateProfile(
    BuildContext context,
    _ElectionCandidate candidate,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: .78,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7FA2FF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(child: _CandidateAvatar(candidate: candidate, size: 76)),
              const SizedBox(height: 12),
              Text(
                candidate.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF07172F),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                candidate.course,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF2457F5)),
              ),
              const SizedBox(height: 20),
              const _SampleBadge(),
              const SizedBox(height: 14),
              Text(
                '“${candidate.slogan}”',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: candidate.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Manifesto',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF07172F),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                candidate.manifesto,
                style: const TextStyle(color: Color(0xFF0D47A1), height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _selectForBallot(candidate);
                },
                icon: const Icon(Icons.ballot_outlined),
                label: const Text('Select for sample ballot'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showComparison(BuildContext context) async {
    final candidates = _position.candidates
        .where((candidate) => _compareSelections.contains(candidate.id))
        .toList(growable: false);
    if (candidates.length < 2) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compare candidates',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(_position.title),
              const SizedBox(height: 12),
              ...candidates.map(
                (candidate) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _CandidateAvatar(candidate: candidate, size: 42),
                  title: Text(candidate.name),
                  subtitle: Text(
                    '${candidate.course}\n${candidate.slogan}\n${candidate.manifesto}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectForBallot(_ElectionCandidate candidate) {
    setState(() {
      _ballotSelections[_position.id] = candidate.id;
      _ballotReviewed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${candidate.name} selected for the sample ballot.'),
        action: SnackBarAction(
          label: 'Open ballot',
          onPressed: () => DefaultTabController.of(context).animateTo(1),
        ),
      ),
    );
  }

  void _toggleComparison(_ElectionCandidate candidate) {
    setState(() {
      if (_compareSelections.contains(candidate.id)) {
        _compareSelections.remove(candidate.id);
      } else if (_compareSelections.length < 3) {
        _compareSelections.add(candidate.id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compare up to three candidates.')),
        );
      }
    });
  }

  Future<void> _reviewBallot(BuildContext context) async {
    final summary = _positions
        .map((position) {
          final candidateId = _ballotSelections[position.id];
          final candidate = position.candidates.firstWhere(
            (item) => item.id == candidateId,
          );
          return (position: position, candidate: candidate);
        })
        .toList(growable: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review sample choices'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _DemoNotice(
                  text:
                      'This is a preview. Confirming will not submit or save '
                      'an official vote.',
                ),
                const SizedBox(height: 12),
                ...summary.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.position.title),
                    subtitle: Text(item.candidate.name),
                    leading: _CandidateAvatar(
                      candidate: item.candidate,
                      size: 38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish preview'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _ballotReviewed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preview complete. No official vote was submitted.'),
        ),
      );
    }
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.compact,
    required this.selectedForBallot,
    required this.selectedForComparison,
    required this.onSelectForBallot,
    required this.onToggleComparison,
    required this.onOpenProfile,
  });

  final _ElectionCandidate candidate;
  final bool compact;
  final bool selectedForBallot;
  final bool selectedForComparison;
  final VoidCallback onSelectForBallot;
  final VoidCallback onToggleComparison;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selectedForBallot
            ? const Color(0xFF2457F5)
            : const Color(0xFFE8F0FF),
        width: selectedForBallot ? 1.5 : 1,
      ),
    ),
    child: Padding(
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CandidateAvatar(candidate: candidate, size: compact ? 46 : 52),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF07172F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      candidate.course,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF2457F5),
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: selectedForComparison,
                onChanged: (_) => onToggleComparison(),
                semanticLabel: 'Compare ${candidate.name}',
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            Text(
              '“${candidate.slogan}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: candidate.color,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              candidate.manifesto,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0D47A1),
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ] else ...[
            const SizedBox(height: 7),
            Text(
              candidate.slogan,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: candidate.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          SizedBox(height: compact ? 10 : 0),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpenProfile,
                  child: const Text('Manifesto'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onSelectForBallot,
                  child: Text(selectedForBallot ? 'Selected' : 'Select'),
                ),
              ),
            ],
          ),
          if (selectedForBallot) ...[
            const SizedBox(height: 5),
            const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 15,
                  color: Color(0xFF2457F5),
                ),
                SizedBox(width: 5),
                Text(
                  'Selected for this session only',
                  style: TextStyle(
                    color: Color(0xFF2457F5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _BallotChoiceTile extends StatelessWidget {
  const _BallotChoiceTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final _ElectionCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: selected ? const Color(0xFF2457F5) : const Color(0xFFE8F0FF),
        width: selected ? 1.5 : 1,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 4),
            _CandidateAvatar(candidate: candidate, size: 42),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.name,
                    style: const TextStyle(
                      color: Color(0xFF07172F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    candidate.course,
                    style: const TextStyle(color: Color(0xFF2457F5)),
                  ),
                  Text(
                    candidate.slogan,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: candidate.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CandidateAvatar extends StatelessWidget {
  const _CandidateAvatar({required this.candidate, required this.size});

  final _ElectionCandidate candidate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = candidate.name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    return Semantics(
      label: '${candidate.name} initials',
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: candidate.color.withValues(alpha: .13),
        child: Text(
          initials,
          style: TextStyle(
            color: candidate.color,
            fontWeight: FontWeight.w800,
            fontSize: size * .28,
          ),
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.candidate});

  final _ElectionCandidate candidate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              candidate.name,
              style: const TextStyle(
                color: Color(0xFF0D47A1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${candidate.sampleResult}% sample',
            style: TextStyle(
              color: candidate.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: candidate.sampleResult / 100,
          minHeight: 9,
          backgroundColor: const Color(0xFFE8F0FF),
          valueColor: AlwaysStoppedAnimation<Color>(candidate.color),
          semanticsLabel: 'Sample result for ${candidate.name}',
          semanticsValue: '${candidate.sampleResult} percent',
        ),
      ),
    ],
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FD),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2457F5)),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF07172F),
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: const Color(0xFF2457F5)),
        ),
      ],
    ),
  );
}

class _ResultSummaryCard extends StatelessWidget {
  const _ResultSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 155,
    child: Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8F0FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF2457F5)),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF07172F),
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: const TextStyle(color: Color(0xFF2457F5))),
          ],
        ),
      ),
    ),
  );
}

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFFF7F9FD),
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF2457F5),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Color(0xFF0D47A1))),
        ),
      ],
    ),
  );
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.text, this.success = false});

  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: success ? const Color(0xFFE9F5EE) : const Color(0xFFFFF6D6),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: success ? const Color(0xFFB7DCC4) : const Color(0xFFFFC107),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.info_outline_rounded,
          size: 19,
          color: success ? const Color(0xFF23633D) : const Color(0xFF775700),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: success
                  ? const Color(0xFF214C32)
                  : const Color(0xFF775700),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SampleBadge extends StatelessWidget {
  const _SampleBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6D6),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'SAMPLE',
      style: TextStyle(
        color: Color(0xFF775700),
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: .5,
      ),
    ),
  );
}

enum _CandidateLayout { gallery, compact }

class _ElectionPosition {
  const _ElectionPosition({
    required this.id,
    required this.title,
    required this.candidates,
  });

  final String id;
  final String title;
  final List<_ElectionCandidate> candidates;
}

class _ElectionCandidate {
  const _ElectionCandidate({
    required this.id,
    required this.name,
    required this.course,
    required this.slogan,
    required this.manifesto,
    required this.color,
    required this.sampleResult,
  });

  final String id;
  final String name;
  final String course;
  final String slogan;
  final String manifesto;
  final Color color;
  final int sampleResult;
}
