import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class LiftClubScreen extends StatefulWidget {
  const LiftClubScreen({super.key});

  @override
  State<LiftClubScreen> createState() => _LiftClubScreenState();
}

class _LiftClubScreenState extends State<LiftClubScreen> {
  late Future<List<Map<String, dynamic>>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    _ridesFuture = _loadRides();
  }

  Future<List<Map<String, dynamic>>> _loadRides() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    return const [
      {
        'route': 'Secunda to Ermelo Campus',
        'driver': 'Mr. Vusi (Verified Student)',
        'departure': 'Tomorrow, 06:00 AM',
        'seats': 2,
        'price': 'R 80',
        'verified': true,
      },
      {
        'route': 'Breyten to Ermelo Campus',
        'driver': 'Sarah T.',
        'departure': 'Friday, 07:30 AM',
        'seats': 3,
        'price': 'R 30',
        'verified': true,
      },
      {
        'route': 'Ermelo Campus to Bushbuckridge (Weekend Trip)',
        'driver': 'John D.',
        'departure': 'Friday, 14:00 PM',
        'seats': 1,
        'price': 'R 250',
        'verified': true,
      },
      {
        'route': 'Ermelo CBD to Campus Morning Shuttle',
        'driver': 'Amanda L.',
        'departure': 'Weekdays, 06:45 AM',
        'seats': 4,
        'price': 'R 20',
        'verified': true,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Lift Club')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ridesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildShimmerLoading();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _ridesFuture = _loadRides();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry rides load'),
              ),
            );
          }

          final rides = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 12),
                Expanded(child: _buildRideList(rides)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2962FF), Color(0xFF00ACC1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2962FF).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Safe Student Rides',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'All rides below are from verified drivers around Ermelo TVET routes.',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideList(List<Map<String, dynamic>> rides) {
    return AnimationLimiter(
      child: ListView.separated(
        itemCount: rides.length,
        separatorBuilder: (context, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ride = rides[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 420),
            child: SlideAnimation(
              verticalOffset: 20,
              child: FadeInAnimation(child: _buildRideCard(ride)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final route = ride['route'] as String;
    final driver = ride['driver'] as String;
    final departure = ride['departure'] as String;
    final seats = ride['seats'] as int;
    final price = ride['price'] as String;
    final verified = ride['verified'] as bool;

    final seatColor = seats <= 1
        ? const Color(0xFFE53935)
        : const Color(0xFF2E7D32);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route_rounded, color: Color(0xFF2962FF)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  route,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                driver,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              if (verified)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, color: Color(0xFF2E7D32), size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Verified',
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Departure: $departure',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: seatColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Seats: $seats',
                  style: TextStyle(
                    color: seatColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                price,
                style: const TextStyle(
                  color: Color(0xFF2962FF),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seat request sent to driver!')),
                );
              },
              icon: const Icon(Icons.event_seat_outlined),
              label: const Text('Request Seat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2962FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: 4,
                separatorBuilder: (context, _) => const SizedBox(height: 12),
                itemBuilder: (context, _) {
                  return Container(
                    height: 184,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
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
}
