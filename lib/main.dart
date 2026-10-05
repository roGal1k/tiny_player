import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/search_screen.dart';
import 'presentation/screens/downloads_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/controllers/audio_player_controller.dart';
import 'presentation/widgets/mini_player_widget.dart';
import 'data/providers/provider_registry.dart';
import 'data/providers/local_provider.dart';
import 'data/providers/jamendo_provider.dart';
import 'data/providers/internet_archive_provider.dart';
import 'data/providers/soundcloud_provider.dart';
import 'data/providers/vk_provider.dart';
import 'data/providers/freesound_provider.dart';
import 'data/providers/hitmo_provider.dart';
import 'data/providers/youtube_provider.dart';
import 'data/services/local_library_service.dart';
import 'data/services/download_manager.dart';
import 'data/services/genius_lyrics_service.dart';
import 'data/services/equalizer_service.dart';
import 'data/services/settings_service.dart';
import 'data/services/audio_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  final settingsService = SettingsService();
  await settingsService.loadSettings();

  final registry = ProviderRegistry();
  registry.registerProvider(LocalProvider());
  final initialHitmoUrl = settingsService.hitmoMirrorUrl.isNotEmpty
      ? settingsService.hitmoMirrorUrl
      : (dotenv.env['HITMO_MIRROR_URL'] ?? 'https://ru.hitmoz.org');
  registry.registerProvider(HitmoProvider(mirrorUrl: initialHitmoUrl));
  registry.registerProvider(YouTubeProvider());
  registry.registerProvider(SoundCloudProvider(clientId: dotenv.env['SC_CLIENT_ID']));
  registry.registerProvider(JamendoProvider());
  registry.registerProvider(InternetArchiveProvider());
  registry.registerProvider(FreesoundProvider(apiKey: dotenv.env['FREESOUND_API_KEY']));
  registry.registerProvider(VkProvider(accessToken: dotenv.env['VK_TOKEN']));
  registry.syncDisabledProviders(settingsService.disabledProviders);

  final audioCacheService = AudioCacheService();
  await audioCacheService.init();

  final localLibraryService = LocalLibraryService();
  final downloadManager = DownloadManager(
    registry: registry,
    libraryService: localLibraryService,
  );
  final lyricsService = GeniusLyricsService(
    accessToken: dotenv.env['GENIUS_ACCESS_TOKEN'],
    clientId: dotenv.env['GENIUS_CLIENT_ID'],
    clientSecret: dotenv.env['GENIUS_CLIENT_SECRET'],
  );
  final equalizerService = EqualizerService();
  await equalizerService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<ProviderRegistry>.value(value: registry),
        Provider<GeniusLyricsService>.value(value: lyricsService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<AudioCacheService>.value(value: audioCacheService),
        ChangeNotifierProvider<LocalLibraryService>.value(value: localLibraryService),
        ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
        ChangeNotifierProvider<EqualizerService>.value(value: equalizerService),
        ChangeNotifierProvider<AudioPlayerController>(
          create: (_) => AudioPlayerController(
            registry: registry,
            equalizerService: equalizerService,
            settingsService: settingsService,
            cacheService: audioCacheService,
          ),
        ),
      ],
      child: const CorePlayerApp(),
    ),
  );
}

class CorePlayerApp extends StatelessWidget {
  const CorePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService?>(context);
    return MaterialApp(
      title: 'Core Player',
      debugShowCheckedModeBanner: false,
      theme: settings?.themeData ?? ThemeData.dark(),
      themeMode: settings?.flutterThemeMode ?? ThemeMode.dark,
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    HomeScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Basic responsive layout detection
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    
    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: Text('Search'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: Text('Library'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.download_outlined),
                  selectedIcon: Icon(Icons.download),
                  label: Text('Downloads'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: _screens,
                    ),
                  ),
                  const MiniPlayerWidget(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile layout
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
          const MiniPlayerWidget(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
