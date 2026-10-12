import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final List<CampusEvent> _events = <CampusEvent>[];
  final Set<String> _attendingEventIds = <String>{};
  final List<EventInvitation> _invitations = <EventInvitation>[];
  final List<StudentFriend> _friends = <StudentFriend>[];

  bool _loading = true;
  String? _error;
  String _filterType = 'all';
  String? _filterValue;

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadEvents();
    final eventId = Uri.base.queryParameters['event_id'];
    if (eventId != null && mounted) {
      final event = _eventById(eventId);
      if (event != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEventDetails(event);
        });
      }
    }
  }

  Future<void> _loadEvents({bool showLoader = true}) async {
    final user = _user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to discover campus events.';
      });
      return;
    }
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final responses = await Future.wait<dynamic>(<Future<dynamic>>[
        _supabase
            .from('events')
            .select(
              'id, title, date_label, venue, price, image_url, contact, '
              'date, created_at, description, end_date, campus, '
              'organisation, club, faculty, category, organizer_name, '
              'agenda, accessibility, capacity, attendee_count, status, '
              'accent_color, updated_at',
            )
            .order('date'),
        _supabase
            .from('event_attendees')
            .select('event_id, user_id, created_at')
            .eq('user_id', user.id),
        _supabase
            .from('event_invitations')
            .select(
              'id, event_id, sender_id, receiver_id, message, status, '
              'created_at, responded_at',
            )
            .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
            .order('created_at', ascending: false),
        _supabase
            .from('friendships')
            .select('user_id, friend_id')
            .or('user_id.eq.${user.id},friend_id.eq.${user.id}'),
      ]);

      final events = List<Map<String, dynamic>>.from(
        responses[0] as List<dynamic>,
      ).map(CampusEvent.fromRow).toList();
      final attendanceRows =
          List<Map<String, dynamic>>.from(responses[1] as List<dynamic>);
      final invitations = List<Map<String, dynamic>>.from(
        responses[2] as List<dynamic>,
      ).map(EventInvitation.fromRow).toList();
      final friendshipRows =
          List<Map<String, dynamic>>.from(responses[3] as List<dynamic>);
      final friendIds = friendshipRows.map((row) {
        final first = row['user_id'].toString();
        return first == user.id ? row['friend_id'].toString() : first;
      }).toSet().toList();
      final friends = await _loadFriendProfiles(friendIds);

      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(events);
        _attendingEventIds
          ..clear()
          ..addAll(
            attendanceRows.map((row) => row['event_id'].toString()),
          );
        _invitations
          ..clear()
          ..addAll(invitations);
        _friends
          ..clear()
          ..addAll(friends);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<List<StudentFriend>> _loadFriendProfiles(List<String> ids) async {
    if (ids.isEmpty) return <StudentFriend>[];
    final rows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('profiles')
          .select('id, name, surname, nickname, photo_url, campus, department')
          .inFilter('id', ids) as List<dynamic>,
    );
    return rows.map(StudentFriend.fromRow).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  CampusEvent? _eventById(String id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  List<CampusEvent> get _filteredEvents {
    final now = DateTime.now();
    return _events.where((event) {
      if (event.status == 'completed' || event.date.isBefore(now)) {
        return false;
      }
      if (_filterType == 'all' || _filterValue == null) return true;
      return event.filterValue(_filterType) == _filterValue;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<String> get _filterOptions {
    if (_filterType == 'all') return <String>[];
    final values = _events
        .map((event) => event.filterValue(_filterType))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  int get _upcomingCount => _events
      .where(
        (event) =>
            event.date.isAfter(DateTime.now()) &&
            event.status != 'cancelled' &&
            event.status != 'completed',
      )
      .length;

  int get _pendingInvitationCount => _invitations
      .where(
        (invitation) =>
            invitation.receiverId == _user?.id &&
            invitation.status == 'pending',
      )
      .length;

  Future<void> _toggleAttendance(CampusEvent event) async {
    final user = _user;
    if (user == null) return;
    final attending = _attendingEventIds.contains(event.id);
    HapticFeedback.mediumImpact();
    try {
      if (attending) {
        await _supabase
            .from('event_attendees')
            .delete()
            .eq('event_id', event.id)
            .eq('user_id', user.id);
      } else {
        await _supabase.from('event_attendees').insert(<String, dynamic>{
          'event_id': event.id,
          'user_id': user.id,
        });
      }
      await _loadEvents(showLoader: false);
    } catch (error) {
      _showError(
        attending ? 'Unable to cancel attendance' : 'Unable to attend event',
        error,
      );
    }
  }

  Future<void> _shareEvent(CampusEvent event) async {
    HapticFeedback.selectionClick();
    final link =
        'https://og-vibes.vercel.app/?event_id=${Uri.encodeQueryComponent(event.id)}';
    await Share.share(
      '${event.title}\n'
      '${event.formattedDate} • ${event.venue}\n'
      '${event.price}\n\n'
      'View on OG Vibes: $link',
    );
  }

  Future<void> _inviteFriends(CampusEvent event) async {
    if (_friends.isEmpty) {
      _showMessage('Add friends before sending event invitations.');
      return;
    }
    final alreadyInvited = _invitations
        .where(
          (invite) =>
              invite.eventId == event.id &&
              invite.senderId == _user?.id,
        )
        .map((invite) => invite.receiverId)
        .toSet();
    final selected = <String>{};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Invite friends to ${event.title}',
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose friends who may enjoy this event.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height * .42)
                      .clamp(180.0, 420.0)
                      .toDouble(),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    itemBuilder: (_, index) {
                      final friend = _friends[index];
                      final invited = alreadyInvited.contains(friend.id);
                      return CheckboxListTile(
                        value: invited || selected.contains(friend.id),
                        enabled: !invited,
                        contentPadding: EdgeInsets.zero,
                        secondary: _FriendAvatar(friend: friend),
                        title: Text(
                          friend.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          invited
                              ? 'Invitation already sent'
                              : friend.subtitle,
                        ),
                        onChanged: (checked) {
                          setSheetState(() {
                            if (checked == true) {
                              selected.add(friend.id);
                            } else {
                              selected.remove(friend.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, selected),
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      'Send ${selected.length} '
                      '${selected.length == 1 ? 'invitation' : 'invitations'}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || result.isEmpty || _user == null) return;

    try {
      await _supabase.from('event_invitations').insert(
            result
                .map(
                  (friendId) => <String, dynamic>{
                    'event_id': event.id,
                    'sender_id': _user!.id,
                    'receiver_id': friendId,
                    'message': 'Join me at ${event.title}',
                  },
                )
                .toList(),
          );
      await _loadEvents(showLoader: false);
      _showMessage('Event invitations sent.');
    } catch (error) {
      _showError('Unable to send invitations', error);
    }
  }

  Future<void> _showEventDetails(CampusEvent event) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .88,
        minChildSize: .6,
        maxChildSize: .96,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: <Widget>[
            _EventBanner(event: event, height: 220),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        event.title,
                        style: const TextStyle(
                          color: AppColors.midnightInk,
                          fontSize: 25,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        event.organizerName,
                        style: TextStyle(
                          color: event.accentColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                _EventStatusPill(event: event),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _DetailChip(
                  icon: Icons.calendar_today_outlined,
                  label: event.formattedDate,
                ),
                _DetailChip(
                  icon: Icons.schedule_outlined,
                  label: event.formattedTime,
                ),
                _DetailChip(
                  icon: Icons.location_on_outlined,
                  label: event.venue,
                ),
                _DetailChip(
                  icon: Icons.payments_outlined,
                  label: event.price,
                ),
              ],
            ),
            if (event.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              const _SectionHeading(
                icon: Icons.notes_rounded,
                title: 'About this event',
              ),
              const SizedBox(height: 9),
              Text(
                event.description,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
              ),
            ],
            if (event.agenda.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              const _SectionHeading(
                icon: Icons.format_list_bulleted_rounded,
                title: 'Programme',
              ),
              const SizedBox(height: 10),
              ...event.agenda.asMap().entries.map(
                    (entry) => _AgendaItem(
                      index: entry.key + 1,
                      value: entry.value,
                      color: event.accentColor,
                    ),
                  ),
            ],
            const SizedBox(height: 24),
            const _SectionHeading(
              icon: Icons.info_outline_rounded,
              title: 'Event information',
            ),
            const SizedBox(height: 10),
            _InfoRow(label: 'Campus', value: event.campus),
            if (event.organisation.isNotEmpty)
              _InfoRow(label: 'Organisation', value: event.organisation),
            if (event.club.isNotEmpty)
              _InfoRow(label: 'Club', value: event.club),
            if (event.faculty.isNotEmpty)
              _InfoRow(label: 'Faculty', value: event.faculty),
            if (event.contact.isNotEmpty)
              _InfoRow(label: 'Contact', value: event.contact),
            if (event.accessibility.isNotEmpty)
              _InfoRow(
                label: 'Accessibility',
                value: event.accessibility,
              ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareEvent(event),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _inviteFriends(event);
                    },
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Invite'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_attendingEventIds.contains(event.id) || event.canAttend)
                    ? () {
                        Navigator.pop(context);
                        _toggleAttendance(event);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: event.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: Icon(
                  _attendingEventIds.contains(event.id)
                      ? Icons.check_circle_rounded
                      : Icons.event_available_outlined,
                ),
                label: Text(
                  _attendingEventIds.contains(event.id)
                      ? 'You’re going • Cancel attendance'
                      : event.isFull
                          ? 'Event is full'
                          : 'I’m going',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text(
          'Events',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh events',
            onPressed: () => _loadEvents(showLoader: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.vibeBlue),
            )
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: () => _loadEvents(showLoader: false),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final desktop = constraints.maxWidth >= 980;
                      return CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: <Widget>[
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              desktop ? 34 : 16,
                              8,
                              desktop ? 34 : 16,
                              16,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1180),
                                  child: Column(
                                    children: <Widget>[
                                      _buildHero(desktop: desktop),
                                      const SizedBox(height: 16),
                                      _buildFilters(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildEventGrid(desktop: desktop),
                          const SliverToBoxAdapter(child: SizedBox(height: 40)),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildHero({required bool desktop}) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hero = Container(
      width: double.infinity,
      padding: EdgeInsets.all(desktop ? 28 : 22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: desktop
          ? Row(
              children: <Widget>[
                const Expanded(child: _HeroCopy()),
                const SizedBox(width: 24),
                _HeroArtwork(count: _upcomingCount),
                const SizedBox(width: 24),
                _buildHeroMetrics(),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _HeroCopy(),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    _HeroArtwork(count: _upcomingCount, compact: true),
                    const SizedBox(width: 14),
                    Expanded(child: _buildHeroMetrics()),
                  ],
                ),
              ],
            ),
    );
    return reduceMotion
        ? hero
        : hero.animate().fadeIn(duration: 420.ms).slideY(begin: .07, end: 0);
  }

  Widget _buildHeroMetrics() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _HeroMetric(
          icon: Icons.calendar_month_outlined,
          value: '$_upcomingCount',
          label: 'Upcoming',
        ),
        _HeroMetric(
          icon: Icons.event_available_outlined,
          value: '${_attendingEventIds.length}',
          label: 'Attending',
        ),
        _HeroMetric(
          icon: Icons.mail_outline_rounded,
          value: '$_pendingInvitationCount',
          label: 'Invites',
          highlight: _pendingInvitationCount > 0,
        ),
      ],
    );
  }

  Widget _buildFilters() {
    const filters = <(String, String, IconData)>[
      ('all', 'All', Icons.grid_view_rounded),
      ('campus', 'Campus', Icons.location_city_outlined),
      ('organisation', 'Organisation', Icons.apartment_outlined),
      ('club', 'Club', Icons.groups_2_outlined),
      ('faculty', 'Faculty', Icons.school_outlined),
    ];
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((filter) {
                final selected = _filterType == filter.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    avatar: Icon(
                      filter.$3,
                      size: 17,
                      color:
                          selected ? Colors.white : AppColors.textMuted,
                    ),
                    label: Text(filter.$2),
                    selectedColor: AppColors.midnightInk,
                    labelStyle: TextStyle(
                      color:
                          selected ? Colors.white : AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _filterType = filter.$1;
                        _filterValue = null;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          if (_filterType != 'all' && _filterOptions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _filterValue,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Choose ${_filterType.toLowerCase()}',
                prefixIcon: const Icon(Icons.tune_rounded),
              ),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem(
                  value: null,
                  child: Text('Show all'),
                ),
                ..._filterOptions.map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _filterValue = value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventGrid({required bool desktop}) {
    final events = _filteredEvents;
    if (events.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(
          icon: Icons.event_busy_outlined,
          title: _events.isEmpty
              ? 'No events published yet'
              : 'No events match this filter',
          subtitle: _events.isEmpty
              ? 'New campus experiences will appear here when organisers publish them.'
              : 'Try another campus, organisation, club, or faculty.',
          onReset: () => setState(() {
            _filterType = 'all';
            _filterValue = null;
          }),
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: desktop ? 34 : 16),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1040
                    ? 3
                    : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                final width =
                    (constraints.maxWidth - ((columns - 1) * 14)) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: List<Widget>.generate(events.length, (index) {
                    final event = events[index];
                    final card = SizedBox(
                      width: width,
                      child: _EventCard(
                        event: event,
                        attending: _attendingEventIds.contains(event.id),
                        onTap: () => _showEventDetails(event),
                        onShare: () => _shareEvent(event),
                        onInvite: () => _inviteFriends(event),
                      ),
                    );
                    if (MediaQuery.disableAnimationsOf(context)) return card;
                    return card
                        .animate(delay: (index * 45).ms)
                        .fadeIn(duration: 320.ms)
                        .slideY(begin: .06, end: 0);
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return _EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Events could not load',
      subtitle: _error!,
      onReset: _loadEvents,
      actionLabel: 'Try again',
    );
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  void _showError(String title, Object error) {
    _showMessage('$title: ${_friendlyError(error)}');
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Socket') || text.contains('Network')) {
      return 'Check your connection and try again.';
    }
    if (text.contains('row-level security') ||
        text.contains('permission denied')) {
      return 'You do not have permission for this action.';
    }
    return text.replaceFirst('PostgrestException(message: ', '').split(',').first;
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .8),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .88)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.attending,
    required this.onTap,
    required this.onShare,
    required this.onInvite,
  });

  final CampusEvent event;
  final bool attending;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${event.title}, ${event.formattedDate}, ${event.venue}, ${event.price}',
      child: _GlassCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  _EventBanner(event: event, height: 174),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _EventStatusPill(event: event),
                  ),
                  if (attending)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: AppStyles.pillRadius,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'GOING',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      event.category.toUpperCase(),
                      style: TextStyle(
                        color: event.accentColor,
                        fontSize: 9,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 11),
                    _CompactDetail(
                      icon: Icons.calendar_today_outlined,
                      value: '${event.formattedDate} • ${event.formattedTime}',
                    ),
                    const SizedBox(height: 7),
                    _CompactDetail(
                      icon: Icons.location_on_outlined,
                      value: '${event.venue} • ${event.campus}',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            event.price,
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _IconAction(
                          tooltip: 'Share event',
                          icon: Icons.share_outlined,
                          onTap: onShare,
                        ),
                        const SizedBox(width: 6),
                        _IconAction(
                          tooltip: 'Invite friends',
                          icon: Icons.group_add_outlined,
                          onTap: onInvite,
                        ),
                      ],
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
}

class _EventBanner extends StatelessWidget {
  const _EventBanner({
    required this.event,
    required this.height,
  });

  final CampusEvent event;
  final double height;

  @override
  Widget build(BuildContext context) {
    final image = event.imageUrl;
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            event.accentColor,
            AppColors.midnightInk,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: image == null
          ? Stack(
              children: <Widget>[
                Positioned(
                  right: -18,
                  bottom: -28,
                  child: Icon(
                    Icons.celebration_rounded,
                    size: 150,
                    color: Colors.white.withValues(alpha: .11),
                  ),
                ),
                Center(
                  child: Icon(
                    event.categoryIcon,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ],
            )
          : Image.network(
              image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Icon(
                  event.categoryIcon,
                  color: Colors.white,
                  size: 52,
                ),
              ),
            ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bolt_rounded,
              color: AppColors.electricCyan,
              size: 18,
            ),
            SizedBox(width: 7),
            Text(
              'OG CAMPUS EXPERIENCES',
              style: TextStyle(
                color: AppColors.electricCyan,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
        Text(
          'There’s more to\ncampus than class.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 9),
        Text(
          'Discover memorable events across your campus community.',
          style: TextStyle(
            color: Colors.white70,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 96.0 : 122.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .09),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.celebration_rounded,
            color: AppColors.electricCyan,
            size: 30,
          ),
          const SizedBox(height: 5),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'UPCOMING',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 8,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(15),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventStatusPill extends StatelessWidget {
  const _EventStatusPill({required this.event});

  final CampusEvent event;

  @override
  Widget build(BuildContext context) {
    final color = event.status == 'cancelled'
        ? AppColors.danger
        : event.status == 'postponed'
            ? AppColors.warning
            : event.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        event.status.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
  });

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
          Text(
            label,
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactDetail extends StatelessWidget {
  const _CompactDetail({
    required this.icon,
    required this.value,
  });

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
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
  });

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

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({
    required this.index,
    required this.value,
    required this.color,
  });

  final int index;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                value,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4F9),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.midnightInk, size: 18),
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.friend});

  final StudentFriend friend;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: AppColors.vibeBlue.withValues(alpha: .12),
      backgroundImage:
          friend.photoUrl == null ? null : NetworkImage(friend.photoUrl!),
      child: friend.photoUrl == null
          ? Text(
              friend.initials,
              style: const TextStyle(
                color: AppColors.vibeBlue,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onReset,
    this.actionLabel = 'Reset filters',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onReset;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.vibeBlue, size: 36),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class CampusEvent {
  const CampusEvent({
    required this.id,
    required this.title,
    required this.venue,
    required this.price,
    required this.imageUrl,
    required this.contact,
    required this.date,
    required this.description,
    required this.endDate,
    required this.campus,
    required this.organisation,
    required this.club,
    required this.faculty,
    required this.category,
    required this.organizerName,
    required this.agenda,
    required this.accessibility,
    required this.capacity,
    required this.attendeeCount,
    required this.status,
    required this.accentHex,
  });

  factory CampusEvent.fromRow(Map<String, dynamic> row) => CampusEvent(
        id: row['id'].toString(),
        title: row['title']?.toString().trim() ?? 'Campus event',
        venue: row['venue']?.toString().trim() ?? 'Campus venue',
        price: row['price']?.toString().trim() ?? 'Free',
        imageUrl: _optional(row['image_url']),
        contact: row['contact']?.toString().trim() ?? '',
        date: _date(row['date']),
        description: row['description']?.toString().trim() ?? '',
        endDate: DateTime.tryParse(row['end_date']?.toString() ?? '')?.toLocal(),
        campus: row['campus']?.toString().trim() ?? 'All campuses',
        organisation: row['organisation']?.toString().trim() ?? '',
        club: row['club']?.toString().trim() ?? '',
        faculty: row['faculty']?.toString().trim() ?? '',
        category: row['category']?.toString().trim() ?? 'Campus life',
        organizerName:
            row['organizer_name']?.toString().trim() ?? 'OG Vibes',
        agenda: List<String>.from(
          row['agenda'] as List<dynamic>? ?? <dynamic>[],
        ),
        accessibility: row['accessibility']?.toString().trim() ?? '',
        capacity: int.tryParse(row['capacity']?.toString() ?? ''),
        attendeeCount:
            int.tryParse(row['attendee_count']?.toString() ?? '') ?? 0,
        status: row['status']?.toString() ?? 'scheduled',
        accentHex: row['accent_color']?.toString() ?? '#2457F5',
      );

  final String id;
  final String title;
  final String venue;
  final String price;
  final String? imageUrl;
  final String contact;
  final DateTime date;
  final String description;
  final DateTime? endDate;
  final String campus;
  final String organisation;
  final String club;
  final String faculty;
  final String category;
  final String organizerName;
  final List<String> agenda;
  final String accessibility;
  final int? capacity;
  final int attendeeCount;
  final String status;
  final String accentHex;

  Color get accentColor => _hexColor(accentHex);
  bool get isFull => capacity != null && attendeeCount >= capacity!;
  bool get canAttend =>
      !isFull &&
      date.isAfter(DateTime.now()) &&
      (status == 'scheduled' || status == 'postponed');

  String filterValue(String type) => switch (type) {
        'campus' => campus,
        'organisation' => organisation,
        'club' => club,
        'faculty' => faculty,
        _ => '',
      };

  String get formattedDate {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String get formattedTime {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  IconData get categoryIcon {
    final value = category.toLowerCase();
    if (value.contains('sport')) return Icons.sports_basketball_outlined;
    if (value.contains('career')) return Icons.work_outline_rounded;
    if (value.contains('music')) return Icons.music_note_rounded;
    if (value.contains('academic')) return Icons.school_outlined;
    if (value.contains('wellness')) return Icons.favorite_outline_rounded;
    return Icons.celebration_outlined;
  }
}

class EventInvitation {
  const EventInvitation({
    required this.id,
    required this.eventId,
    required this.senderId,
    required this.receiverId,
    required this.status,
  });

  factory EventInvitation.fromRow(Map<String, dynamic> row) => EventInvitation(
        id: row['id'].toString(),
        eventId: row['event_id'].toString(),
        senderId: row['sender_id'].toString(),
        receiverId: row['receiver_id'].toString(),
        status: row['status']?.toString() ?? 'pending',
      );

  final String id;
  final String eventId;
  final String senderId;
  final String receiverId;
  final String status;
}

class StudentFriend {
  const StudentFriend({
    required this.id,
    required this.displayName,
    required this.photoUrl,
    required this.campus,
    required this.department,
  });

  factory StudentFriend.fromRow(Map<String, dynamic> row) {
    final nickname = row['nickname']?.toString().trim() ?? '';
    final fullName = '${row['name'] ?? ''} ${row['surname'] ?? ''}'.trim();
    return StudentFriend(
      id: row['id'].toString(),
      displayName: nickname.isNotEmpty
          ? nickname
          : fullName.isNotEmpty
              ? fullName
              : 'OG Student',
      photoUrl: _optional(row['photo_url']),
      campus: row['campus']?.toString().trim() ?? '',
      department: row['department']?.toString().trim() ?? '',
    );
  }

  final String id;
  final String displayName;
  final String? photoUrl;
  final String campus;
  final String department;

  String get initials => displayName
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word[0].toUpperCase())
      .join();
  String get subtitle => <String>[campus, department]
      .where((value) => value.isNotEmpty)
      .join(' • ');
}

DateTime _date(dynamic value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();

String? _optional(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

Color _hexColor(String value) {
  final clean = value.replaceAll('#', '');
  final parsed = int.tryParse(clean, radix: 16) ?? 0x2457F5;
  return Color(0xFF000000 | parsed);
}
