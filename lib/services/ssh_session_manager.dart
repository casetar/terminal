import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'database_service.dart';

class SshSession {
  final SSHClient client;
  final SSHSession session;
  final Terminal terminal;
  final TerminalController terminalController;
  final SshHost host;
  bool connected;
  String statusMsg;

  SshSession({
    required this.client,
    required this.session,
    required this.terminal,
    required this.terminalController,
    required this.host,
    required this.connected,
    required this.statusMsg,
  });
}

class SshSessionManager {
  static final Map<int, SshSession> _sessions = {};

  static SshSession? getSession(int hostId) => _sessions[hostId];

  static void addSession(int hostId, SshSession session) {
    _sessions[hostId] = session;
  }

  static void removeSession(int hostId) {
    final session = _sessions.remove(hostId);
    if (session != null) {
      try {
        session.session.close();
      } catch (_) {}
      try {
        session.client.close();
      } catch (_) {}
    }
  }

  static void removeSessionOnly(int hostId) {
    _sessions.remove(hostId);
  }

  static List<SshSession> get activeSessions => _sessions.values.toList();
}
