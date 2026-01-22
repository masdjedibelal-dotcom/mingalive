import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_bottom_nav.dart';
import 'search_entry_screen.dart';
import 'home_screen.dart';
import 'stream_screen.dart';
import 'profile_screen.dart';
import 'list_screen.dart';

/// Global key for accessing MainShell state from other screens
final GlobalKey<_MainShellState> mainShellKey = GlobalKey<_MainShellState>();

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
  
  /// Get the current MainShell state instance
  static _MainShellState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MainShellState>() ??
        mainShellKey.currentState;
  }
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  String? _activeRoomId;
  String? _activePlaceId;
  final GlobalKey<StreamScreenState> _streamScreenKey =
      GlobalKey<StreamScreenState>();
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    3,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// Switches to the Stream tab (index 1)
  void switchToStreamTab() {
    switchToTab(1);
  }

  /// Switch to Stream tab and open a room by placeId (deterministic)
  void openPlaceChat(String placeId) {
    final roomId = 'place_$placeId';
    debugPrint('🟣 openPlaceChat -> placeId=$placeId');
    setState(() {
      _activePlaceId = placeId;
      _activeRoomId = roomId;
      _currentIndex = 1;
    });
    // Ensure any pushed routes are dismissed so Stream is visible.
    _popToRoot(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _streamScreenKey.currentState?.jumpToPlace(placeId);
    });
  }

  /// Open ListScreen with injected openPlaceChat callback
  void openListScreen({
    required BuildContext context,
    String? categoryName,
    String? searchTerm,
    required String kind,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ListScreen(
          categoryName: categoryName,
          searchTerm: searchTerm,
          kind: kind,
          openPlaceChat: openPlaceChat,
        ),
      ),
    );
  }

  /// Switches to a specific tab by index
  void switchToTab(int index) {
    if (index >= 0 && index < 3) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SearchEntryScreen(
          kind: 'food',
          openPlaceChat: openPlaceChat,
        ),
      ),
    );
  }

  void _popToRoot(int index) {
    final navigator = _navigatorKeys[index].currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
  }

  Widget _buildTabNavigator({
    required int index,
    required Widget child,
  }) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(builder: (_) => child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Main navigation screens - using IndexedStack to preserve state
    final List<Widget> screens = [
      _buildTabNavigator(
        index: 0,
        child: HomeScreen(onStreamTap: switchToStreamTab),
      ),
      _buildTabNavigator(
        index: 1,
        child: StreamScreen(
          key: _streamScreenKey,
          activeRoomId: _activeRoomId,
          activePlaceId: _activePlaceId,
        ),
      ),
      _buildTabNavigator(
        index: 2,
        child: const ProfileScreen(),
      ),
    ];

    return WillPopScope(
      onWillPop: () async {
        final currentNavigator = _navigatorKeys[_currentIndex].currentState;
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
          return false;
        }
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: GlassBottomNav(
          currentIndex: _currentIndex,
          onTap: switchToTab,
          onSearch: () => _openSearch(context),
          items: const [
            GlassBottomNavItem(icon: Icons.home_filled, label: 'Live'),
            GlassBottomNavItem(icon: Icons.play_circle_filled, label: 'Stream'),
            GlassBottomNavItem(icon: Icons.person_outline, label: 'Profil'),
          ],
        ),
      ),
    );
  }
}
