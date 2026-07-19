import 'package:flutter/material.dart';
import '../widgets/app_navigation_drawer.dart';
import 'audio_test_screen.dart';

class GenreSelectScreen extends StatefulWidget {
  const GenreSelectScreen({super.key});

  @override
  State<GenreSelectScreen> createState() => _GenreSelectScreenState();
}

class _GenreSelectScreenState extends State<GenreSelectScreen> {
  String _searchQuery = '';

  final List<_Genre> _genres = const [
    _Genre(name: 'Rock', color: Color(0xFFE53935)),
    _Genre(name: 'Classic', color: Color(0xFF43A047)),
    _Genre(name: 'Pop', color: Color(0xFF5C6BC0)),
    _Genre(name: 'Ballad', color: Color(0xFFD4C03A)),
    _Genre(name: 'HipHop', color: Color(0xFF8E24AA)),
    _Genre(name: 'R&B', color: Color(0xFFE07B00)),
  ];

  List<_Genre> get _filtered {
    if (_searchQuery.isEmpty) return _genres;
    return _genres
        .where((g) => g.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: const AppNavigationDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: const AppDrawerButton(),
        title: _buildLogoTitle(),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Select a Genre',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              // Search bar
              TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Value',
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  suffixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF555555),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1C1C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Genre grid
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: _filtered.map((g) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AudioTestScreen(genre: g.name),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: g.color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          g.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoTitle() {
    return RichText(
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'kara',
            style: TextStyle(
              color: Color(0xFF4A90D9),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
          TextSpan(
            text: 'O',
            style: TextStyle(
              color: Color(0xFF4A90D9),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
          TextSpan(
            text: 'K',
            style: TextStyle(
              color: Color(0xFFFF8C00),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _Genre {
  const _Genre({required this.name, required this.color});
  final String name;
  final Color color;
}
