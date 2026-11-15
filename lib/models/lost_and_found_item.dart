import 'dart:typed_data';

import 'package:flutter/material.dart';

class LostAndFoundItem {
  LostAndFoundItem({
    required this.title,
    required this.foundAt,
    required this.collectAt,
    required this.requirements,
    required this.icon,
    required this.color,
    this.imageBytes,
    this.imageUrl,
    this.status,
  });

  final String title;
  final String foundAt;
  final String collectAt;
  final String requirements;
  final IconData icon;
  final Color color;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? status;

  factory LostAndFoundItem.fromRow(Map<String, dynamic> row) {
    return LostAndFoundItem(
      title: (row['title'] as String?) ?? 'Untitled item',
      foundAt: (row['found_at'] as String?) ?? 'Unknown',
      collectAt: (row['collect_at'] as String?) ?? 'Admin Desk',
      requirements: (row['requirements'] as String?) ?? 'Bring ID or proof of ownership',
      icon: Icons.inventory_2_outlined,
      color: const Color(0xFF1565C0),
      imageUrl: row['image_url']?.toString(),
      status: row['status']?.toString(),
    );
  }
}
