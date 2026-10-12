import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/services/sync_service.dart';

class SyncAccountScreen extends StatefulWidget {
  const SyncAccountScreen({super.key});

  @override
  State<SyncAccountScreen> createState() => _SyncAccountScreenState();
}

class _SyncAccountScreenState extends State<SyncAccountScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _obscurePassword = true;
  bool _isRegisterMode = false;

  @override
  void initState() {
    super.initState();
    final syncService = context.read<SyncService>();
    _serverUrlController.text = syncService.serverUrl;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncService = context.watch<SyncService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Облачная синхронизация'),
        actions: [
          if (syncService.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Синхронизировать сейчас',
              onPressed: syncService.isSyncing
                  ? null
                  : () => syncService.syncNow(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: syncService.isLoggedIn
                ? _buildLoggedInView(syncService, theme)
                : _buildAuthView(syncService, theme),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInView(SyncService syncService, ThemeData theme) {
    final vpsFile = syncService.vpsFileInfo;
    final fileSizeKb = ((vpsFile?.sizeBytes ?? 0) / 1024).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Account Profile Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                  child: Icon(
                    Icons.account_circle,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  syncService.username ?? 'Пользователь',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_done, color: Colors.greenAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      syncService.serverUrl,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Статус:'),
                    Flexible(
                      child: Text(
                        syncService.statusMessage ?? 'Подключено к VPS',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Последняя синхронизация:'),
                    Text(
                      syncService.lastSyncedAt != null
                          ? '${syncService.lastSyncedAt!.hour.toString().padLeft(2, '0')}:${syncService.lastSyncedAt!.minute.toString().padLeft(2, '0')}:${syncService.lastSyncedAt!.second.toString().padLeft(2, '0')}'
                          : 'Еще не выполнялась',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. VPS File Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.save_as_outlined, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Файл профиля на VPS',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            vpsFile != null && vpsFile.exists
                                ? '${vpsFile.filename} ($fileSizeKb КБ)'
                                : '${syncService.username}_data.json (сохраняется автоматически)',
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (vpsFile != null && vpsFile.exists)
                      const Chip(
                        label: Text('На сервере', style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.music_note, size: 16, color: Colors.cyanAccent),
                      label: Text('${vpsFile?.tracksCount ?? "—"} треков (лайков)'),
                      backgroundColor: Colors.white.withOpacity(0.06),
                    ),
                    Chip(
                      avatar: const Icon(Icons.person, size: 16, color: Colors.purpleAccent),
                      label: Text('${vpsFile?.artistsCount ?? "—"} авторов'),
                      backgroundColor: Colors.white.withOpacity(0.06),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Actions
        FilledButton.icon(
          onPressed: syncService.isSyncing
              ? null
              : () async {
                  await syncService.syncNow();
                  if (mounted && syncService.statusMessage != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(syncService.statusMessage!)),
                    );
                  }
                },
          icon: syncService.isSyncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.sync),
          label: Text(syncService.isSyncing ? 'Синхронизация...' : 'Синхронизировать сейчас'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: syncService.isSyncing
                    ? null
                    : () async {
                        final ok = await syncService.saveBackupFileToVps();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'Файл пользователя успешно сохранен на VPS'
                                  : 'Не удалось сохранить файл на VPS'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Сохранить на VPS'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: syncService.isSyncing
                    ? null
                    : () async {
                        _confirmRestoreFromVps(syncService);
                      },
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Восстановить с VPS'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _showExportDialog(syncService),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Экспорт .json'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _showImportDialog(syncService),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Импорт .json'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: () => _confirmLogout(syncService),
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.redAccent)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthView(SyncService syncService, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.cloud_sync_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          _isRegisterMode ? 'Создать аккаунт' : 'Вход в аккаунт',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Синхронизируйте вашу медиатеку и плейлисты между Linux, Android и Web',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _serverUrlController,
          decoration: const InputDecoration(
            labelText: 'Адрес сервера',
            prefixIcon: Icon(Icons.dns_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Логин',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Пароль',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (syncService.statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            syncService.statusMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: syncService.statusMessage!.contains('успешно')
                  ? Colors.greenAccent
                  : Colors.redAccent,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: syncService.isSyncing
              ? null
              : () async {
                  final user = _usernameController.text.trim();
                  final pass = _passwordController.text;
                  final url = _serverUrlController.text.trim();

                  if (user.isEmpty || pass.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Заполните логин и пароль')),
                    );
                    return;
                  }

                  if (_isRegisterMode) {
                    await syncService.register(user, pass, customUrl: url);
                  } else {
                    await syncService.login(user, pass, customUrl: url);
                  }
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: syncService.isSyncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isRegisterMode ? 'Зарегистрироваться' : 'Войти'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            setState(() {
              _isRegisterMode = !_isRegisterMode;
            });
          },
          child: Text(
            _isRegisterMode
                ? 'Уже есть аккаунт? Войти'
                : 'Нет аккаунта? Зарегистрироваться',
          ),
        ),
      ],
    );
  }

  void _confirmLogout(SyncService syncService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Локальные треки останутся на этом устройстве, но синхронизация будет приостановлена.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              syncService.logout();
            },
            child: const Text('Выйти', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmRestoreFromVps(SyncService syncService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Восстановить данные с VPS?'),
        content: const Text(
          'Все сохраненные авторы, любимые треки (лайки) и настройки будут загружены из вашего файла на VPS и объединены с текущей медиатекой.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await syncService.restoreFromVpsFile();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? (syncService.statusMessage ?? 'Данные успешно восстановлены с VPS')
                        : 'Ошибка восстановления файла с VPS'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.cloud_download),
            label: const Text('Восстановить'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportDialog(SyncService syncService) async {
    final jsonStr = await syncService.exportLocalBackupJson();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Экспорт файла данных'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Полная копия ваших авторов, лайков и настроек в формате JSON:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Container(
                height: 180,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    jsonStr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Файл JSON скопирован в буфер обмена')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Скопировать JSON'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(SyncService syncService) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт файла данных'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вставьте содержимое резервного JSON файла (авторы, лайки, настройки):',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '{\n  "library": [...],\n  "favorite_artists": [...]\n}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              final count = await syncService.importLocalBackupJson(text);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(count > 0
                        ? 'Успешно импортировано объектов: $count'
                        : 'Ошибка: некорректный формат JSON или пустой файл'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.file_download),
            label: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }
}
