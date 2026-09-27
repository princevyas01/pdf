import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/editorial_components.dart';
import 'files_tab.dart';
import '../favorites/favorites_tab.dart';
import '../search/search_tab.dart';
import '../tools/tools_tab.dart';
import '../stats/stats_tab.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  // The ordering shown in the Stitch screenshots is strictly:
  // 0: Files, 1: Favorites, 2: Search, 3: Tools, 4: Stats
  final List<Widget> _tabs = const [
    FilesTab(),
    FavoritesTab(),
    SearchTab(),
    ToolsTab(),
    StatsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: EditorialBottomBar(
        currentIndex: _currentIndex,
        onSelected: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
