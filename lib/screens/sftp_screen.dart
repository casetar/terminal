import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/key_storage_service.dart';
import '../services/ssh_session_manager.dart';
import 'text_editor_screen.dart';

class SftpScreen extends StatefulWidget {
  final SshHost host;

  const SftpScreen({super.key, required this.host});

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  SSHClient? _client;
  SftpClient? _sftp;
  List<SftpName> _items = [];
  bool _loading = true;
  String _currentPath = '.';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initSftp();
  }

  Future<void> _initSftp() async {
    try {
      final existing = widget.host.id != null
          ? SshSessionManager.getSession(widget.host.id!)
          : null;
          
      if (existing != null && !existing.client.isClosed) {
        _client = existing.client;
      } else {
        if (widget.host.authType == 'key' && widget.host.keyId != null) {
          final pem = await KeyStorageService.getKeyPem(widget.host.keyId!);
          final pass = await KeyStorageService.getKeyPassphrase(widget.host.keyId!);
          _client = SSHClient(
            await SSHSocket.connect(widget.host.host, widget.host.port),
            username: widget.host.username,
            identities: [
              ...SSHKeyPair.fromPem(pem!, pass),
            ],
          );
        } else {
          final password = await KeyStorageService.getPassword('${widget.host.id}');
          _client = SSHClient(
            await SSHSocket.connect(widget.host.host, widget.host.port),
            username: widget.host.username,
            onPasswordRequest: () => password ?? '',
            onUserInfoRequest: (request) =>
                request.prompts.map((p) => password ?? '').toList(),
          );
        }
      }

      _sftp = await _client!.sftp();
      await _loadDirectory(_currentPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await _sftp!.listdir(path);
      items.sort((a, b) {
        final aIsDir = a.attr.isDirectory;
        final bIsDir = b.attr.isDirectory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.filename.compareTo(b.filename);
      });
      
      if (mounted) {
        setState(() {
          _currentPath = path;
          _items = items.where((item) => item.filename != '.').toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        setState(() => _loading = true);
        File localFile = File(result.files.single.path!);
        String filename = result.files.single.name;
        
        String remotePath;
        if (_currentPath == '.' || _currentPath.endsWith('/')) {
          remotePath = '$_currentPath$filename';
        } else {
          remotePath = '$_currentPath/$filename';
        }
        
        final remoteFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
        await remoteFile.write(localFile.openRead().cast());
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded $filename'),
              backgroundColor: AppTheme.accentGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Upload error: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _downloadFile(SftpName item) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        setState(() => _loading = true);
        
        String remotePath;
        if (_currentPath == '.' || _currentPath.endsWith('/')) {
          remotePath = '$_currentPath${item.filename}';
        } else {
          remotePath = '$_currentPath/${item.filename}';
        }
        
        final remoteFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
        File localFile = File(p.join(selectedDirectory, item.filename));
        
        final sink = localFile.openWrite();
        await for (var chunk in remoteFile.read()) {
          sink.add(chunk);
        }
        await sink.close();
        
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded ${item.filename}'),
              backgroundColor: AppTheme.accentGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Download error: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  void _onItemTap(SftpName item) {
    if (item.attr.isDirectory) {
      if (item.filename == '..') {
        if (_currentPath == '.' || _currentPath == '/') {
          _loadDirectory('/');
        } else {
          final parts = _currentPath.split('/');
          parts.removeLast();
          if (parts.isEmpty || (parts.length == 1 && parts[0] == '')) {
            _loadDirectory('/');
          } else {
            _loadDirectory(parts.join('/'));
          }
        }
      } else {
        String newPath;
        if (_currentPath == '.') {
          newPath = item.filename;
        } else {
          newPath = _currentPath.endsWith('/') 
              ? '$_currentPath${item.filename}' 
              : '$_currentPath/${item.filename}';
        }
        _loadDirectory(newPath);
      }
    } else {
      final ext = p.extension(item.filename).toLowerCase();
      final textExtensions = ['.txt', '.sh', '.json', '.yaml', '.md'];
      
      if (textExtensions.contains(ext)) {
        _openTextFile(item);
      } else {
        _openOtherFile(item);
      }
    }
  }

  Future<void> _openTextFile(SftpName item) async {
    setState(() => _loading = true);
    try {
      String remotePath;
      if (_currentPath == '.' || _currentPath.endsWith('/')) {
        remotePath = '$_currentPath${item.filename}';
      } else {
        remotePath = '$_currentPath/${item.filename}';
      }
      
      final remoteFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
      final bytes = <int>[];
      await for (var chunk in remoteFile.read()) {
        bytes.addAll(chunk);
      }
      final content = utf8.decode(bytes);
      
      if (mounted) {
        setState(() => _loading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TextEditorScreen(
              title: item.filename,
              initialContent: content,
              onSave: (newContent) async {
                final saveFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
                await saveFile.write(Stream.value(Uint8List.fromList(utf8.encode(newContent))));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error reading file: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openOtherFile(SftpName item) async {
    setState(() => _loading = true);
    try {
      String remotePath;
      if (_currentPath == '.' || _currentPath.endsWith('/')) {
        remotePath = '$_currentPath${item.filename}';
      } else {
        remotePath = '$_currentPath/${item.filename}';
      }
      
      final remoteFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
      
      final extDir = await getExternalStorageDirectory();
      final tempDir = extDir ?? await getApplicationDocumentsDirectory();
      final tempFile = File(p.join(tempDir.path, item.filename));
      
      final sink = tempFile.openWrite();
      await for (var chunk in remoteFile.read()) {
        sink.add(chunk);
      }
      await sink.close();
      
      if (mounted) {
        setState(() => _loading = false);
        await OpenFilex.open(tempFile.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error opening file: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final existing = widget.host.id != null
          ? SshSessionManager.getSession(widget.host.id!)
          : null;
    if (existing == null || existing.client != _client) {
      _client?.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          'SFTP: $_currentPath', 
          style: const TextStyle(fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file, color: AppTheme.accentGreen),
            tooltip: 'Upload File',
            onPressed: _uploadFile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: AppTheme.danger),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadDirectory(_currentPath),
                  color: AppTheme.accent,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isDir = item.attr.isDirectory;
                      return ListTile(
                        leading: Icon(
                          isDir ? Icons.folder : Icons.insert_drive_file,
                          color: isDir ? AppTheme.accent : AppTheme.textSecondary,
                        ),
                        title: Text(
                          item.filename,
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        subtitle: !isDir && item.attr.size != null
                            ? Text(
                                '${item.attr.size} bytes',
                                style: const TextStyle(color: AppTheme.textSecondary),
                              )
                            : null,
                        trailing: !isDir 
                            ? IconButton(
                                icon: const Icon(Icons.download, color: AppTheme.accent),
                                onPressed: () => _downloadFile(item),
                              )
                            : null,
                        onTap: () => _onItemTap(item),
                      );
                    },
                  ),
                ),
    );
  }
}
