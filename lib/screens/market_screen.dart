import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

Map<String, dynamic> mapProductRowToMarketItem(Map<String, dynamic> row) {
  final title = (row['title'] ?? '').toString();
  final price = (row['price'] is num) ? (row['price'] as num).toDouble() : double.tryParse(row['price'].toString()) ?? 0;
  final createdAt = (row['created_at'] ?? '').toString();
  final rawProfiles = row['profiles'];
  final profiles = rawProfiles is Map ? Map<String, dynamic>.from(rawProfiles) : <String, dynamic>{};
  final name = (profiles['name'] ?? '').toString().trim();
  final surname = (profiles['surname'] ?? '').toString().trim();
  final sellerName = [name, surname].where((part) => part.isNotEmpty).join(' ').trim();
  final category = (row['category'] ?? 'General').toString();
  final created = DateTime.tryParse(createdAt);

  return {
    'title': title.isEmpty ? 'Untitled listing' : title,
    'price': 'R ${price.toStringAsFixed(2)}',
    'seller': sellerName.isEmpty ? 'Campus seller' : sellerName,
    'category': category,
    'time': created == null ? 'Recently added' : _relativeTime(created),
    'icon': _iconForCategory(category),
    'accent': _accentForCategory(category),
  };
}

String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inDays > 0) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  if (diff.inHours > 0) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inMinutes > 0) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  return 'Just now';
}

IconData _iconForCategory(String category) {
  switch (category.toLowerCase()) {
    case 'textbooks':
      return Icons.menu_book_rounded;
    case 'clothing/uniforms':
    case 'clothing':
      return Icons.checkroom_rounded;
    case 'appliances':
      return Icons.kitchen_rounded;
    case 'stationery':
      return Icons.straighten_rounded;
    case 'study tools':
      return Icons.calculate_rounded;
    default:
      return Icons.shopping_bag_outlined;
  }
}

Color _accentForCategory(String category) {
  switch (category.toLowerCase()) {
    case 'textbooks':
      return const Color(0xFF2962FF);
    case 'clothing/uniforms':
    case 'clothing':
      return const Color(0xFF00ACC1);
    case 'appliances':
      return const Color(0xFFFF8F00);
    case 'stationery':
      return const Color(0xFF6A1B9A);
    case 'study tools':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF5E35B1);
  }
}

class _MarketScreenState extends State<MarketScreen> {
  late Future<List<Map<String, dynamic>>> _marketFuture;

  @override
  void initState() {
    super.initState();
    _marketFuture = _loadMarketItems();
  }

  Future<List<Map<String, dynamic>>> _loadMarketItems() async {
    final response = await Supabase.instance.client
        .from('products')
        .select('id, title, price, category, description, created_at, images, seller_id, profiles!products_seller_id_fkey(name, surname)')
        .eq('status', 'available')
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response as List<dynamic>);
    return rows.map(mapProductRowToMarketItem).toList();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Student Marketplace')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _marketFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildShimmerLoading();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _marketFuture = _loadMarketItems();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry marketplace load'),
              ),
            );
          }

          final items = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              children: [
                _buildSafetyBanner(),
                const SizedBox(height: 12),
                Expanded(child: _buildMarketGrid(items)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSafetyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7043), Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF7043).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_user_outlined, color: Colors.white),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Meet in public campus zones. Use secure in-app chat for deals.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketGrid(List<Map<String, dynamic>> items) {
    return AnimationLimiter(
      child: GridView.builder(
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return AnimationConfiguration.staggeredGrid(
            position: index,
            columnCount: 2,
            duration: const Duration(milliseconds: 420),
            child: ScaleAnimation(
              child: FadeInAnimation(
                child: _buildProductCard(item),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item) {
    final title = item['title'] as String;
    final price = item['price'] as String;
    final seller = item['seller'] as String;
    final category = item['category'] as String;
    final time = item['time'] as String;
    final icon = item['icon'] as IconData;
    final accent = item['accent'] as Color;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 84,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 38, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              category,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Text(
            seller,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            time,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Opening secure chat with seller...'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Message Seller'),
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
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, _) {
                  return Container(
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
