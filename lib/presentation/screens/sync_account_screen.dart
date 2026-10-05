import 'package:flutter/material.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Статус:'),
                    Text(
                      syncService.statusMessage ?? 'Подключено',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
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
        const SizedBox(height: 20),
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
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
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
}
