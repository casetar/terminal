import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/key_storage_service.dart';
import '../services/localization_service.dart';
import '../services/ssh_session_manager.dart';
import 'sftp_screen.dart';

class TerminalScreen extends StatefulWidget {
  final SshHost host;
  const TerminalScreen({super.key, required this.host});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal terminal;
  late final TerminalController terminalController;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  SSHClient? _client;
  SSHSession? _session;
  bool _connected = false;
  // ignore: unused_field
  bool _loading = true;
  String _statusMsg = '';

  // Voice
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  String _voiceBuffer = '';

  // Arrow keys overlay (shown after Escape)
  bool _showArrows = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initSession();
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();

    // On macOS, permission_handler doesn't integrate with the sandbox —
    // speech_to_text handles the system permission dialog itself.
    // On Android/iOS we still use permission_handler.
    final bool micGranted;
    if (!Platform.isMacOS) {
      micGranted = await Permission.microphone.request().isGranted;
    } else {
      micGranted = true; // macOS: let speech_to_text trigger the system prompt
    }

    if (!micGranted) {
      debugPrint('Microphone permission denied');
      _speechAvailable = false;
      if (mounted) setState(() {});
      return;
    }

    _speechAvailable = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech error: ${error.errorMsg}');
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
      },
    );

    if (mounted) setState(() {});
  }

  void _initSession() {
    final existing = widget.host.id != null
        ? SshSessionManager.getSession(widget.host.id!)
        : null;
    if (existing != null && !existing.client.isClosed) {
      terminal = existing.terminal;
      terminalController = existing.terminalController;
      _client = existing.client;
      _session = existing.session;
      _connected = existing.connected;
      _statusMsg = existing.statusMsg;
      _loading = false;

      // Ensure the terminal's onOutput updates for our current state
      terminal.onOutput = (data) {
        _session?.write(utf8.encode(data));
      };

      // Set up onResize callback for existing session
      terminal.onResize = (width, height, pxWidth, pxHeight) {
        _session?.resizeTerminal(width, height);
      };
    } else {
      // Discard broken session if any
      if (widget.host.id != null) {
        SshSessionManager.removeSessionOnly(widget.host.id!);
      }
      terminal = Terminal(maxLines: 10000);
      terminalController = TerminalController();
      _statusMsg = LocalizationService.translate('connecting');
      _connect();
    }
  }

  Future<void> _connect() async {
    try {
      try {
        _session?.close();
      } catch (_) {}
      try {
        _client?.close();
      } catch (_) {}

      terminal
          .write('\r\n\x1b[36m┌─────────────────────────────────┐\x1b[0m\r\n');
      terminal.write('\x1b[36m│  Terminal                            │\x1b[0m\r\n');
      terminal
          .write('\x1b[36m└─────────────────────────────────┘\x1b[0m\r\n\r\n');
      terminal.write(
          '\x1b[33m⟶ ${LocalizationService.translate('connecting')} ${widget.host.host}:${widget.host.port}...\x1b[0m\r\n');

      SSHClient client;
      if (widget.host.authType == 'key' && widget.host.keyId != null) {
        final pem = await KeyStorageService.getKeyPem(widget.host.keyId!);
        final pass =
            await KeyStorageService.getKeyPassphrase(widget.host.keyId!);
        client = SSHClient(
          await SSHSocket.connect(widget.host.host, widget.host.port),
          username: widget.host.username,
          identities: [
            ...SSHKeyPair.fromPem(pem!, pass),
          ],
          keepAliveInterval: const Duration(seconds: 15),
        );
      } else {
        final password =
            await KeyStorageService.getPassword('${widget.host.id}');
        client = SSHClient(
          await SSHSocket.connect(widget.host.host, widget.host.port),
          username: widget.host.username,
          onPasswordRequest: () => password ?? '',
          onUserInfoRequest: (request) =>
              request.prompts.map((p) => password ?? '').toList(),
          keepAliveInterval: const Duration(seconds: 15),
        );
      }

      _client = client;
      final session = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      _session = session;

      // Set up onResize callback for new session
      terminal.onResize = (width, height, pxWidth, pxHeight) {
        session.resizeTerminal(width, height);
      };

      terminal.write(
          '\x1b[32m✓ ${LocalizationService.translate('connected')}!\x1b[0m\r\n\r\n');
      setState(() {
        _connected = true;
        _loading = false;
        _statusMsg = LocalizationService.translate('connected');
      });

      // Auto-attach or install tmux to persist the session
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_connected && _session != null) {
          const tmuxCmd = 'if ! command -v tmux >/dev/null 2>&1; then '
              'echo "Installing tmux on server..."; '
              'if [ "\$(id -u)" = "0" ]; then '
              '  (apt-get update && apt-get install -y tmux) || (yum install -y tmux) || (apk add tmux); '
              'else '
              '  (sudo apt-get update && sudo apt-get install -y tmux) || (sudo yum install -y tmux) || (sudo apk add tmux); '
              'fi; '
              'fi; '
              'tmux attach -t savun || tmux new -s savun || exec \$SHELL\n';
          _sendInput(tmuxCmd);
        }
      });

      if (widget.host.id != null) {
        SshSessionManager.addSession(
          widget.host.id!,
          SshSession(
            client: client,
            session: session,
            terminal: terminal,
            terminalController: terminalController,
            host: widget.host,
            connected: true,
            statusMsg: _statusMsg,
          ),
        );
      }

      // Pipe terminal ↔ SSH
      terminal.onOutput = (data) {
        session.write(utf8.encode(data));
      };

      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((text) {
        terminal.write(text);
      });

      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((text) {
        terminal.write('\x1b[31m$text\x1b[0m');
      });

      client.done.then((_) {
        if (widget.host.id != null) {
          final currentSession = SshSessionManager.getSession(widget.host.id!);
          if (currentSession != null && currentSession.client == client) {
            SshSessionManager.removeSessionOnly(widget.host.id!);
          }
        }
        if (mounted && _connected) {
          terminal.write(
              '\r\n\x1b[33m[${LocalizationService.translate('disconnected')}]\x1b[0m\r\n');
          setState(() {
            _connected = false;
            _loading = false;
            _statusMsg = LocalizationService.translate('disconnected');
          });
        }
      });

      session.done.then((_) {
        if (widget.host.id != null) {
          final currentSession = SshSessionManager.getSession(widget.host.id!);
          if (currentSession != null && currentSession.session == session) {
            SshSessionManager.removeSessionOnly(widget.host.id!);
          }
        }
        if (mounted && _connected) {
          terminal.write(
              '\r\n\x1b[33m[${LocalizationService.translate('disconnected')}]\x1b[0m\r\n');
          setState(() {
            _connected = false;
            _loading = false;
            _statusMsg = LocalizationService.translate('disconnected');
          });
        }
      });
    } catch (e) {
      terminal.write(
          '\x1b[31m✗ ${LocalizationService.translate('error')}: $e\x1b[0m\r\n');
      setState(() {
        _loading = false;
        _connected = false;
        _statusMsg = LocalizationService.translate('error');
      });
    }
  }

  void _disconnect() {
    if (widget.host.id != null) {
      SshSessionManager.removeSession(widget.host.id!);
    } else {
      _session?.close();
      _client?.close();
    }
    Navigator.pop(context);
  }

  void _sendInput(String text) {
    if (_session != null && text.isNotEmpty) {
      _session!.write(utf8.encode(text));
    }
  }

  void _toggleArrows() {
    setState(() => _showArrows = !_showArrows);
    if (!_showArrows) {
      _sendInput('\x1b'); // Escape key when hiding arrows
    }
  }

  void _sendArrow(String sequence) {
    _sendInput(sequence);
    setState(() => _showArrows = false);
  }

  Future<void> _copySelection() async {
    final selection = terminalController.selection;
    if (selection == null) return;
    final text = terminal.buffer.getText(selection);
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      terminal.paste(data.text!);
    }
  }

  void _handleTerminalTap(TapUpDetails details, CellOffset cellOffset) {
    if (terminalController.selection != null) return;
    
    int lineIndex = terminal.buffer.scrollBack + cellOffset.y;
    if (lineIndex < 0 || lineIndex >= terminal.buffer.height) return;
    
    int start = lineIndex - 3 < 0 ? 0 : lineIndex - 3;
    int end = lineIndex + 3 >= terminal.buffer.height ? terminal.buffer.height - 1 : lineIndex + 3;
    
    String block = "";
    for (int i = start; i <= end; i++) {
      String text = terminal.buffer.lines[i].getText();
      block += text.trimRight();
    }
    
    final matches = _urlRegex.allMatches(block);
    if (matches.isNotEmpty) {
      final url = matches.first.group(0)!;
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  static final _urlRegex = RegExp(r'https?://[^\s]+');

  Future<void> _toggleVoice() async {
    _inputFocus.unfocus(); // Hide keyboard during dictation
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      final text = _inputController.text.trim();
      if (text.isNotEmpty) {
        _sendInput('$text\r');
      } else {
        _sendInput('\r');
      }
      _inputController.clear();
      _voiceBuffer = '';
      return;
    }
    await _startVoice();
  }

  Future<void> _startVoice() async {
    if (!_speechAvailable) return;

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        debugPrint("Microphone permission not granted");
        return;
      }
    }

    if (_speech.isListening) {
      await _speech.cancel();
    }

    _voiceBuffer = _inputController.text.trim();
    setState(() => _isListening = true);

    final languageCode =
        LocalizationService.language.value == 'ru' ? 'ru-RU' : 'en-US';

    try {
      await _speech.listen(
        onResult: (result) {
          final recognized = result.recognizedWords.trim();
          if (result.finalResult && recognized.isNotEmpty) {
            setState(() {
              _voiceBuffer += (_voiceBuffer.isEmpty ? '' : ' ') + recognized;
              _inputController.text = _voiceBuffer;
            });
          }
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: languageCode,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(minutes: 5),
          partialResults: false,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      debugPrint("Speech exception: $e");
      if (mounted) setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    if (widget.host.id == null) {
      _session?.close();
      _client?.close();
    }
    _speech.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.host.label, style: const TextStyle(fontSize: 15)),
            Text(
              '${widget.host.username}@${widget.host.host}',
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          // Status indicator
          GestureDetector(
            onDoubleTap: () {
              if (!_connected) {
                _connect();
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _connected
                    ? AppTheme.accentGreen.withValues(alpha: 0.15)
                    : AppTheme.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _connected
                      ? AppTheme.accentGreen.withValues(alpha: 0.4)
                      : AppTheme.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _connected ||
                            _statusMsg.isEmpty ||
                            _statusMsg ==
                                LocalizationService.translate('connecting')
                        ? _statusMsg
                        : '$_statusMsg (двойной тап)',
                    style: TextStyle(
                      fontSize: 11,
                      color: _connected ? AppTheme.accentGreen : AppTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder, color: AppTheme.accentPurple),
            tooltip: 'SFTP',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SftpScreen(host: widget.host)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: AppTheme.danger),
            tooltip: LocalizationService.translate('disconnected'),
            onPressed: _disconnect,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppTheme.bg,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.computer, color: AppTheme.accent, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    widget.host.label,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
                  ),
                  Text(
                    '${widget.host.username}@${widget.host.host}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: AppTheme.accentPurple),
              title: const Text('SFTP File Manager', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context); // close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SftpScreen(host: widget.host)),
                );
              },
            ),
          ],
        ),
      ),
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // Terminal scroll area — top 70% of screen, separate from input
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.zero,
                padding: EdgeInsets.zero,
              ),
              child: TerminalView(
                terminal,
              readOnly: false,
              controller: terminalController,
              theme: TerminalTheme(
                cursor: AppTheme.accent,
                selection: AppTheme.accent.withValues(alpha: 0.3),
                foreground: AppTheme.textPrimary,
                background: const Color(0xFF080B10),
                black: Colors.black,
                white: AppTheme.textPrimary,
                red: AppTheme.danger,
                green: AppTheme.accentGreen,
                yellow: const Color(0xFFFFD60A),
                blue: AppTheme.accent,
                magenta: AppTheme.accentPurple,
                cyan: AppTheme.accent,
                brightBlack: AppTheme.textSecondary,
                brightWhite: Colors.white,
                brightRed: AppTheme.danger,
                brightGreen: AppTheme.accentGreen,
                brightYellow: const Color(0xFFFFD60A),
                brightBlue: AppTheme.accent,
                brightMagenta: AppTheme.accentPurple,
                brightCyan: AppTheme.accent,
                searchHitBackground: AppTheme.accent.withValues(alpha: 0.4),
                searchHitBackgroundCurrent:
                    AppTheme.accent.withValues(alpha: 0.7),
                searchHitForeground: const Color(0xFF080B10),
              ),
              padding: const EdgeInsets.all(8),
              textStyle: const TerminalStyle(fontSize: 13),
              onTapUp: _handleTerminalTap,
            ),
            ),
          ),



          // Input bar with voice
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showArrows) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Escape
                        _ArrowBtn(
                          icon: null,
                          label: 'Esc',
                          onTap: () {
                            _sendInput('\x1b');
                            setState(() => _showArrows = false);
                          },
                        ),
                        const SizedBox(width: 8),
                        _ArrowBtn(
                          icon: Icons.arrow_upward,
                          onTap: () => _sendArrow('\x1b[A'),
                        ),
                        const SizedBox(width: 8),
                        _ArrowBtn(
                          icon: Icons.arrow_downward,
                          onTap: () => _sendArrow('\x1b[B'),
                        ),
                        const SizedBox(width: 8),
                        _ArrowBtn(
                          icon: Icons.arrow_left,
                          onTap: () => _sendArrow('\x1b[D'),
                        ),
                        const SizedBox(width: 8),
                        _ArrowBtn(
                          icon: Icons.arrow_right,
                          onTap: () => _sendArrow('\x1b[C'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  // Copy
                  _IconBtn(
                    icon: Icons.copy_outlined,
                    color: AppTheme.textSecondary,
                    tooltip: LocalizationService.translate('copy'),
                    onTap: _copySelection,
                  ),
                  const SizedBox(width: 6),
                  // Paste
                  _IconBtn(
                    icon: Icons.paste_outlined,
                    color: AppTheme.textSecondary,
                    tooltip: LocalizationService.translate('paste'),
                    onTap: _pasteFromClipboard,
                  ),
                  const SizedBox(width: 6),
                  // Ctrl+C
                  _IconBtn(
                    icon: Icons.cancel_outlined,
                    color: AppTheme.danger,
                    tooltip: 'Ctrl+C',
                    onTap: () => _sendInput('\x03'),
                  ),
                  const SizedBox(width: 6),
                  // Tab
                  _IconBtn(
                    icon: Icons.keyboard_tab,
                    color: AppTheme.textSecondary,
                    tooltip: 'Tab',
                    onTap: () => _sendInput('\t'),
                  ),
                  const SizedBox(width: 8),
                  // Escape / Arrows toggle
                  _IconBtn(
                    icon: _showArrows ? Icons.close : Icons.keyboard,
                    color: AppTheme.textSecondary,
                    tooltip: _showArrows ? 'Hide arrows' : 'Escape',
                    onTap: _toggleArrows,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontFamily: 'JetBrains Mono',
                      ),
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? LocalizationService.translate('speak_hint')
                            : LocalizationService.translate('command_hint'),
                        hintStyle: TextStyle(
                          color: _isListening
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        _sendInput('$v\n');
                        _inputController.clear();
                      },
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Voice button — always visible; system dialog fires on first tap
                  _IconBtn(
                    icon: _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening
                        ? AppTheme.accent
                        : (_speechAvailable
                            ? AppTheme.textSecondary
                            : AppTheme.textSecondary.withValues(alpha: 0.4)),
                    tooltip: 'Voice',
                    onTap: _toggleVoice,
                  ),
                  const SizedBox(width: 6),
                  // Send button
                  _IconBtn(
                    icon: Icons.send,
                    color: AppTheme.accent,
                    tooltip: LocalizationService.translate('send'),
                    onTap: () {
                      final text = _inputController.text;
                      if (text.isNotEmpty) {
                        _sendInput('$text\r');
                      } else {
                        _sendInput('\r');
                      }
                      _inputController.clear();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  const _ArrowBtn({this.icon, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, color: AppTheme.accent, size: 20)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
