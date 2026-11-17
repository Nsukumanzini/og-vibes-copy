import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(seconds: 2),
  );
  late Future<List<_ChecklistItem>> _checklistFuture;
  List<_ChecklistItem> _items = [];

  @override
  void initState() {
    super.initState();
    _checklistFuture = _loadChecklist();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<List<_ChecklistItem>> _loadChecklist() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    _items = [
      _ChecklistItem(
        title: 'Submit PoE File for Office Data Processing',
        done: true,
        due: 'Completed',
      ),
      _ChecklistItem(
        title: 'Register for June NATED Exams',
        done: false,
        due: 'Due Friday',
      ),
      _ChecklistItem(
        title: 'Buy N4 Maths Textbook',
        done: false,
        due: 'This week',
      ),
    ];

    return _items;
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Academic Checklist'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF2962FF),
                  Color(0xFF6200EA),
                ],
              ),
            ),
            child: FutureBuilder<List<_ChecklistItem>>(
              future: _checklistFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _buildLoading();
                }
                if (!snapshot.hasData || snapshot.hasError) {
                  return Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _checklistFuture = _loadChecklist();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry checklist load'),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _buildTile(_items[index]),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.02,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(_ChecklistItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: CheckboxListTile(
        value: item.done,
        onChanged: (value) {
          setState(() {
            item.done = value ?? false;
          });
          if (_items.every((e) => e.done)) {
            _confettiController.play();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('All academic tasks completed!')),
            );
          }
        },
        title: Text(
          item.title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            decoration: item.done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          item.due,
          style: TextStyle(
            color: item.done ? const Color(0xFF69F0AE) : Colors.amberAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
        activeColor: const Color(0xFF00C853),
        checkColor: Colors.white,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.white24,
        highlightColor: Colors.white38,
        child: ListView.separated(
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Container(
            height: 92,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistItem {
  _ChecklistItem({required this.title, required this.done, required this.due});

  final String title;
  bool done;
  final String due;
}
