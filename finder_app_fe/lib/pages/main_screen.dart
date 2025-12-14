import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'notification_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static final GlobalKey<_MainScreenState> navigatorKey =
      GlobalKey<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    HomeScreen(key: HomeScreen.homeKey),
    const NotificationScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    // If Post (index 2) is tapped, show post options dialog
    if (index == 2) {
      _showPostOptions();
      return;
    }

    // Adjust index for pages array (Post button doesn't have a page)
    // Navigation indices: 0=Home, 1=Notification, 2=Post, 3=Chat, 4=Profile
    // Pages indices: 0=Home, 1=Notification, 2=Chat, 3=Profile
    int pageIndex = index > 2 ? index - 1 : index;

    setState(() {
      _selectedIndex = pageIndex;
    });
  }

  void _showPostOptions() {
    // Call the home screen's showReportOptions method
    HomeScreen.homeKey.currentState?.showReportOptions();
  }

  void navigateToTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Map page index back to navigation index for highlighting
    // Pages indices: 0=Home, 1=Notification, 2=Chat, 3=Profile
    // Navigation indices: 0=Home, 1=Notification, 2=Post, 3=Chat, 4=Profile
    int navIndex = _selectedIndex >= 2 ? _selectedIndex + 1 : _selectedIndex;

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_rounded),
            label: 'Notification',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_rounded),
            label: 'Post',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_rounded),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
        currentIndex: navIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}
