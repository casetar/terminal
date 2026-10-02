import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../services/ssh_session_manager.dart';
import 'terminal_screen.dart';
import 'keys_screen.dart';
import 'add_host_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SshHost> _hosts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHosts();
  }

  Future<void> _loadHosts() async {
    final hosts = await DatabaseService.getHosts();
    setState(() {
      _hosts = hosts;
      _loading = false;
    });
  }

  Future<void> _deleteHost(SshHost host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(LocalizationService.translate('delete_host_confirm'), style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '${host.label} (${host.host})',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(LocalizationService.translate('cancel'), style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(LocalizationService.translate('delete'), style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.deleteHost(host.id!);
      _loadHosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.terminal, color: AppTheme.accent, size: 18),
            ),
            const SizedBox(width: 10),
            Text(LocalizationService.translate('app_title')),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined, color: AppTheme.accentPurple),
            tooltip: LocalizationService.translate('keys_title'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KeysScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _hosts.isEmpty
              ? _buildEmpty()
              : _buildHostList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddHostScreen()),
          );
          _loadHosts();
        },
        backgroundColor: AppTheme.accent,
        foregroundColor: AppTheme.bg,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white24, width: 1.5),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(Icons.dns_outlined, color: AppTheme.textSecondary, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            LocalizationService.translate('no_hosts'),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            LocalizationService.translate('add_host_start'),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHostList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _hosts.length,
      itemBuilder: (ctx, i) {
        final host = _hosts[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _HostCard(
            host: host,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TerminalScreen(host: host)),
              );
              _loadHosts();
            },
            onDelete: () => _deleteHost(host),
            onEdit: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddHostScreen(editHost: host)),
              );
              _loadHosts();
            },
          ),
        );
      },
    );
  }
}

class _HostCard extends StatelessWidget {
  final SshHost host;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _HostCard({
    required this.host,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isKey = host.authType == 'key';
    final activeSession = host.id != null ? SshSessionManager.getSession(host.id!) : null;
    final isConnected = activeSession != null && activeSession.connected;

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isConnected 
                  ? AppTheme.accentGreen.withValues(alpha: 0.5) 
                  : AppTheme.border,
              width: isConnected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppTheme.accentGreen.withValues(alpha: 0.1)
                      : AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isConnected
                        ? AppTheme.accentGreen.withValues(alpha: 0.3)
                        : AppTheme.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.computer,
                  color: isConnected ? AppTheme.accentGreen : AppTheme.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            host.label,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.accentGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${host.username}@${host.host}:${host.port}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isKey
                      ? AppTheme.accentPurple.withValues(alpha: 0.15)
                      : AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isKey
                        ? AppTheme.accentPurple.withValues(alpha: 0.4)
                        : AppTheme.accentGreen.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isKey ? Icons.vpn_key : Icons.lock_outline,
                      size: 11,
                      color: isKey ? AppTheme.accentPurple : AppTheme.accentGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isKey ? 'key' : 'pwd',
                      style: TextStyle(
                        color: isKey ? AppTheme.accentPurple : AppTheme.accentGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                color: AppTheme.card,
                icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      const Icon(Icons.edit_outlined, color: AppTheme.accent, size: 16),
                      const SizedBox(width: 10),
                      Text(LocalizationService.translate('edit_host'), style: const TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline, color: AppTheme.danger, size: 16),
                      const SizedBox(width: 10),
                      Text(LocalizationService.translate('delete'), style: const TextStyle(color: AppTheme.danger)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
