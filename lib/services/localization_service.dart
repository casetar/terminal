import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'simple_storage_service.dart';

class LocalizationService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Use file storage on macOS/desktop to avoid unsigned Keychain issues
  static bool get _useSimple =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static final ValueNotifier<String> language = ValueNotifier<String>('ru');

  static Future<void> init() async {
    final saved = _useSimple
        ? await SimpleStorageService.read('app_language')
        : await _storage.read(key: 'app_language');
    if (saved != null) {
      language.value = saved;
    }
  }

  static Future<void> toggleLanguage() async {
    final next = language.value == 'ru' ? 'en' : 'ru';
    language.value = next;
    if (_useSimple) {
      await SimpleStorageService.write('app_language', next);
    } else {
      await _storage.write(key: 'app_language', value: next);
    }
  }

  static String translate(String key) {
    final lang = language.value;
    return _translations[lang]?[key] ?? _translations['en']?[key] ?? key;
  }

  static const _translations = {
    'ru': {
      'app_title': 'Terminal',
      'keys_title': 'SSH Ключи',
      'add_host': 'Добавить хост',
      'edit_host': 'Редактировать',
      'delete_host_confirm': 'Удалить хост?',
      'delete': 'Удалить',
      'cancel': 'Отмена',
      'no_hosts': 'Нет сохранённых хостов',
      'add_host_start': 'Нажмите «+» чтобы начать',
      'host_label': 'Название',
      'host_label_hint': 'Мой сервер',
      'host_ip': 'Хост / IP',
      'port': 'Порт',
      'username': 'Пользователь',
      'general': 'Основное',
      'authentication': 'Аутентификация',
      'password': 'Пароль',
      'ssh_key': 'SSH Ключ',
      'save': 'Сохранить',
      'saving': 'Сохранение...',
      'no_keys': 'Нет сохранённых ключей',
      'add_keys_hint': 'Добавьте ключи в разделе «SSH Ключи».',
      'select_key': 'Выберите ключ',
      'import_file': 'Импорт файла',
      'paste_pem': 'Вставить PEM',
      'key_name': 'Название ключа',
      'key_name_hint': 'Мой ключ',
      'save_key': 'Сохранить ключ',
      'enter_pem': 'Вставить ключ (PEM)',
      'connecting': 'Подключение...',
      'connected': 'Подключено',
      'disconnected': 'Отключено',
      'error': 'Ошибка',
      'command_hint': 'Команда...',
      'speak_hint': '🎤 Говорите...',
      'ctrl_c': 'Ctrl+C',
      'tab': 'Tab',
      'send': 'Отправить',
      'invalid_pem': 'Файл не похож на приватный ключ (PEM)',
      'confirm_delete_key': 'Удалить ключ?',
      'key_hint_import': 'Импортируйте .pem файл или вставьте ключ',
      'clear_terminal': 'Очистить терминал',
      'scroll_up': 'Прокрутить вверх',
      'scroll_down': 'Прокрутить вниз',
      'copy': 'Копировать',
      'paste': 'Вставить',
    },
    'en': {
      'app_title': 'Terminal',
      'keys_title': 'SSH Keys',
      'add_host': 'Add Host',
      'edit_host': 'Edit',
      'delete_host_confirm': 'Delete host?',
      'delete': 'Delete',
      'cancel': 'Cancel',
      'no_hosts': 'No saved hosts',
      'add_host_start': 'Tap "+" to start',
      'host_label': 'Label',
      'host_label_hint': 'My Server',
      'host_ip': 'Host / IP',
      'port': 'Port',
      'username': 'Username',
      'general': 'General',
      'authentication': 'Authentication',
      'password': 'Password',
      'ssh_key': 'SSH Key',
      'save': 'Save',
      'saving': 'Saving...',
      'no_keys': 'No saved keys',
      'add_keys_hint': 'Add keys in the "SSH Keys" section.',
      'select_key': 'Select Key',
      'import_file': 'Import File',
      'paste_pem': 'Paste PEM',
      'key_name': 'Key Label',
      'key_name_hint': 'My Key',
      'save_key': 'Save Key',
      'enter_pem': 'Paste Key (PEM)',
      'connecting': 'Connecting...',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'error': 'Error',
      'command_hint': 'Command...',
      'speak_hint': '🎤 Speak...',
      'ctrl_c': 'Ctrl+C',
      'tab': 'Tab',
      'send': 'Send',
      'invalid_pem': 'File does not look like a private key (PEM)',
      'confirm_delete_key': 'Delete key?',
      'key_hint_import': 'Import a .pem file or paste a key',
      'clear_terminal': 'Clear terminal',
      'scroll_up': 'Scroll up',
      'scroll_down': 'Scroll down',
      'copy': 'Copy',
      'paste': 'Paste',
    }
  };
}
