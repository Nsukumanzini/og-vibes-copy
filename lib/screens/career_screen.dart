import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key});

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<Map<String, List<Map<String, dynamic>>>> _opportunitiesFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _opportunitiesFuture = _loadOpportunities();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadOpportunities() async {
    final response = await Supabase.instance.client
        .from('career_opportunities')
        .select('id, title, description, category, company, duration, type, salary, created_at')
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response as List<dynamic>);
    final grouped = <String, List<Map<String, dynamic>>>{
      'bursary': [],
      'internship': [],
      'job': [],
      'funding': [],
    };

    for (final row in rows) {
      final category = (row['category'] ?? 'funding').toString().toLowerCase();
      final bucket = grouped.containsKey(category) ? category : 'funding';
      grouped[bucket]!.add(mapCareerRowToItem(row));
    }

    return grouped;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Career & Funding'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.school),
              text: 'Bursaries',
            ),
            Tab(
              icon: Icon(Icons.business),
              text: 'Internships',
            ),
            Tab(
              icon: Icon(Icons.work),
              text: 'Jobs',
            ),
            Tab(
              icon: Icon(Icons.paid),
              text: 'Funding',
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _opportunitiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _opportunitiesFuture = _loadOpportunities();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry career load'),
              ),
            );
          }

          final opportunities = snapshot.data!;
          return TabBarView(
            controller: _tabController,
            children: [
              _buildBursariesTab(opportunities['bursary'] ?? const []),
              _buildInternshipsTab(opportunities['internship'] ?? const []),
              _buildJobsTab(opportunities['job'] ?? const []),
              _buildFundingTab(opportunities['funding'] ?? const []),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBursariesTab(List<Map<String, dynamic>> items) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardHeader(
          'Available Bursaries',
          'Explore financial assistance programs',
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildBursaryCard(
                title: item['title'].toString(),
                description: item['description'].toString(),
                icon: Icons.star,
                color: Colors.amber,
              ),
            )),
        const SizedBox(height: 30),
        _buildActionButton('View All Bursaries', Colors.amber),
      ],
    );
  }

  Widget _buildInternshipsTab(List<Map<String, dynamic>> items) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardHeader(
          'Current Internships',
          'Gain real-world experience',
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildInternshipCard(
                company: item['company'].toString(),
                position: item['title'].toString(),
                duration: item['duration'].toString(),
                icon: Icons.code,
                color: Colors.blue,
              ),
            )),
        const SizedBox(height: 30),
        _buildActionButton('Browse All Internships', Colors.blue),
      ],
    );
  }

  Widget _buildJobsTab(List<Map<String, dynamic>> items) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardHeader(
          'Job Opportunities',
          'Find graduate and part-time positions',
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildJobCard(
                company: item['company'].toString(),
                position: item['title'].toString(),
                type: item['type'].toString(),
                salary: item['salary'].toString(),
                icon: Icons.computer,
              ),
            )),
        const SizedBox(height: 30),
        _buildActionButton('View All Jobs', Colors.green),
      ],
    );
  }

  Widget _buildFundingTab(List<Map<String, dynamic>> items) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardHeader(
          'Alternative Funding',
          'Explore diverse funding opportunities',
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildFundingCard(
                title: item['title'].toString(),
                description: item['description'].toString(),
                icon: Icons.account_balance,
                color: Colors.teal,
              ),
            )),
        const SizedBox(height: 30),
        _buildActionButton('Explore Funding Options', Colors.teal),
      ],
    );
  }

  Widget _buildCardHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  Widget _buildBursaryCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening $title details...')),
          );
        },
      ),
    );
  }

  Widget _buildInternshipCard({
    required String company,
    required String position,
    required String duration,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        position,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                duration,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard({
    required String company,
    required String position,
    required String type,
    required String salary,
    required IconData icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        position,
                        style: const TextStyle(
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    salary,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFundingCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening $title details...')),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(String label, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Navigating to $label...')),
          );
        },
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> mapCareerRowToItem(Map<String, dynamic> row) {
  return {
    'title': (row['title'] ?? '').toString(),
    'description': (row['description'] ?? '').toString(),
    'category': (row['category'] ?? '').toString(),
    'company': (row['company'] ?? '').toString(),
    'duration': (row['duration'] ?? '').toString(),
    'type': (row['type'] ?? '').toString(),
    'salary': (row['salary'] ?? '').toString(),
  };
}
