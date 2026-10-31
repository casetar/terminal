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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _loading = true);
        for (final file in result.files) {
          if (file.path == null) continue;
          final localFile = File(file.path!);
          final filename = file.name;

          String remotePath;
          if (_currentPath == '.') {
            remotePath = filename;
          } else if (_currentPath.endsWith('/')) {
            remotePath = '$_currentPath$filename';
          } else {
            remotePath = '$_currentPath/$filename';
          }

          final remoteFile = await _sftp!.open(
            remotePath,
            mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
          );
          await remoteFile.write(localFile.openRead().cast());
          await remoteFile.close();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded ${result.files.length} file(s)'),
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
    setState(() => _loading = true);
    try {
      String remotePath;
      if (_currentPath == '.') {
        remotePath = item.filename;
      } else if (_currentPath.endsWith('/')) {
        remotePath = '$_currentPath${item.filename}';
      } else {
        remotePath = '$_currentPath/${item.filename}';
      }

      final remoteFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);

      // Save to Downloads folder
      final downloadsDir = await getDownloadsDirectory();
      final saveDir = downloadsDir?.path ?? (await getApplicationDocumentsDirectory()).path;
      if (saveDir.isEmpty) {
        throw Exception('Save directory not available');
      }

      final localFile = File('$saveDir/${item.filename}');
      final sink = localFile.openWrite();
      await for (var chunk in remoteFile.read()) {
        sink.add(chunk);
      }
      await sink.close();
      await remoteFile.close();

      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to $saveDir/${item.filename}'),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        try {
          await OpenFilex.open('$saveDir/${item.filename}');
        } catch (_) {}
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

  Future<void> _zipAndDownloadFolder(SftpName item) async {
    try {
      setState(() => _loading = true);
      final folderName = item.filename;
      String remotePath;
      if (_currentPath == '.') {
        remotePath = folderName;
      } else if (_currentPath.endsWith('/')) {
        remotePath = '$_currentPath$folderName';
      } else {
        remotePath = '$_currentPath/$folderName';
      }
      final zipRemotePath = '/tmp/${folderName.replaceAll('/', '_')}.zip';

      // Create zip on server via SSH
      final result = await _client!.runWithResult(
        'zip -r "$zipRemotePath" "$remotePath"',
        stdout: false,
        stderr: true,
      );
      if (result.exitCode != 0) {
        throw Exception('zip failed: ${utf8.decode(result.stderr)}');
      }

      // Download the zip via SFTP
      final String? selectedDirectory =
          await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) {
        // Clean up temp zip on server
        try {
          await _sftp!.remove(zipRemotePath);
        } catch (_) {}
        if (mounted) setState(() => _loading = false);
        return;
      }

      final localFile = File('$selectedDirectory/${folderName}.zip');
      final remoteFile = await _sftp!.open(zipRemotePath, mode: SftpFileOpenMode.read);
      final sink = localFile.openWrite();
      await for (var chunk in remoteFile.read()) {
        sink.add(chunk);
      }
      await sink.close();
      await remoteFile.close();

      // Clean up temp zip on server
      try {
        await _sftp!.remove(zipRemotePath);
      } catch (_) {}

      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zipped and downloaded ${folderName}.zip'),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Zip/download error: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  bool _isTextFile(String filename) {
    final ext = p.extension(filename).toLowerCase();
    final textExtensions = ['.txt', '.sh', '.json', '.yaml', '.yml', '.md', '.csv', '.log', '.conf', '.cfg', '.ini', '.py', '.js', '.html', '.css', '.xml', '.dart', '.swift', '.kt', '.java', '.c', '.cpp', '.h', '.hpp', '.rb', '.go', '.rs'];
    return textExtensions.contains(ext);
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
      if (_currentPath == '.') {
        remotePath = item.filename;
      } else if (_currentPath.endsWith('/')) {
        remotePath = '$_currentPath${item.filename}';
      } else {
        remotePath = '$_currentPath/${item.filename}';
      }
      
      final remoteFile = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
      final bytes = <int>[];
      await for (var chunk in remoteFile.read()) {
        bytes.addAll(chunk);
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      
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
      if (_currentPath == '.') {
        remotePath = item.filename;
      } else if (_currentPath.endsWith('/')) {
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
                        trailing: isDir
                            ? IconButton(
                                icon: const Icon(
                                  Icons.archive,
                                  color: AppTheme.accentPurple,
                                ),
                                tooltip: 'Zip & Download',
                                onPressed: () => _zipAndDownloadFolder(item),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Edit button for text files
                                  if (_isTextFile(item.filename))
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: AppTheme.accent,
                                      ),
                                      tooltip: 'Edit',
                                      onPressed: () => _openTextFile(item),
                                    ),
                                  if (_isTextFile(item.filename))
                                    const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.download,
                                      color: AppTheme.accent,
                                    ),
                                    onPressed: () => _downloadFile(item),
                                  ),
                                ],
                              ),
                        onTap: () => _onItemTap(item),
                      );
                    },
                  ),
                ),
    );
  }
}
