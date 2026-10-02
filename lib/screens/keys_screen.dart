import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../theme/app_theme.dart';
import '../services/key_storage_service.dart';
import '../services/localization_service.dart';

class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  List<Map<String, String>> _keys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keys = await KeyStorageService.getAllKeys();
    setState(() {
      _keys = keys;
      _loading = false;
    });
  }

  Future<void> _importKey() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();

    // Validate it looks like a PEM key
    if (!content.contains('PRIVATE KEY')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.translate('invalid_pem')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    final labelCtrl = TextEditingController(
      text: result.files.first.name.replaceAll('.pem', '').replaceAll('id_', ''),
    );
    final passCtrl = TextEditingController();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(LocalizationService.translate('save_key'), style: const TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: LocalizationService.translate('key_name'),
                hintText: LocalizationService.translate('key_name_hint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                hintText: 'Optional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationService.translate('cancel'), style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await KeyStorageService.saveKey(
                label: labelCtrl.text.trim().isEmpty ? 'Key' : labelCtrl.text.trim(),
                privateKey: content,
                passphrase: passCtrl.text.isEmpty ? null : passCtrl.text,
              );
              if (mounted) Navigator.pop(context);
              _loadKeys();
            },
            child: Text(LocalizationService.translate('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteKey() async {
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController(text: 'Key');
    final passCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(LocalizationService.translate('enter_pem'), style: const TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(labelText: LocalizationService.translate('key_name')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyCtrl,
                maxLines: 6,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  labelText: LocalizationService.translate('paste_pem'),
                  hintText: '-----BEGIN RSA PRIVATE KEY-----\n...',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Passphrase',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocalizationService.translate('cancel'), style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (keyCtrl.text.isEmpty) return;
              await KeyStorageService.saveKey(
                label: labelCtrl.text.isEmpty ? 'Key' : labelCtrl.text,
                privateKey: keyCtrl.text,
                passphrase: passCtrl.text.isEmpty ? null : passCtrl.text,
              );
              if (mounted) Navigator.pop(context);
              _loadKeys();
            },
            child: Text(LocalizationService.translate('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteKey(String id, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(LocalizationService.translate('confirm_delete_key'), style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
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
      await KeyStorageService.deleteKey(id);
      _loadKeys();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(LocalizationService.translate('keys_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(
              children: [
                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.folder_open_outlined,
                          label: LocalizationService.translate('import_file'),
                          color: AppTheme.accentPurple,
                          onTap: _importKey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.paste_outlined,
                          label: LocalizationService.translate('paste_pem'),
                          color: AppTheme.accent,
                          onTap: _pasteKey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_keys.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.vpn_key_off, color: AppTheme.textSecondary, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            LocalizationService.translate('no_keys'),
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            LocalizationService.translate('key_hint_import'),
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _keys.length,
                      itemBuilder: (_, i) {
                        final key = _keys[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.accentPurple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.3)),
                              ),
                              child: const Icon(Icons.vpn_key, color: AppTheme.accentPurple, size: 20),
                            ),
                            title: Text(
                              key['label'] ?? 'Ключ',
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'ID: ${key['id']}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                              onPressed: () => _deleteKey(key['id']!, key['label'] ?? 'Ключ'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
}
