import 'package:flutter/material.dart';
import '../services/offline_data_adapter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  String _category = 'Clothes';
  bool _isAnonymous = true;
  bool _submitting = false;
  bool _showForm = false;
  bool _loadingOffers = true;
  final List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];

  static const List<String> _categories = [
    'Clothes',
    'Shoes',
    'Stationery',
    'Care items',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    try {
      final rows = await OfflineData.instance.client
          .from('support_donations')
          .select('id, category, item, location, status, created_at')
          .order('created_at', ascending: false)
          .limit(10);
      if (!mounted) return;
      setState(() {
        _offers
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(rows));
        _loadingOffers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOffers = false);
    }
  }

  @override
  void dispose() {
    _itemController.dispose();
    _detailsController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submitDonation() async {
    if (_itemController.text.trim().isEmpty) {
      _showSnack('Please describe what you are donating.');
      return;
    }

    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) {
      _showSnack('Sign in to share a donation.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await OfflineData.instance.client.from('support_donations').insert({
        'user_id': user.id,
        'category': _category,
        'item': _itemController.text.trim(),
        'details': _detailsController.text.trim(),
        'location': _locationController.text.trim(),
        'is_anonymous': _isAnonymous,
      });
      if (!mounted) return;
      _showSnack('Your donation offer was shared privately.');
    } catch (error) {
      if (mounted) _showSnack('Could not share this offer: $error');
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    _itemController.clear();
    _detailsController.clear();
    _locationController.clear();
    setState(() {
      _category = 'Clothes';
      _isAnonymous = true;
      _showForm = false;
    });
    await _loadOffers();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Donations')),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppStyles.auroraGradient),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: <Widget>[
            _buildSectionTitle('Donate to a fellow student'),
            const SizedBox(height: 12),
            const Text(
              'Offer clothes, shoes, stationery or other essentials. Your details stay private and the support team will coordinate the handover.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => setState(() => _showForm = !_showForm),
              icon: const Icon(Icons.volunteer_activism_outlined),
              label: Text(_showForm ? 'Close donation form' : 'Donate'),
            ),
            if (_showForm) ...[
              _buildFieldLabel('Donation category'),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _category,
                  items: _categories
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildFieldLabel('What are you donating?'),
              const SizedBox(height: 8),
              _buildTextField(
                _itemController,
                'e.g. winter jacket, school shoes, or pens',
              ),
              const SizedBox(height: 18),
              _buildFieldLabel('Additional details'),
              const SizedBox(height: 8),
              _buildTextField(
                _detailsController,
                'Size, condition, quantity, or any useful note',
                maxLines: 4,
              ),
              const SizedBox(height: 18),
              _buildFieldLabel('Pickup or drop-off info'),
              const SizedBox(height: 8),
              _buildTextField(
                _locationController,
                'Pool point, campus location, or availability window',
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Switch(
                    value: _isAnonymous,
                    onChanged: (value) => setState(() => _isAnonymous = value),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hide my identity from the recipient',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _submitting ? null : _submitDonation,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.volunteer_activism_outlined),
                label: Text(_submitting ? 'Sending…' : 'Send donation offer'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildInfoCard(
              icon: Icons.lightbulb,
              title: 'How it works',
              description:
                  'Your offer is sent privately to the support team. Other students cannot see your identity or collection details.',
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Your recent offers'),
            const SizedBox(height: 12),
            if (_loadingOffers)
              const Center(child: CircularProgressIndicator())
            else if (_offers.isEmpty)
              const Text(
                'No donation offers yet.',
                style: TextStyle(color: AppColors.textMuted),
              )
            else
              ..._offers.map(
                (offer) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.volunteer_activism_rounded),
                    title: Text('${offer['item']}'),
                    subtitle: Text(
                      '${offer['category']} • ${offer['location'] ?? ''}',
                    ),
                    trailing: Chip(label: Text('${offer['status']}')),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.midnightInk,
        fontSize: 24,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.midnightInk,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.vibeBlue),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.vibeBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    height: 1.5,
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
