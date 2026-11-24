import 'dart:async';
import '../widgets/glass_card.dart';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class CafeteriaScreen extends StatefulWidget {
  const CafeteriaScreen({super.key});

  @override
  State<CafeteriaScreen> createState() => _CafeteriaScreenState();
}

class _CafeteriaScreenState extends State<CafeteriaScreen> {
  static const _categories = ['Popular', 'Meals', 'Snacks', 'Drinks'];
  static const _pickupTimes = [
    '12:15 – 12:30',
    '12:30 – 12:45',
    '12:45 – 13:00',
  ];
  static const _sampleMenu = <_MealItem>[
    _MealItem(
      id: 'n4-kota',
      name: 'The N4 Kota',
      description: 'Quarter loaf, chips, cheese, sausage and house sauce.',
      price: 35,
      image: 'assets/images/cafeteria/kota.jpg',
      categories: ['Popular', 'Meals'],
      prepMinutes: 10,
      rating: 4.9,
      isPopular: true,
      accent: Color(0xFFE77619),
    ),
    _MealItem(
      id: 'vetkoek-mince',
      name: 'Vetkoek & Mince',
      description: 'Golden vetkoek filled with savory mince.',
      price: 25,
      image: 'assets/images/cafeteria/vetkoek.jpg',
      categories: ['Popular', 'Snacks'],
      prepMinutes: 12,
      rating: 4.8,
      isPopular: true,
      accent: Color(0xFF8E5B3A),
    ),
    _MealItem(
      id: 'beef-stew',
      name: 'Beef Stew Plate',
      description: 'Slow-cooked beef with pap and seasonal vegetables.',
      price: 45,
      image: 'assets/images/cafeteria/stew.jpg',
      categories: ['Meals'],
      prepMinutes: 18,
      rating: 4.7,
      isPopular: false,
      accent: Color(0xFFB74432),
    ),
    _MealItem(
      id: 'chicken-toastie',
      name: 'Chicken Mayo Toastie',
      description: 'Toasted chicken and mayo sandwich.',
      price: 32,
      image: 'assets/images/cafeteria/toastie.jpg',
      categories: ['Popular', 'Snacks'],
      prepMinutes: 10,
      rating: 4.6,
      isPopular: true,
      isAvailable: false,
      icon: Icons.lunch_dining_rounded,
      accent: Color(0xFF2457F5),
    ),
    _MealItem(
      id: 'iced-rooibos',
      name: 'Iced Rooibos',
      description: 'Chilled rooibos tea with lemon.',
      price: 15,
      image: 'assets/images/cafeteria/rooibos.jpg',
      categories: ['Drinks'],
      prepMinutes: 3,
      rating: 4.5,
      isPopular: false,
      icon: Icons.local_drink_rounded,
      accent: Color(0xFFFFC107),
    ),
  ];

  late Future<List<_MealItem>> _menuFuture;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, int> _cart = {};
  String _selectedCategory = 'Popular';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _menuFuture = _loadMenu();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_MealItem>> _loadMenu() async {
    // Local sample data keeps this screen usable without a menu backend.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return _sampleMenu;
  }

  int get _cartCount => _cart.values.fold(0, (sum, count) => sum + count);

  double get _cartTotal => _sampleMenu.fold<double>(
    0,
    (total, meal) => total + meal.price * (_cart[meal.id] ?? 0),
  );

  List<_MealItem> get _cartItems => _sampleMenu
      .where((meal) => (_cart[meal.id] ?? 0) > 0)
      .toList(growable: false);

  void _changeQuantity(_MealItem meal, int delta) {
    if (!meal.isAvailable) return;
    final next = (_cart[meal.id] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _cart.remove(meal.id);
      } else {
        _cart[meal.id] = next;
      }
    });
  }

  String _price(double value) => 'R ${value.toStringAsFixed(2)}';

  bool _isCafeteriaOpen(DateTime now) {
    final weekday =
        now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
    final minutes = now.hour * 60 + now.minute;
    return weekday && minutes >= 7 * 60 + 30 && minutes < 16 * 60;
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      floatingActionButton: _cartCount == 0
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.extended(
                onPressed: _openCartSheet,
                backgroundColor: AppColors.vibeBlue,
                foregroundColor: Colors.white,
                icon: Badge(
                  label: Text('$_cartCount'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
                label: Text(
                  'View cart  ·  ${_price(_cartTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
      body: FutureBuilder<List<_MealItem>>(
        future: _menuFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _buildErrorState();
          }

          final menu = snapshot.data!;
          final meals = menu
              .where((meal) {
                final matchesCategory = _selectedCategory == 'Popular'
                    ? meal.isPopular
                    : meal.categories.contains(_selectedCategory);
                final normalizedQuery = _query.trim().toLowerCase();
                final matchesSearch =
                    normalizedQuery.isEmpty ||
                    meal.name.toLowerCase().contains(normalizedQuery) ||
                    meal.description.toLowerCase().contains(normalizedQuery);
                return matchesCategory && matchesSearch;
              })
              .toList(growable: false);
          final recommended = _query.isEmpty && _selectedCategory != 'Popular'
              ? menu
                    .where((meal) => meal.isPopular && meal.isAvailable)
                    .toList()
              : const <_MealItem>[];

          return CustomScrollView(
            slivers: [
              _buildHeroHeader(),
              SliverToBoxAdapter(child: _buildSearchField()),
              SliverToBoxAdapter(child: _buildCategories()),
              if (recommended.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildRecommendedSection(recommended),
                ),
              if (meals.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedCategory == 'Popular'
                                ? 'Popular with students'
                                : _selectedCategory,
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${meals.length} ${meals.length == 1 ? 'item' : 'items'}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 132),
                  sliver: SliverList.builder(
                    itemCount: meals.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MealCard(
                        meal: meals[index],
                        quantity: _cart[meals[index].id] ?? 0,
                        onAdd: () => _changeQuantity(meals[index], 1),
                        onRemove: () => _changeQuantity(meals[index], -1),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroHeader() {
    final open = _isCafeteriaOpen(DateTime.now());
    return SliverAppBar(
      pinned: true,
      expandedHeight: 236,
      backgroundColor: AppColors.vibeBlue,
      foregroundColor: Colors.white,
      title: const Text('Campus cafeteria'),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/cafeteria/kota.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AppColors.deepBlue,
                child: Icon(
                  Icons.restaurant_rounded,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .3, 1],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Campus Main Cafeteria',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                shadows: const [
                                  Shadow(blurRadius: 12, color: Colors.black87),
                                ],
                              ),
                        ),
                      ),
                      _OpenStatusBadge(isOpen: open),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mon–Fri  ·  07:30–16:00  ·  Sample menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search the menu',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
    ),
  );

  Widget _buildCategories() => SizedBox(
    height: 52,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      scrollDirection: Axis.horizontal,
      itemCount: _categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = _categories[index];
        final selected = category == _selectedCategory;
        return ChoiceChip(
          label: Text(category),
          selected: selected,
          onSelected: (_) => setState(() => _selectedCategory = category),
          showCheckmark: false,
          selectedColor: AppColors.vibeBlue,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.midnightInk,
            fontWeight: FontWeight.w800,
          ),
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? AppColors.vibeBlue : AppColors.glassBorder,
            ),
          ),
        );
      },
    ),
  );

  Widget _buildRecommendedSection(List<_MealItem> recommended) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 4, 18, 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: AppColors.ogGold),
              SizedBox(width: 8),
              Text(
                'Student favourites',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 255,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: recommended.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _RecommendedCard(
              meal: recommended[index],
              onAdd: () => _changeQuantity(recommended[index], 1),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 18, 28, 100),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.search_off_rounded,
          size: 54,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 14),
        Text(
          _query.isEmpty
              ? 'Nothing in this category yet'
              : 'No menu matches found',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.midnightInk,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Try another category or clear your search.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
        if (_query.isNotEmpty) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() => _query = '');
            },
            icon: const Icon(Icons.close_rounded),
            label: const Text('Clear search'),
          ),
        ],
      ],
    ),
  );

  Widget _buildErrorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 58,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 14),
          const Text(
            'The sample menu could not be loaded',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.midnightInk,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() => _menuFuture = _loadMenu()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Widget _buildLoadingState() => Shimmer.fromColors(
    baseColor: AppColors.glassBorder,
    highlightColor: Colors.white,
    child: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 236,
          backgroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: Padding(
              padding: const EdgeInsets.fromLTRB(16, 92, 16, 18),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  height: 92,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, _) => Container(
                width: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.builder(
            itemCount: 3,
            itemBuilder: (_, _) => Container(
              height: 150,
              margin: const EdgeInsets.only(bottom: 12),
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

  Future<void> _openCartSheet() async {
    if (_cartCount == 0) return;
    final openCheckout = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final items = _cartItems;
          return SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your sample cart',
                          style: TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${_cartCount} ${_cartCount == 1 ? 'item' : 'items'}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review your items and change quantities before checkout.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('Your cart is empty.'))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final meal = items[index];
                              final quantity = _cart[meal.id] ?? 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _MealPhoto(
                                        meal: meal,
                                        width: 66,
                                        height: 66,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            meal.name,
                                            style: const TextStyle(
                                              color: AppColors.midnightInk,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(_price(meal.price * quantity)),
                                        ],
                                      ),
                                    ),
                                    _QuantityStepper(
                                      quantity: quantity,
                                      onRemove: () {
                                        _changeQuantity(meal, -1);
                                        setSheetState(() {});
                                      },
                                      onAdd: () {
                                        _changeQuantity(meal, 1);
                                        setSheetState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sample total',
                          style: TextStyle(
                            color: AppColors.midnightInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _price(_cartTotal),
                        style: const TextStyle(
                          color: AppColors.vibeBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _cartCount == 0
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop(true);
                            },
                      icon: const Icon(Icons.schedule_rounded),
                      label: const Text('Choose pickup time'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (openCheckout == true && mounted) await _openCheckoutSheet();
  }

  Future<void> _openCheckoutSheet() async {
    if (_cartCount == 0) return;
    var selectedPickup = _pickupTimes[1];
    final previewed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pickup preview',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a sample collection window. This will not send an order.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              ..._pickupTimes.map(
                (time) => RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(time),
                  subtitle: const Text('Estimated ready in 10–18 minutes'),
                  value: time,
                  groupValue: selectedPickup,
                  onChanged: (value) {
                    if (value != null)
                      setSheetState(() => selectedPickup = value);
                  },
                ),
              ),
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sample total',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    _price(_cartTotal),
                    style: const TextStyle(
                      color: AppColors.vibeBlue,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Preview sample order'),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Demo only · No order or payment will be sent',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (previewed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sample pickup preview: $selectedPickup. No order was sent.',
          ),
        ),
      );
    }
  }
}

class _OpenStatusBadge extends StatelessWidget {
  const _OpenStatusBadge({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: isOpen ? AppColors.successSurface : AppColors.dangerSurface,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 9,
          color: isOpen ? AppColors.success : AppColors.danger,
        ),
        const SizedBox(width: 6),
        Text(
          isOpen ? 'Open now' : 'Closed now',
          style: TextStyle(
            color: isOpen ? AppColors.success : AppColors.danger,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.meal, required this.onAdd});

  final _MealItem meal;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 205,
    child: GlassCard(
      margin: EdgeInsets.zero,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: 122,
                child: _MealPhoto(meal: meal),
              ),
              Positioned(
                left: 9,
                top: 9,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: AppColors.ogGold,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Student pick',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: AppColors.ogGold,
                        size: 15,
                      ),
                      Text(
                        ' ${meal.rating.toStringAsFixed(1)}  ·  ${meal.prepMinutes} min',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'R ${meal.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.vibeBlue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Add ${meal.name} to cart',
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded, size: 20),
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
  );
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final _MealItem meal;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => GlassCard(
    margin: EdgeInsets.zero,
    color: Colors.white,
    elevation: 1,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: Padding(
      padding: const EdgeInsets.all(11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _MealPhoto(meal: meal, width: 96, height: 112),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        meal.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.midnightInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (meal.isPopular)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.star_rounded,
                          color: AppColors.ogGold,
                          size: 18,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meal.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: AppColors.ogGold,
                      size: 15,
                    ),
                    Text(
                      ' ${meal.rating.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.schedule_rounded,
                      color: AppColors.textMuted,
                      size: 14,
                    ),
                    Text(
                      ' ${meal.prepMinutes} min',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'R ${meal.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.vibeBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (meal.isAvailable)
                      quantity == 0
                          ? SizedBox(
                              height: 36,
                              child: FilledButton.tonalIcon(
                                onPressed: onAdd,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add'),
                                style: FilledButton.styleFrom(
                                  foregroundColor: AppColors.vibeBlue,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            )
                          : _QuantityStepper(
                              quantity: quantity,
                              onAdd: onAdd,
                              onRemove: onRemove,
                            )
                    else
                      const _UnavailableBadge(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MealPhoto extends StatelessWidget {
  const _MealPhoto({required this.meal, this.width, this.height});

  final _MealItem meal;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final asset = meal.image;
    return SizedBox(
      width: width,
      height: height,
      child: asset == null
          ? ColoredBox(
              color: meal.accent.withValues(alpha: .16),
              child: Icon(meal.icon, color: meal.accent, size: 38),
            )
          : Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: meal.accent.withValues(alpha: .16),
                child: Icon(meal.icon, color: meal.accent, size: 38),
              ),
            ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    decoration: BoxDecoration(
      color: AppColors.blueTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove one',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w900)),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Add one',
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _UnavailableBadge extends StatelessWidget {
  const _UnavailableBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.dangerSurface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text(
      'Sold out',
      style: TextStyle(
        color: AppColors.danger,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _MealItem {
  const _MealItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.categories,
    required this.prepMinutes,
    required this.rating,
    required this.isPopular,
    required this.accent,
    this.image,
    this.icon = Icons.restaurant_rounded,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String? image;
  final IconData icon;
  final List<String> categories;
  final int prepMinutes;
  final double rating;
  final bool isPopular;
  final bool isAvailable;
  final Color accent;
}
