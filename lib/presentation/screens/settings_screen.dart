import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/equalizer_service.dart';
import '../../data/services/local_library_service.dart';
import '../../data/providers/provider_registry.dart';
import '../../data/providers/hitmo_provider.dart';
import '../controllers/audio_player_controller.dart';
import 'equalizer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _hitmoMirrorController;
  bool _isTestingHitmo = false;
  bool? _hitmoTestSuccess;
  String? _hitmoTestMessage;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsService?>(context, listen: false);
    _hitmoMirrorController = TextEditingController(text: settings?.hitmoMirrorUrl ?? 'https://ru.hitmoz.org');
  }

  @override
  void dispose() {
    _hitmoMirrorController.dispose();
    super.dispose();
  }

  Future<void> _testHitmoMirror(SettingsService settings) async {
    final url = _hitmoMirrorController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isTestingHitmo = true;
      _hitmoTestSuccess = null;
      _hitmoTestMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    final success = await settings.testHitmoMirror(url);
    stopwatch.stop();

    if (mounted) {
      setState(() {
        _isTestingHitmo = false;
        _hitmoTestSuccess = success;
        _hitmoTestMessage = success
            ? 'Доступно (HTTP OK, ${stopwatch.elapsedMilliseconds}ms)'
            : 'Недоступно или ошибка таймаута';
      });
    }
  }

  Future<void> _saveHitmoMirror(SettingsService settings, ProviderRegistry? registry) async {
    final url = _hitmoMirrorController.text.trim();
    if (url.isEmpty) return;

    await settings.setHitmoMirrorUrl(url);

    // Update HitmoProvider mirror URL dynamically in the registry
    if (registry != null) {
      for (final provider in registry.allProviders) {
        if (provider is HitmoProvider) {
          provider.updateMirrorUrl(url);
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Зеркало Hitmo сохранено: $url'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Color _getProviderColor(String id) {
    switch (id.toLowerCase()) {
      case 'hitmo':
        return Colors.pinkAccent;
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'vk':
        return Colors.lightBlueAccent;
      case 'soundcloud':
        return Colors.orangeAccent;
      case 'jamendo':
        return Colors.redAccent;
      case 'internet_archive':
        return Colors.blueAccent;
      case 'freesound':
        return Colors.tealAccent;
      case 'local':
        return Colors.purpleAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  IconData _getProviderIcon(String id) {
    switch (id.toLowerCase()) {
      case 'hitmo':
        return Icons.music_video;
      case 'youtube':
        return Icons.smart_display;
      case 'vk':
        return Icons.record_voice_over;
      case 'soundcloud':
        return Icons.cloud_queue;
      case 'jamendo':
        return Icons.album;
      case 'internet_archive':
        return Icons.archive;
      case 'freesound':
        return Icons.graphic_eq;
      case 'local':
        return Icons.folder;
      default:
        return Icons.library_music;
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required BuildContext context, required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsService?>(context);
    final audioCtrl = Provider.of<AudioPlayerController?>(context);
    final eq = Provider.of<EqualizerService?>(context);
    final registry = Provider.of<ProviderRegistry?>(context);
    final libraryService = Provider.of<LocalLibraryService?>(context);

    if (settings == null) {
      return const Scaffold(
        body: Center(child: Text('Загрузка настроек...')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // -----------------------------------------------------------
          // СЕКЦИЯ 1: Аудио и Воспроизведение
          // -----------------------------------------------------------
          _buildSectionHeader(context, 'Аудио и Воспроизведение', Icons.volume_up),
          _buildCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Master volume row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Основная громкость',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${((audioCtrl?.volume ?? settings.volume) * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        (audioCtrl?.isMuted ?? settings.isMuted) ||
                                (audioCtrl?.volume ?? settings.volume) == 0
                            ? Icons.volume_off
                            : Icons.volume_up,
                        color: (audioCtrl?.isMuted ?? settings.isMuted)
                            ? Colors.redAccent
                            : theme.colorScheme.primary,
                      ),
                      tooltip: (audioCtrl?.isMuted ?? settings.isMuted)
                          ? 'Включить звук'
                          : 'Выключить звук',
                      onPressed: () {
                        if (audioCtrl != null) {
                          audioCtrl.toggleMute();
                        } else {
                          settings.toggleMute();
                        }
                      },
                    ),
                    Expanded(
                      child: Slider(
                        value: audioCtrl?.volume ?? settings.volume,
                        min: 0.0,
                        max: 1.0,
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: theme.dividerColor,
                        onChanged: (val) {
                          if (audioCtrl != null) {
                            audioCtrl.setVolume(val);
                          } else {
                            settings.setVolume(val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Автовоспроизведение следующего трека
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Автовоспроизведение очереди',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Автоматически проигрывать следующий трек после окончания текущего',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  value: settings.autoPlayNext,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (val) => settings.setAutoPlayNext(val),
                ),
                const Divider(height: 24),

                // Скорость воспроизведения по умолчанию
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Скорость по умолчанию',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${settings.defaultPlaybackRate}x',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [0.75, 1.0, 1.25, 1.5, 2.0].map((rate) {
                    final isSelected = (settings.defaultPlaybackRate - rate).abs() < 0.05;
                    return ChoiceChip(
                      label: Text('${rate}x'),
                      selected: isSelected,
                      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: isSelected ? theme.colorScheme.primary : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) {
                        settings.setDefaultPlaybackRate(rate);
                        audioCtrl?.setPlaybackRate(rate);
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 24),

                // Карточка DSP Эквалайзера
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (eq?.isEnabled ?? false)
                              ? Colors.tealAccent.withValues(alpha: 0.15)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.tune,
                          color: (eq?.isEnabled ?? false) ? Colors.tealAccent : Colors.white60,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Эквалайзер & Тюнер',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (eq?.isEnabled ?? false)
                                  ? 'Активен: ${eq!.currentPresetName} (Предусилитель: ${eq.preampDb >= 0 ? '+' : ''}${eq.preampDb.toStringAsFixed(1)} dB)'
                                  : 'Выключен (DSP Bypass)',
                              style: TextStyle(
                                fontSize: 12,
                                color: (eq?.isEnabled ?? false) ? Colors.tealAccent : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => EqualizerScreen.showAsBottomSheet(context),
                        child: const Text('Настроить', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // -----------------------------------------------------------
          // СЕКЦИЯ 2: Источники и Зеркала (Провайдеры)
          // -----------------------------------------------------------
          _buildSectionHeader(context, 'Источники и Зеркала', Icons.hub_outlined),
          _buildCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Зеркало Hitmo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Адрес зеркала для поиска и стриминга из каталога Hitmo',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hitmoMirrorController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.link, size: 20),
                    hintText: 'https://ru.hitmoz.org',
                    isDense: true,
                    filled: true,
                    fillColor: theme.scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    suffixIcon: _hitmoMirrorController.text != settings.hitmoMirrorUrl
                        ? IconButton(
                            icon: const Icon(Icons.restore, size: 18),
                            tooltip: 'Сбросить к сохраненному',
                            onPressed: () {
                              setState(() {
                                _hitmoMirrorController.text = settings.hitmoMirrorUrl;
                              });
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isTestingHitmo ? null : () => _testHitmoMirror(settings),
                      icon: _isTestingHitmo
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_ping, size: 16),
                      label: const Text('Проверить пинг'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _saveHitmoMirror(settings, registry),
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Сохранить'),
                    ),
                  ],
                ),
                if (_hitmoTestMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _hitmoTestSuccess == true
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hitmoTestSuccess == true ? Colors.greenAccent : Colors.redAccent,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hitmoTestSuccess == true ? Icons.check_circle : Icons.error_outline,
                          size: 16,
                          color: _hitmoTestSuccess == true ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hitmoTestMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _hitmoTestSuccess == true ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 28),

                const Text(
                  'Активные музыкальные провайдеры',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Отключенные провайдеры не опрашиваются при глобальном поиске',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 8),

                if (registry != null) ...[
                  ...registry.allProviders.map((provider) {
                    final isEnabled = settings.isProviderEnabled(provider.providerId);
                    final color = _getProviderColor(provider.providerId);
                    final icon = _getProviderIcon(provider.providerId);

                    return SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      title: Text(
                        provider.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        provider.providerId,
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: isEnabled,
                      activeColor: theme.colorScheme.primary,
                      onChanged: (val) {
                        settings.setProviderEnabled(provider.providerId, val);
                        registry.setProviderEnabled(provider.providerId, val);
                      },
                    );
                  }),
                ] else ...[
                  const Text('Провайдеры загружаются...', style: TextStyle(color: Colors.white54)),
                ],
              ],
            ),
          ),

          // -----------------------------------------------------------
          // СЕКЦИЯ 3: Хранилище и Библиотека
          // -----------------------------------------------------------
          _buildSectionHeader(context, 'Хранилище и Библиотека', Icons.folder_special_outlined),
          _buildCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Локальная фонотека',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${libraryService?.tracks.length ?? 0} треков',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Треки, сохраненные локально или добавленные из файловой системы',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    if (libraryService != null) {
                      await libraryService.loadLibrary();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Фонотека обновлена. Найдено треков: ${libraryService.tracks.length}'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Пересканировать библиотеку'),
                ),
              ],
            ),
          ),

          // -----------------------------------------------------------
          // СЕКЦИЯ 4: Внешний вид и Тема
          // -----------------------------------------------------------
          _buildSectionHeader(context, 'Внешний вид и Оформление', Icons.palette_outlined),
          _buildCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Тема интерфейса',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildThemeChip(context, settings, 'dark', 'Темная', Icons.dark_mode_outlined),
                    _buildThemeChip(context, settings, 'oled', 'OLED Черная', Icons.brightness_1),
                    _buildThemeChip(context, settings, 'light', 'Светлая', Icons.light_mode_outlined),
                    _buildThemeChip(context, settings, 'system', 'Системная', Icons.settings_brightness),
                  ],
                ),
                const Divider(height: 24),

                const Text(
                  'Цветовой акцент',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _buildColorChip(context, settings, 'cyan', 'Cyan', Colors.cyanAccent),
                    _buildColorChip(context, settings, 'purple', 'Purple', Colors.purpleAccent),
                    _buildColorChip(context, settings, 'emerald', 'Emerald', Colors.tealAccent),
                    _buildColorChip(context, settings, 'amber', 'Amber', Colors.amberAccent),
                    _buildColorChip(context, settings, 'pink', 'Pink', Colors.pinkAccent),
                  ],
                ),
              ],
            ),
          ),

          // -----------------------------------------------------------
          // СЕКЦИЯ 5: О приложении
          // -----------------------------------------------------------
          _buildSectionHeader(context, 'О приложении', Icons.info_outline),
          _buildCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.music_note, color: Colors.black, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'CorePlayer',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Версия 1.2.0 • Pro Edition',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Мультиплатформенный аудиокомбайн с поддержкой онлайн-поиска (Hitmo, SoundCloud, VK, Jamendo, Internet Archive, Freesound), AIMP-подобного DSP 10-полосного эквалайзера с тюнером, очередью треков и текстами песен Genius.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: ['MP3', 'FLAC', 'AAC', 'WAV', 'OGG', 'M4A'].map((fmt) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        fmt,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white60),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80), // Bottom padding for mini-player
        ],
      ),
    );
  }

  Widget _buildThemeChip(
    BuildContext context,
    SettingsService settings,
    String modeKey,
    String label,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final isSelected = settings.themeMode == modeKey;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? theme.colorScheme.primary : Colors.white70,
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? theme.colorScheme.primary : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => settings.setThemeMode(modeKey),
    );
  }

  Widget _buildColorChip(
    BuildContext context,
    SettingsService settings,
    String colorKey,
    String label,
    Color color,
  ) {
    final theme = Theme.of(context);
    final isSelected = settings.accentColor == colorKey;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => settings.setAccentColor(colorKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : theme.dividerColor.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
