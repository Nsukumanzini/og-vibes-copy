import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({super.key});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late Future<Map<String, String>> _productFuture;

  @override
  void initState() {
    super.initState();
    _productFuture = _loadProduct();
  }

  Future<Map<String, String>> _loadProduct() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));

    return const {
      'title': 'N4 Mathematics Textbook',
      'price': 'R 200',
      'seller': 'Thandi M.',
      'condition': 'Good Condition',
      'description':
          'Used it last semester. Has some highlighted formulas but no missing pages. Meeting at the cafeteria.',
      'category': 'Textbooks',
      'campus': 'Gert Sibande - Ermelo Campus',
    };
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Listing Details')),
      body: FutureBuilder<Map<String, String>>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoading();
          }
          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _productFuture = _loadProduct();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry product load'),
              ),
            );
          }

          final data = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            child: Column(
              children: [
                _buildImagePlaceholder(),
                const SizedBox(height: 12),
                _buildDetailsCard(data),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Opening secure chat with seller...'),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message Seller'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF2457F5), Color(0xFF2457F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 72),
      ),
    );
  }

  Widget _buildDetailsCard(Map<String, String> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['title']!,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data['price']!,
            style: const TextStyle(
              color: Color(0xFF2457F5),
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.category_outlined, data['category']!),
              _chip(Icons.school_outlined, data['campus']!),
              _chip(Icons.auto_fix_high, data['condition']!),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Description',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data['description']!,
            style: TextStyle(
              color: Colors.grey.shade700,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2457F5).withValues(alpha: 0.15),
              child: const Icon(Icons.person, color: Color(0xFF2457F5)),
            ),
            title: Text(
              data['seller']!,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Trusted campus marketplace seller'),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2457F5).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2457F5)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2457F5),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 230,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
