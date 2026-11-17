import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class CafeteriaScreen extends StatefulWidget {
  const CafeteriaScreen({super.key});

  @override
  State<CafeteriaScreen> createState() => _CafeteriaScreenState();
}

class _CafeteriaScreenState extends State<CafeteriaScreen> {
  static const List<String> _categories = [
    'Popular',
    'Meals',
    'Snacks',
    'Drinks',
  ];

  late Future<List<_MealItem>> _menuFuture;
  String _selectedCategory = 'Popular';

  @override
  void initState() {
    super.initState();
    _menuFuture = _loadMenu();
  }

  Future<List<_MealItem>> _loadMenu() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    return const [
      _MealItem(
        name: 'The N4 Kota',
        description: 'Campus favorite quarter kota combo.',
        price: 'R 35.00',
        icon: Icons.fastfood,
        color: Color(0xFFFF8F00),
        categories: ['Popular', 'Meals'],
      ),
      _MealItem(
        name: 'Vetkoek & Mince',
        description: 'Freshly baked vetkoek with savory mince filling.',
        price: 'R 25.00',
        icon: Icons.breakfast_dining,
        color: Color(0xFF6D4C41),
        categories: ['Popular', 'Snacks'],
      ),
      _MealItem(
        name: 'Beef Stew Plate',
        description: 'Hearty stew with starch and sides.',
        price: 'R 45.00',
        icon: Icons.restaurant,
        color: Color(0xFFE53935),
        categories: ['Meals'],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: FloatingActionButton.extended(
          onPressed: _openCheckoutSheet,
          backgroundColor: const Color(0xFF2962FF),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.shopping_cart_checkout),
          label: const Text(
            '1 Item - R 35.00',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: FutureBuilder<List<_MealItem>>(
        future: _menuFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() => _menuFuture = _loadMenu());
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry cafeteria load'),
              ),
            );
          }

          final allMeals = snapshot.data!;
          final meals = allMeals
              .where((meal) => meal.categories.contains(_selectedCategory))
              .toList();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 210,
                backgroundColor: const Color(0xFF0D47A1),
                title: const Text('Cafeteria Pre-Orders'),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    padding: const EdgeInsets.fromLTRB(16, 92, 16, 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF2962FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: _buildHeaderBanner(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final selected = category == _selectedCategory;
                        return ChoiceChip(
                          label: Text(category),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = category);
                          },
                          showCheckmark: false,
                          selectedColor: const Color(0xFF2962FF),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: selected
                                  ? const Color(0xFF2962FF)
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.builder(
                  itemCount: meals.length,
                  itemBuilder: (context, index) =>
                      _MealCard(meal: meals[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Campus Main Cafeteria',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Sample menu • ordering is not connected',
            style: TextStyle(
              color: Color(0xFFB9F6CA),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Browse the menu preview and sample checkout.',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCheckoutSheet() async {
    String selectedMethod = 'PayFast (Card/EFT)';
    bool isPaying = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const Text(
                    'Demo checkout',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Summary: The N4 Kota (x1)',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Total: R 35.00',
                          style: TextStyle(
                            color: Color(0xFF2962FF),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Sample payment option:',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...[
                    'PayFast (Card/EFT)',
                    'Student Account/Bursary',
                    'Cash on Collection',
                  ].map(
                    (method) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(method),
                      value: method,
                      groupValue: selectedMethod,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedMethod = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isPaying
                          ? null
                          : () async {
                              setSheetState(() => isPaying = true);
                              await Future<void>.delayed(
                                const Duration(milliseconds: 1500),
                              );
                              if (!mounted) {
                                return;
                              }
                              // ignore: use_build_context_synchronously
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF2E7D32),
                                  content: Text(
                                    'Demo only: no payment or cafeteria order was sent.',
                                  ),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2962FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isPaying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Preview order',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 210,
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(16, 92, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, _) => Container(
                    width: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverList.builder(
              itemCount: 3,
              itemBuilder: (_, _) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal});

  final _MealItem meal;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: meal.color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(meal.icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.name,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meal.description,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      meal.price,
                      style: TextStyle(
                        color: meal.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Added to cart for quick checkout.'),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: meal.color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealItem {
  const _MealItem({
    required this.name,
    required this.description,
    required this.price,
    required this.icon,
    required this.color,
    required this.categories,
  });

  final String name;
  final String description;
  final String price;
  final IconData icon;
  final Color color;
  final List<String> categories;
}
