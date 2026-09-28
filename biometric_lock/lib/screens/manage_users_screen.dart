import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/device_client.dart';

class EnrolledUser {
  final String id;
  final String name;

  EnrolledUser({required this.id, required this.name});
}

class ManageUsersScreen extends StatefulWidget {
  final String sessionToken;

  const ManageUsersScreen({super.key, required this.sessionToken});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

enum _ManageStep { awaitingFingerprint, list, error }

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  _ManageStep _step = _ManageStep.awaitingFingerprint;
  WebSocketChannel? _channel;
  List<EnrolledUser> _users = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _channel = DeviceClient.instance.openSessionWebSocket(widget.sessionToken);

    _channel!.stream.listen(
      (data) {
        if (data is String) {
          _handleMessage(data);
        }
      },
      onError: (err) {
        setState(() {
          _step = _ManageStep.error;
          _errorMessage = 'Connection failure.';
        });
      },
      onDone: () {
        if (_step != _ManageStep.error && mounted) {
          // Closed
        }
      },
    );
  }

  void _handleMessage(String jsonStr) {
    try {
      final msg = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      if (type == 'state') {
        final state = msg['state'] as String?;
        if (state == 'fingerprint_confirmed') {
          setState(() {
            _step = _ManageStep.list;
          });
          // Section 5.3 Step 5: Send select_mode manage
          _channel?.sink
              .add(jsonEncode({'type': 'select_mode', 'mode': 'manage'}));
        } else if (state == 'fingerprint_failed' || state == 'timeout') {
          setState(() {
            _step = _ManageStep.error;
            _errorMessage = 'Owner verification failed.';
          });
        }
      } else if (type == 'user_list') {
        final list = (msg['users'] as List<dynamic>?) ?? [];
        setState(() {
          _users = list
              .map((u) => EnrolledUser(
                  id: u['id'] as String, name: u['name'] as String))
              .toList();
        });
      } else if (type == 'delete_result') {
        final success = msg['success'] as bool? ?? false;
        final id = msg['id'] as String?;
        if (success && id != null) {
          setState(() {
            _users.removeWhere((u) => u.id == id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete user')),
          );
        }
      }
    } catch (e) {
      debugPrint('Unexpected JSON: $jsonStr');
    }
  }

  void _confirmDelete(EnrolledUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${user.name}?'),
        content: const Text(
            'This cannot be undone. Their face profile will be removed from the lock.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              // Section 5.3 Step 8: Send delete_user
              _channel?.sink
                  .add(jsonEncode({'type': 'delete_user', 'id': user.id}));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.sink.add(jsonEncode({'type': 'done'}));
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_step == _ManageStep.awaitingFingerprint) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint, size: 72, color: Colors.lightBlueAccent),
            SizedBox(height: 20),
            Text('Touch sensor to verify owner',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      );
    }

    if (_step == _ManageStep.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: Colors.redAccent),
            const SizedBox(height: 20),
            Text(_errorMessage ?? 'Error occurred',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return Home'),
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No users enrolled',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = _users[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('ID: ${user.id}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(user),
          ),
        );
      },
    );
  }
}
