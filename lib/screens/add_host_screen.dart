import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/key_storage_service.dart';
import '../services/localization_service.dart';

class AddHostScreen extends StatefulWidget {
  final SshHost? editHost;
  const AddHostScreen({super.key, this.editHost});

  @override
  State<AddHostScreen> createState() => _AddHostScreenState();
}

class _AddHostScreenState extends State<AddHostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _authType = 'password';
  String? _selectedKeyId;
  List<Map<String, String>> _keys = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
    if (widget.editHost != null) {
      final h = widget.editHost!;
      _labelCtrl.text = h.label;
      _hostCtrl.text = h.host;
      _portCtrl.text = h.port.toString();
      _userCtrl.text = h.username;
      _authType = h.authType;
      _selectedKeyId = h.keyId;
    }
  }

  Future<void> _loadKeys() async {
    final keys = await KeyStorageService.getAllKeys();
    setState(() => _keys = keys);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final host = SshHost(
      id: widget.editHost?.id,
      label: _labelCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _userCtrl.text.trim(),
      authType: _authType,
      keyId: _authType == 'key' ? _selectedKeyId : null,
    );

    if (widget.editHost == null) {
      final id = await DatabaseService.insertHost(host);
      if (_authType == 'password' && _passCtrl.text.isNotEmpty) {
        await KeyStorageService.savePassword('$id', _passCtrl.text);
      }
    } else {
      await DatabaseService.updateHost(host);
      if (_authType == 'password' && _passCtrl.text.isNotEmpty) {
        await KeyStorageService.savePassword('${host.id}', _passCtrl.text);
      }
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.editHost == null;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(isNew ? LocalizationService.translate('add_host') : LocalizationService.translate('edit_host')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionLabel(LocalizationService.translate('general')),
            const SizedBox(height: 10),
            _Field(
              ctrl: _labelCtrl,
              label: LocalizationService.translate('host_label'),
              hint: LocalizationService.translate('host_label_hint'),
              icon: Icons.label_outline,
              validator: (v) => v!.isEmpty ? LocalizationService.translate('host_label') : null,
            ),
            const SizedBox(height: 12),
            _Field(
              ctrl: _hostCtrl,
              label: LocalizationService.translate('host_ip'),
              hint: '192.168.1.1',
              icon: Icons.dns_outlined,
              validator: (v) => v!.isEmpty ? LocalizationService.translate('host_ip') : null,
              keyboard: TextInputType.url,
            ),
            const SizedBox(height: 12),
            _Field(
              ctrl: _portCtrl,
              label: LocalizationService.translate('port'),
              hint: '22',
              icon: Icons.electrical_services,
              validator: (v) => int.tryParse(v!) == null ? '?' : null,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _Field(
              ctrl: _userCtrl,
              label: LocalizationService.translate('username'),
              hint: 'root',
              icon: Icons.person_outline,
              validator: (v) => v!.isEmpty ? LocalizationService.translate('username') : null,
            ),
            const SizedBox(height: 24),
            _SectionLabel(LocalizationService.translate('authentication')),
            const SizedBox(height: 10),
            // Auth type toggle
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  _AuthTypeBtn(
                    label: LocalizationService.translate('password'),
                    icon: Icons.lock_outline,
                    selected: _authType == 'password',
                    onTap: () => setState(() => _authType = 'password'),
                  ),
                  _AuthTypeBtn(
                    label: LocalizationService.translate('ssh_key'),
                    icon: Icons.vpn_key_outlined,
                    selected: _authType == 'key',
                    onTap: () => setState(() => _authType = 'key'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_authType == 'password')
              _Field(
                ctrl: _passCtrl,
                label: LocalizationService.translate('password'),
                hint: widget.editHost != null ? '(сохранён)' : '••••••••',
                icon: Icons.key,
                obscure: true,
                validator: (v) =>
                    widget.editHost == null && v!.isEmpty ? LocalizationService.translate('password') : null,
              ),
            if (_authType == 'key')
              _keys.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.vpn_key_off, color: AppTheme.textSecondary),
                          const SizedBox(height: 8),
                          Text(
                            '${LocalizationService.translate('no_keys')}\n${LocalizationService.translate('add_keys_hint')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _selectedKeyId,
                      dropdownColor: AppTheme.card,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: LocalizationService.translate('select_key'),
                        prefixIcon: const Icon(Icons.vpn_key_outlined, color: AppTheme.accentPurple),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: _keys.map((k) => DropdownMenuItem(
                        value: k['id'],
                        child: Text(k['label'] ?? k['id']!),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedKeyId = v),
                      validator: (v) => _authType == 'key' && v == null ? LocalizationService.translate('select_key') : null,
                    ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bg),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? LocalizationService.translate('saving') : LocalizationService.translate('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final String? Function(String?)? validator;
  final TextInputType? keyboard;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.validator,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        validator: validator,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary),
        ),
      );
}

class _AuthTypeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AuthTypeBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: AppTheme.accent.withValues(alpha: 0.5))
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? AppTheme.accent : AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
