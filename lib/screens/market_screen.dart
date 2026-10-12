import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

enum _MarketSort { relevance, newest, priceLow, priceHigh }

class _MarketScreenState extends State<MarketScreen> {
  static const List<String> _meetupPoints = <String>[
    'Campus security gate',
    'Library reception',
    'Student centre',
    'Administration reception',
    'Cafeteria public area',
  ];
  static const String _cacheKey = 'marketplace_available_products_v2';

  final List<_MarketProduct> _products = <_MarketProduct>[];
  final List<_MarketOrder> _orders = <_MarketOrder>[];
  RealtimeChannel? _productChannel;
  RealtimeChannel? _orderChannel;
  Timer? _refreshDebounce;
  int _tabIndex = 0;
  _MarketSort _sort = _MarketSort.relevance;
  bool _loading = true;
  bool _refreshing = false;
  bool _usingCachedData = false;
  String? _error;

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _hydrateCache();
    await _loadData(showLoader: _products.isEmpty);
    _subscribeToChanges();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _productChannel?.unsubscribe();
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _hydrateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_cacheKey);
      if (encoded == null || encoded.isEmpty) return;
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return;
      final cached = decoded
          .whereType<Map>()
          .map(
            (row) => _MarketProduct.fromRow(
              Map<String, dynamic>.from(row),
              _supabase,
            ),
          )
          .toList();
      if (!mounted || cached.isEmpty) return;
      setState(() {
        _products
          ..clear()
          ..addAll(cached);
        _usingCachedData = true;
        _loading = false;
      });
    } catch (_) {
      // A corrupt cache should never prevent a fresh marketplace load.
    }
  }

  Future<void> _cacheAvailableProducts(List<Map<String, dynamic>> rows) async {
    try {
      final safeRows = rows
          .where((row) => row['status'] == 'available')
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(safeRows));
    } catch (_) {
      // Caching is an enhancement; the live marketplace remains authoritative.
    }
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final user = _user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign in to browse and sell on Marketplace.';
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
            .from('products')
            .select(
              'id, seller_id, title, price, category, description, '
              'is_negotiable, images, image_paths, status, condition, campus, '
              'meetup_point, created_at, updated_at, '
              'profiles!products_seller_id_fkey(name, surname, photo_url, is_verified)',
            )
            .order('created_at', ascending: false),
        _supabase
            .from('marketplace_orders')
            .select(
              'id, product_id, buyer_id, seller_id, kind, amount, status, '
              'meetup_point, created_at, updated_at, '
              'products!marketplace_orders_product_id_fkey(id, title, price, images, image_paths, status), '
              'buyer:profiles!marketplace_orders_buyer_id_fkey(name, surname), '
              'seller:profiles!marketplace_orders_seller_id_fkey(name, surname)',
            )
            .order('created_at', ascending: false),
      ]);
      final productRows = List<Map<String, dynamic>>.from(
        responses[0] as List<dynamic>,
      );
      final orderRows = List<Map<String, dynamic>>.from(
        responses[1] as List<dynamic>,
      );
      final products = productRows
          .map((row) => _MarketProduct.fromRow(row, _supabase))
          .toList();
      final orders = orderRows.map(_MarketOrder.fromRow).toList();
      unawaited(_cacheAvailableProducts(productRows));
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(products);
        _orders
          ..clear()
          ..addAll(orders);
        _loading = false;
        _refreshing = false;
        _usingCachedData = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _usingCachedData = _products.isNotEmpty;
        _error = _friendlyError(error);
      });
    }
  }

  void _subscribeToChanges() {
    _productChannel = _supabase
        .channel('marketplace-products-${_user?.id ?? 'guest'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
    _orderChannel = _supabase
        .channel('marketplace-orders-${_user?.id ?? 'guest'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'marketplace_orders',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_loadData(showLoader: false)),
    );
  }

  List<_MarketProduct> get _browseProducts {
    final userId = _user?.id;
    final products = _products
        .where(
          (product) =>
              product.status == 'available' && product.sellerId != userId,
        )
        .toList();
    switch (_sort) {
      case _MarketSort.relevance:
        products.sort((a, b) {
          final aScore =
              (a.imageUrls.isNotEmpty ? 2 : 0) + (a.isNegotiable ? 1 : 0);
          final bScore =
              (b.imageUrls.isNotEmpty ? 2 : 0) + (b.isNegotiable ? 1 : 0);
          final score = bScore.compareTo(aScore);
          return score != 0 ? score : b.createdAt.compareTo(a.createdAt);
        });
      case _MarketSort.newest:
        products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _MarketSort.priceLow:
        products.sort((a, b) => a.price.compareTo(b.price));
      case _MarketSort.priceHigh:
        products.sort((a, b) => b.price.compareTo(a.price));
    }
    return products;
  }

  List<_MarketProduct> get _sellingProducts {
    final userId = _user?.id;
    return _products.where((product) => product.sellerId == userId).toList();
  }

  Future<void> _openListingWizard() async {
    HapticFeedback.selectionClick();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const _ListingWizard(),
    );
    if (created == true) {
      await _loadData(showLoader: false);
      _showMessage('Your listing is live.');
    }
  }

  Future<void> _openProduct(_MarketProduct product) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => _ProductDetailsSheet(
        product: product,
        isOwner: product.sellerId == _user?.id,
        onBuy: () {
          Navigator.pop(sheetContext);
          unawaited(_placeOrder(product, 'buy'));
        },
        onOffer: () {
          Navigator.pop(sheetContext);
          unawaited(_placeOrder(product, 'offer'));
        },
        onReport: () {
          Navigator.pop(sheetContext);
          unawaited(_reportProduct(product));
        },
      ),
    );
  }

  Future<void> _placeOrder(_MarketProduct product, String kind) async {
    final user = _user;
    if (user == null || user.id == product.sellerId) return;
    final result = await showDialog<_OrderDraft>(
      context: context,
      builder: (_) => _OrderDialog(
        product: product,
        kind: kind,
        meetupPoints: _meetupPoints,
      ),
    );
    if (result == null) return;
    try {
      await _supabase.from('marketplace_orders').insert(<String, dynamic>{
        'product_id': product.id,
        'buyer_id': user.id,
        'seller_id': product.sellerId,
        'kind': kind,
        'amount': result.amount,
        'meetup_point': result.meetupPoint,
      });
      HapticFeedback.mediumImpact();
      await _loadData(showLoader: false);
      _showMessage(
        kind == 'buy'
            ? 'Purchase request sent to ${product.sellerName}.'
            : 'Your offer was sent to ${product.sellerName}.',
      );
      if (mounted) setState(() => _tabIndex = 2);
    } catch (error) {
      _showMessage(
        error.toString().contains('marketplace_orders_one_pending')
            ? 'You already have a pending request for this item.'
            : _friendlyError(error),
        error: true,
      );
    }
  }

  Future<void> _reportProduct(_MarketProduct product) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ReportDialog(),
    );
    if (result == null || _user == null) return;
    try {
      await _supabase.from('marketplace_reports').insert(<String, dynamic>{
        'product_id': product.id,
        'reporter_id': _user!.id,
        'reason': result['reason'],
        'details': result['details'],
      });
      HapticFeedback.mediumImpact();
      _showMessage('Report submitted privately for moderation.');
    } catch (error) {
      _showMessage(
        error.toString().contains('marketplace_reports_once')
            ? 'You have already reported this listing.'
            : _friendlyError(error),
        error: true,
      );
    }
  }

  Future<void> _updateOrderStatus(_MarketOrder order, String status) async {
    try {
      await _supabase
          .from('marketplace_orders')
          .update(<String, dynamic>{'status': status})
          .eq('id', order.id);
      HapticFeedback.mediumImpact();
      await _loadData(showLoader: false);
      _showMessage(
        status == 'accepted'
            ? 'Deal accepted. The item is now reserved.'
            : 'Order updated.',
      );
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    }
  }

  Future<void> _toggleListing(_MarketProduct product) async {
    final nextStatus = product.status == 'archived' ? 'available' : 'archived';
    try {
      await _supabase
          .from('products')
          .update(<String, dynamic>{'status': nextStatus})
          .eq('id', product.id);
      await _loadData(showLoader: false);
      _showMessage(
        nextStatus == 'archived' ? 'Listing archived.' : 'Listing restored.',
      );
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.danger : AppColors.midnightInk,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('OG Marketplace'),
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      floatingActionButton: _tabIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _openListingWizard,
              backgroundColor: AppColors.vibeBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('List an item'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _products.isEmpty
          ? _ErrorState(message: _error!, onRetry: () => _loadData())
          : Column(
              children: <Widget>[
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _loadData(showLoader: false),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: <Widget>[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          sliver: SliverToBoxAdapter(child: _buildHero()),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverToBoxAdapter(child: _buildTabs()),
                        ),
                        if (_usingCachedData || _error != null)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            sliver: SliverToBoxAdapter(
                              child: _OfflineBanner(
                                message:
                                    'Showing saved listings while the live marketplace reconnects.',
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                          sliver: _buildActiveTab(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHero() {
    final availableCount = _products
        .where((product) => product.status == 'available')
        .length;
    final activeDeals = _orders
        .where(
          (order) => order.status == 'pending' || order.status == 'accepted',
        )
        .length;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.vibeBlue.withValues(alpha: .24),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -30,
            top: -34,
            child: Icon(
              Icons.shopping_bag_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: .07),
            ),
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
                  color: AppColors.electricCyan.withValues(alpha: .16),
                  borderRadius: AppStyles.pillRadius,
                  border: Border.all(
                    color: AppColors.electricCyan.withValues(alpha: .38),
                  ),
                ),
                child: const Text(
                  'OG VIBES • CAMPUS MARKET',
                  style: TextStyle(
                    color: AppColors.electricCyan,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Buy smart.\nTrade safely.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$availableCount live listings  •  $activeDeals active deals',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .74),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  _HeroPill(
                    icon: Icons.verified_user_rounded,
                    label: 'Campus-only',
                  ),
                  const SizedBox(width: 8),
                  _HeroPill(
                    icon: Icons.location_on_rounded,
                    label: 'Safe meetups',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 380.ms).slideY(begin: .08, end: 0);
  }

  Widget _buildTabs() {
    const tabs = <(IconData, String)>[
      (Icons.storefront_rounded, 'Browse'),
      (Icons.sell_rounded, 'Selling'),
      (Icons.receipt_long_rounded, 'Orders'),
    ];
    return _GlassCard(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: List<Widget>.generate(tabs.length, (index) {
          final selected = _tabIndex == index;
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              label: '${tabs[index].$2} marketplace tab',
              child: InkWell(
                borderRadius: BorderRadius.circular(17),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tabIndex = index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: selected ? AppStyles.brandGradient : null,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        tabs[index].$1,
                        size: 18,
                        color: selected ? Colors.white : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tabs[index].$2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppColors.midnightInk,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveTab() {
    switch (_tabIndex) {
      case 1:
        return _sellingSliver();
      case 2:
        return _ordersSliver();
      default:
        return _browseSliver();
    }
  }

  Widget _browseSliver() {
    final products = _browseProducts;
    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Discover on campus',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.midnightInk,
                  ),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<_MarketSort>(
                  value: _sort,
                  borderRadius: BorderRadius.circular(18),
                  icon: const Icon(Icons.tune_rounded, size: 19),
                  items: const <DropdownMenuItem<_MarketSort>>[
                    DropdownMenuItem(
                      value: _MarketSort.relevance,
                      child: Text('Relevance'),
                    ),
                    DropdownMenuItem(
                      value: _MarketSort.newest,
                      child: Text('Newest'),
                    ),
                    DropdownMenuItem(
                      value: _MarketSort.priceLow,
                      child: Text('Price: low'),
                    ),
                    DropdownMenuItem(
                      value: _MarketSort.priceHigh,
                      child: Text('Price: high'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (products.isEmpty)
          SliverToBoxAdapter(
            child: _EmptyState(
              icon: Icons.storefront_outlined,
              title: 'The market is quiet',
              message: 'New campus listings will appear here in realtime.',
              actionLabel: 'Sell the first item',
              onAction: () {
                setState(() => _tabIndex = 1);
                unawaited(_openListingWizard());
              },
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final columns = width >= 1050
                  ? 4
                  : width >= 720
                  ? 3
                  : 2;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: width < 390 ? .62 : .68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _ProductCard(
                            product: products[index],
                            onTap: () => _openProduct(products[index]),
                          )
                          .animate(delay: (45 * index).ms)
                          .fadeIn(duration: 300.ms)
                          .slideY(begin: .06, end: 0),
                  childCount: products.length,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _sellingSliver() {
    final products = _sellingProducts;
    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Your listings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.midnightInk,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Manage availability and buyer interest.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                tooltip: 'Create listing',
                onPressed: _openListingWizard,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (products.isEmpty)
          SliverToBoxAdapter(
            child: _EmptyState(
              icon: Icons.add_a_photo_outlined,
              title: 'Start selling',
              message:
                  'Create a polished listing with up to five clear photos.',
              actionLabel: 'Create listing',
              onAction: _openListingWizard,
            ),
          )
        else
          SliverList.separated(
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return _SellingCard(
                product: product,
                onOpen: () => _openProduct(product),
                onToggle:
                    product.status == 'available' ||
                        product.status == 'archived'
                    ? () => _toggleListing(product)
                    : null,
              );
            },
          ),
      ],
    );
  }

  Widget _ordersSliver() {
    return SliverMainAxisGroup(
      slivers: <Widget>[
        const SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Orders & offers',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.midnightInk,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Purchases and negotiations update here in realtime.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (_orders.isEmpty)
          const SliverToBoxAdapter(
            child: _EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No deals yet',
              message: 'Buy an item or negotiate a price and track it here.',
            ),
          )
        else
          SliverList.separated(
            itemCount: _orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final order = _orders[index];
              return _OrderCard(
                order: order,
                currentUserId: _user?.id ?? '',
                onStatus: (status) => _updateOrderStatus(order, status),
              );
            },
          ),
      ],
    );
  }
}

class _ListingWizard extends StatefulWidget {
  const _ListingWizard();

  @override
  State<_ListingWizard> createState() => _ListingWizardState();
}

class _ListingWizardState extends State<_ListingWizard> {
  static const List<String> _categories = <String>[
    'Textbooks',
    'Electronics',
    'Stationery',
    'Clothing',
    'Study tools',
    'Appliances',
    'Other',
  ];
  static const List<String> _conditions = <String>[
    'New',
    'Like new',
    'Good',
    'Fair',
  ];
  static const List<String> _meetups = <String>[
    'Campus security gate',
    'Library reception',
    'Student centre',
    'Administration reception',
    'Cafeteria public area',
  ];

  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _campusController = TextEditingController(text: 'Main campus');
  final List<_PickedPhoto> _photos = <_PickedPhoto>[];
  int _step = 0;
  String _category = _categories.first;
  String _condition = 'Good';
  String _meetup = _meetups.first;
  bool _negotiable = true;
  bool _saving = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _campusController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_photos.length >= 5) return;
    final files = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (files.isEmpty) return;
    final remaining = 5 - _photos.length;
    final added = <_PickedPhoto>[];
    for (final file in files.take(remaining)) {
      added.add(_PickedPhoto(name: file.name, bytes: await file.readAsBytes()));
    }
    if (!mounted) return;
    setState(() => _photos.addAll(added));
    HapticFeedback.selectionClick();
  }

  bool _validateStep() {
    if (_step == 0 && _photos.isEmpty) {
      _message('Add at least one clear photo.');
      return false;
    }
    if (_step == 1) {
      final price = double.tryParse(_priceController.text.trim());
      if (_titleController.text.trim().length < 3) {
        _message('Enter a descriptive item title.');
        return false;
      }
      if (price == null || price < 0) {
        _message('Enter a valid price.');
        return false;
      }
      if (_descriptionController.text.trim().length < 10) {
        _message('Add a description of at least 10 characters.');
        return false;
      }
    }
    if (_step == 2 && _campusController.text.trim().isEmpty) {
      _message('Enter your campus.');
      return false;
    }
    return true;
  }

  Future<void> _next() async {
    if (!_validateStep()) return;
    if (_step < 2) {
      HapticFeedback.selectionClick();
      setState(() => _step++);
      return;
    }
    await _publish();
  }

  Future<void> _publish() async {
    final user = _supabase.auth.currentUser;
    if (user == null || _saving) return;
    setState(() => _saving = true);
    final uploadedPaths = <String>[];
    try {
      for (var index = 0; index < _photos.length; index++) {
        final photo = _photos[index];
        final path =
            '${user.id}/${DateTime.now().microsecondsSinceEpoch}_$index.jpg';
        await _supabase.storage
            .from('products')
            .uploadBinary(
              path,
              photo.bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
        uploadedPaths.add(path);
      }
      final urls = uploadedPaths
          .map((path) => _supabase.storage.from('products').getPublicUrl(path))
          .toList();
      await _supabase.from('products').insert(<String, dynamic>{
        'seller_id': user.id,
        'title': _titleController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'category': _category,
        'description': _descriptionController.text.trim(),
        'condition': _condition,
        'campus': _campusController.text.trim(),
        'meetup_point': _meetup,
        'is_negotiable': _negotiable,
        'image_paths': uploadedPaths,
        'images': urls,
        'status': 'available',
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (uploadedPaths.isNotEmpty) {
        try {
          await _supabase.storage.from('products').remove(uploadedPaths);
        } catch (_) {
          // A failed cleanup must not hide the original publishing error.
        }
      }
      _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .92,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppStyles.brandGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.sell_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Create a listing',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Step ${_step + 1} of 3 • ${const <String>['Photos', 'Item details', 'Safety & review'][_step]}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: AppStyles.pillRadius,
              child: LinearProgressIndicator(
                value: (_step + 1) / 3,
                minHeight: 7,
                backgroundColor: AppColors.vibeBlue.withValues(alpha: .1),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: SingleChildScrollView(
                key: ValueKey<int>(_step),
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom + 24,
                ),
                child: _step == 0
                    ? _photoStep()
                    : _step == 1
                    ? _detailsStep()
                    : _safetyStep(),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .9),
              border: Border(top: BorderSide(color: AppColors.glassBorder)),
            ),
            child: Row(
              children: <Widget>[
                if (_step > 0)
                  OutlinedButton(
                    onPressed: _saving ? null : () => setState(() => _step--),
                    child: const Text('Back'),
                  ),
                if (_step > 0) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _next,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _step == 2
                                ? Icons.rocket_launch_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                    label: Text(_step == 2 ? 'Publish listing' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _WizardHeading(
          icon: Icons.photo_camera_rounded,
          title: 'Show it at its best',
          message:
              'Add up to five bright, clear photos. The first becomes your cover.',
        ),
        const SizedBox(height: 18),
        if (_photos.isNotEmpty)
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.memory(
                        _photos[index].bytes,
                        width: 180,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _StatusPill(
                        label: index == 0 ? 'Cover' : '${index + 1}',
                        color: AppColors.midnightInk,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IconButton.filled(
                        tooltip: 'Remove photo',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () =>
                            setState(() => _photos.removeAt(index)),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (_photos.isNotEmpty) const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _photos.length >= 5 ? null : _pickPhotos,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26),
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.vibeBlue.withValues(alpha: .25),
                width: 1.4,
              ),
            ),
            child: Column(
              children: <Widget>[
                const Icon(
                  Icons.add_photo_alternate_rounded,
                  color: AppColors.vibeBlue,
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  _photos.length >= 5
                      ? 'Photo limit reached'
                      : 'Choose photos (${_photos.length}/5)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Images are compressed before upload',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _WizardHeading(
          icon: Icons.inventory_2_rounded,
          title: 'Tell buyers what matters',
          message: 'Accurate details build trust and help your item sell.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _titleController,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80,
          decoration: _inputDecoration(
            'Item title',
            Icons.title_rounded,
            hint: 'e.g. First-year Accounting textbook',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: _inputDecoration(
                  'Price',
                  Icons.payments_rounded,
                  prefix: 'R ',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: _inputDecoration(
                  'Category',
                  Icons.category_rounded,
                ),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          maxLines: 5,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(
            'Description',
            Icons.notes_rounded,
            hint: 'Condition, included accessories, and useful details',
          ),
        ),
        const SizedBox(height: 8),
        _GlassCard(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _negotiable,
            onChanged: (value) => setState(() => _negotiable = value),
            secondary: const Icon(
              Icons.handshake_rounded,
              color: AppColors.vibeBlue,
            ),
            title: const Text(
              'Accept price offers',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Buyers may negotiate below your price.'),
          ),
        ),
      ],
    );
  }

  Widget _safetyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _WizardHeading(
          icon: Icons.verified_user_rounded,
          title: 'Set up a safe exchange',
          message:
              'Choose a public, monitored campus location for the handover.',
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _condition,
          decoration: _inputDecoration('Condition', Icons.auto_awesome_rounded),
          items: _conditions
              .map(
                (condition) => DropdownMenuItem<String>(
                  value: condition,
                  child: Text(condition),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _condition = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _campusController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration('Campus', Icons.school_rounded),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _meetup,
          decoration: _inputDecoration(
            'Preferred meetup point',
            Icons.location_on_rounded,
          ),
          items: _meetups
              .map(
                (meetup) => DropdownMenuItem<String>(
                  value: meetup,
                  child: Text(meetup),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _meetup = value);
          },
        ),
        const SizedBox(height: 18),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.preview_rounded, color: AppColors.vibeBlue),
                  SizedBox(width: 8),
                  Text(
                    'Listing preview',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  if (_photos.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _photos.first.bytes,
                        width: 82,
                        height: 82,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _titleController.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'R ${_priceController.text.trim()}',
                          style: const TextStyle(
                            color: AppColors.vibeBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '$_condition • ${_campusController.text.trim()}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SafetyNote(),
      ],
    );
  }
}

class _ProductDetailsSheet extends StatefulWidget {
  const _ProductDetailsSheet({
    required this.product,
    required this.isOwner,
    required this.onBuy,
    required this.onOffer,
    required this.onReport,
  });

  final _MarketProduct product;
  final bool isOwner;
  final VoidCallback onBuy;
  final VoidCallback onOffer;
  final VoidCallback onReport;

  @override
  State<_ProductDetailsSheet> createState() => _ProductDetailsSheetState();
}

class _ProductDetailsSheetState extends State<_ProductDetailsSheet> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Container(
      height: MediaQuery.sizeOf(context).height * .92,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      SizedBox(
                        height: 330,
                        width: double.infinity,
                        child: product.imageUrls.isEmpty
                            ? _ImageFallback(category: product.category)
                            : PageView.builder(
                                itemCount: product.imageUrls.length,
                                onPageChanged: (index) =>
                                    setState(() => _photoIndex = index),
                                itemBuilder: (_, index) => CachedNetworkImage(
                                  imageUrl: product.imageUrls[index],
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => _ImageFallback(
                                    category: product.category,
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: IconButton.filled(
                          tooltip: 'Close',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      if (!widget.isOwner)
                        Positioned(
                          top: 14,
                          right: 14,
                          child: IconButton.filled(
                            tooltip: 'Report listing',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: widget.onReport,
                            icon: const Icon(Icons.flag_outlined),
                          ),
                        ),
                      if (product.imageUrls.length > 1)
                        Positioned(
                          bottom: 14,
                          right: 14,
                          child: _StatusPill(
                            label:
                                '${_photoIndex + 1}/${product.imageUrls.length}',
                            color: AppColors.midnightInk,
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                product.title,
                                style: const TextStyle(
                                  fontSize: 25,
                                  height: 1.1,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.midnightInk,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _money(product.price),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: AppColors.vibeBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: <Widget>[
                            _SoftPill(
                              icon: Icons.category_rounded,
                              label: product.category,
                            ),
                            _SoftPill(
                              icon: Icons.auto_awesome_rounded,
                              label: product.condition,
                            ),
                            if (product.isNegotiable)
                              const _SoftPill(
                                icon: Icons.handshake_rounded,
                                label: 'Negotiable',
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _GlassCard(
                          child: Row(
                            children: <Widget>[
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: AppColors.vibeBlue.withValues(
                                  alpha: .1,
                                ),
                                backgroundImage: product.sellerPhoto.isEmpty
                                    ? null
                                    : CachedNetworkImageProvider(
                                        product.sellerPhoto,
                                      ),
                                child: product.sellerPhoto.isEmpty
                                    ? Text(
                                        product.sellerName.characters.first
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.vibeBlue,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Flexible(
                                          child: Text(
                                            product.sellerName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        if (product.sellerVerified) ...<Widget>[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.verified_rounded,
                                            color: AppColors.vibeBlue,
                                            size: 17,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      '${product.campus} • ${_relative(product.createdAt)}',
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'About this item',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          product.description,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _GlassCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(
                                    alpha: .1,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: AppColors.success,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Text(
                                      'Safe meetup',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${product.meetupPoint}, ${product.campus}',
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _SafetyNote(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!widget.isOwner && product.status == 'available')
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                border: Border(top: BorderSide(color: AppColors.glassBorder)),
              ),
              child: Row(
                children: <Widget>[
                  if (product.isNegotiable) ...<Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onOffer,
                        icon: const Icon(Icons.handshake_outlined),
                        label: const Text('Make offer'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onBuy,
                      icon: const Icon(Icons.shopping_bag_rounded),
                      label: const Text('Buy now'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderDialog extends StatefulWidget {
  const _OrderDialog({
    required this.product,
    required this.kind,
    required this.meetupPoints,
  });

  final _MarketProduct product;
  final String kind;
  final List<String> meetupPoints;

  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  late final TextEditingController _amountController;
  late String _meetup;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.kind == 'buy' ? widget.product.price.toStringAsFixed(2) : '',
    );
    _meetup = widget.product.meetupPoint;
    if (!widget.meetupPoints.contains(_meetup)) {
      _meetup = widget.meetupPoints.first;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid offer.');
      return;
    }
    if (widget.kind == 'offer' && amount > widget.product.price) {
      setState(() => _error = 'Offers cannot exceed the listed price.');
      return;
    }
    Navigator.pop(context, _OrderDraft(amount: amount, meetupPoint: _meetup));
  }

  @override
  Widget build(BuildContext context) {
    final isOffer = widget.kind == 'offer';
    return AlertDialog(
      icon: Icon(
        isOffer ? Icons.handshake_rounded : Icons.shopping_bag_rounded,
        color: AppColors.vibeBlue,
      ),
      title: Text(isOffer ? 'Negotiate a price' : 'Request to buy'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.product.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              enabled: isOffer,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: isOffer ? 'Your offer' : 'Price',
                prefixText: 'R ',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _meetup,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Safe meetup point',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              items: widget.meetupPoints
                  .map(
                    (point) => DropdownMenuItem<String>(
                      value: point,
                      child: Text(point),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _meetup = value);
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Payment happens only after you inspect the item at the agreed public campus location.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isOffer ? 'Send offer' : 'Send request'),
        ),
      ],
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _detailsController = TextEditingController();
  String _reason = 'Suspected scam';

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const reasons = <String>[
      'Suspected scam',
      'Prohibited item',
      'Misleading information',
      'Duplicate listing',
      'Other',
    ];
    return AlertDialog(
      icon: const Icon(Icons.shield_outlined, color: AppColors.danger),
      title: const Text('Report listing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: reasons
                  .map(
                    (reason) => DropdownMenuItem<String>(
                      value: reason,
                      child: Text(reason),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _reason = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailsController,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText: 'Tell the moderation team what happened',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, <String, String>{
            'reason': _reason,
            'details': _detailsController.text.trim(),
          }),
          child: const Text('Submit report'),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final _MarketProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${product.title}, ${_money(product.price)}, sold by ${product.sellerName}',
      child: _GlassCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: AppStyles.bentoRadius,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: product.imageUrls.isEmpty
                          ? _ImageFallback(category: product.category)
                          : CachedNetworkImage(
                              imageUrl: product.imageUrls.first,
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 180),
                              placeholder: (_, _) =>
                                  const ColoredBox(color: Color(0xFFE7EDFA)),
                              errorWidget: (_, _, _) =>
                                  _ImageFallback(category: product.category),
                            ),
                    ),
                    Positioned(
                      top: 9,
                      left: 9,
                      child: _StatusPill(
                        label: product.condition,
                        color: AppColors.midnightInk,
                      ),
                    ),
                    if (product.imageUrls.length > 1)
                      Positioned(
                        right: 9,
                        top: 9,
                        child: _StatusPill(
                          label: '${product.imageUrls.length} photos',
                          color: AppColors.vibeBlue,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.midnightInk,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _money(product.price),
                            style: const TextStyle(
                              color: AppColors.vibeBlue,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (product.isNegotiable)
                          const Icon(
                            Icons.handshake_rounded,
                            size: 17,
                            color: AppColors.success,
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            product.campus,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

class _SellingCard extends StatelessWidget {
  const _SellingCard({
    required this.product,
    required this.onOpen,
    this.onToggle,
  });

  final _MarketProduct product;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 86,
              height: 86,
              child: product.imageUrls.isEmpty
                  ? _ImageFallback(category: product.category)
                  : CachedNetworkImage(
                      imageUrl: product.imageUrls.first,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          _ImageFallback(category: product.category),
                    ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          product.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      _StatusPill(
                        label: product.status,
                        color: _statusColor(product.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _money(product.price),
                    style: const TextStyle(
                      color: AppColors.vibeBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${product.imageUrls.length} photos • ${_relative(product.createdAt)}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onToggle != null)
            IconButton(
              tooltip: product.status == 'archived'
                  ? 'Restore listing'
                  : 'Archive listing',
              onPressed: onToggle,
              icon: Icon(
                product.status == 'archived'
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currentUserId,
    required this.onStatus,
  });

  final _MarketOrder order;
  final String currentUserId;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final isSeller = order.sellerId == currentUserId;
    final otherName = isSeller ? order.buyerName : order.sellerName;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.vibeBlue.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  order.kind == 'offer'
                      ? Icons.handshake_rounded
                      : Icons.shopping_bag_rounded,
                  color: AppColors.vibeBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      order.productTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${isSeller ? 'From' : 'With'} $otherName • ${_relative(order.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: order.status,
                color: _statusColor(order.status),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.auroraCanvas,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _OrderDatum(
                    label: order.kind == 'offer' ? 'Offer' : 'Price',
                    value: _money(order.amount),
                  ),
                ),
                Container(width: 1, height: 34, color: AppColors.glassBorder),
                Expanded(
                  child: _OrderDatum(label: 'Meetup', value: order.meetupPoint),
                ),
              ],
            ),
          ),
          if (order.status == 'pending' || order.status == 'accepted') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (order.status == 'pending' && isSeller) ...<Widget>[
                  TextButton(
                    onPressed: () => onStatus('declined'),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 7),
                  FilledButton.icon(
                    onPressed: () => onStatus('accepted'),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept'),
                  ),
                ] else if (order.status == 'pending')
                  TextButton.icon(
                    onPressed: () => onStatus('cancelled'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancel request'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () => onStatus('completed'),
                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text('Mark completed'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderDatum extends StatelessWidget {
  const _OrderDatum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MarketProduct {
  const _MarketProduct({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.category,
    required this.description,
    required this.isNegotiable,
    required this.imageUrls,
    required this.status,
    required this.condition,
    required this.campus,
    required this.meetupPoint,
    required this.createdAt,
    required this.sellerName,
    required this.sellerPhoto,
    required this.sellerVerified,
  });

  factory _MarketProduct.fromRow(
    Map<String, dynamic> row,
    SupabaseClient client,
  ) {
    final profile = _asMap(row['profiles']);
    final names = <String>[
      (profile['name'] ?? '').toString().trim(),
      (profile['surname'] ?? '').toString().trim(),
    ].where((part) => part.isNotEmpty).toList();
    final imageUrls = <String>[];
    for (final value in _asStringList(row['images'])) {
      if (value.startsWith('http')) imageUrls.add(value);
    }
    for (final path in _asStringList(row['image_paths'])) {
      final url = path.startsWith('http')
          ? path
          : client.storage.from('products').getPublicUrl(path);
      if (!imageUrls.contains(url)) imageUrls.add(url);
    }
    return _MarketProduct(
      id: row['id'].toString(),
      sellerId: row['seller_id'].toString(),
      title: (row['title'] ?? 'Untitled listing').toString(),
      price: _toDouble(row['price']),
      category: (row['category'] ?? 'Other').toString(),
      description: (row['description'] ?? '').toString(),
      isNegotiable: row['is_negotiable'] == true,
      imageUrls: imageUrls,
      status: (row['status'] ?? 'available').toString(),
      condition: (row['condition'] ?? 'Good').toString(),
      campus: (row['campus'] ?? 'Main campus').toString(),
      meetupPoint: (row['meetup_point'] ?? 'Campus security gate').toString(),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      sellerName: names.isEmpty ? 'Campus seller' : names.join(' '),
      sellerPhoto: (profile['photo_url'] ?? '').toString(),
      sellerVerified: profile['is_verified'] == true,
    );
  }

  final String id;
  final String sellerId;
  final String title;
  final double price;
  final String category;
  final String description;
  final bool isNegotiable;
  final List<String> imageUrls;
  final String status;
  final String condition;
  final String campus;
  final String meetupPoint;
  final DateTime createdAt;
  final String sellerName;
  final String sellerPhoto;
  final bool sellerVerified;
}

class _MarketOrder {
  const _MarketOrder({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.kind,
    required this.amount,
    required this.status,
    required this.meetupPoint,
    required this.productTitle,
    required this.buyerName,
    required this.sellerName,
    required this.createdAt,
  });

  factory _MarketOrder.fromRow(Map<String, dynamic> row) {
    final product = _asMap(row['products']);
    return _MarketOrder(
      id: row['id'].toString(),
      buyerId: row['buyer_id'].toString(),
      sellerId: row['seller_id'].toString(),
      kind: (row['kind'] ?? 'buy').toString(),
      amount: _toDouble(row['amount']),
      status: (row['status'] ?? 'pending').toString(),
      meetupPoint: (row['meetup_point'] ?? 'Campus meetup').toString(),
      productTitle: (product['title'] ?? 'Marketplace item').toString(),
      buyerName: _profileName(row['buyer']),
      sellerName: _profileName(row['seller']),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  final String id;
  final String buyerId;
  final String sellerId;
  final String kind;
  final double amount;
  final String status;
  final String meetupPoint;
  final String productTitle;
  final String buyerName;
  final String sellerName;
  final DateTime createdAt;
}

class _OrderDraft {
  const _OrderDraft({required this.amount, required this.meetupPoint});

  final double amount;
  final String meetupPoint;
}

class _PickedPhoto {
  const _PickedPhoto({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .86)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFFE8EEFF), Color(0xFFD9FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _categoryIcon(category),
          size: 46,
          color: AppColors.vibeBlue.withValues(alpha: .72),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .11),
        borderRadius: AppStyles.pillRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  const _SoftPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.vibeBlue.withValues(alpha: .07),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: AppColors.vibeBlue, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .9),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WizardHeading extends StatelessWidget {
  const _WizardHeading({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.vibeBlue.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: AppColors.vibeBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.success.withValues(alpha: .18)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_rounded, color: AppColors.success, size: 21),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Meet in public during campus hours. Inspect the item before paying and report suspicious listings.',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: .24)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: <Widget>[
              Icon(icon, size: 48, color: AppColors.vibeBlue),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
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
        child: _EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Marketplace unavailable',
          message: message,
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(
  String label,
  IconData icon, {
  String? hint,
  String? prefix,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefix,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: AppStyles.controlRadius,
      borderSide: BorderSide(color: AppColors.glassBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: AppStyles.controlRadius,
      borderSide: BorderSide(color: AppColors.glassBorder),
    ),
  );
}

Map<String, dynamic> _asMap(dynamic value) {
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return <String>[];
  return value
      .where((item) => item != null && item.toString().trim().isNotEmpty)
      .map((item) => item.toString())
      .toList();
}

double _toDouble(dynamic value) {
  return value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

String _profileName(dynamic value) {
  final profile = _asMap(value);
  final parts = <String>[
    (profile['name'] ?? '').toString().trim(),
    (profile['surname'] ?? '').toString().trim(),
  ].where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? 'Campus student' : parts.join(' ');
}

String _money(double value) {
  return NumberFormat.currency(
    locale: 'en_ZA',
    symbol: 'R ',
    decimalDigits: value == value.roundToDouble() ? 0 : 2,
  ).format(value);
}

String _relative(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inDays > 30) {
    return DateFormat('d MMM').format(value.toLocal());
  }
  if (difference.inDays > 0) return '${difference.inDays}d ago';
  if (difference.inHours > 0) return '${difference.inHours}h ago';
  if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
  return 'Just now';
}

Color _statusColor(String status) {
  switch (status) {
    case 'available':
    case 'accepted':
    case 'completed':
      return AppColors.success;
    case 'pending':
    case 'reserved':
      return AppColors.warning;
    case 'declined':
    case 'cancelled':
      return AppColors.danger;
    default:
      return AppColors.textMuted;
  }
}

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'textbooks':
      return Icons.menu_book_rounded;
    case 'electronics':
      return Icons.devices_rounded;
    case 'stationery':
      return Icons.edit_note_rounded;
    case 'clothing':
      return Icons.checkroom_rounded;
    case 'study tools':
      return Icons.calculate_rounded;
    case 'appliances':
      return Icons.kitchen_rounded;
    default:
      return Icons.shopping_bag_rounded;
  }
}

String _friendlyError(Object error) {
  final value = error.toString();
  if (value.contains('SocketException') ||
      value.contains('Failed host lookup') ||
      value.contains('ClientException')) {
    return 'No connection. Check your internet and try again.';
  }
  if (value.contains('This item is no longer available')) {
    return 'This item was just reserved by another buyer.';
  }
  return 'Something went wrong. Please try again.';
}
