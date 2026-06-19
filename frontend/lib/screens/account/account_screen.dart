import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kairos/core/constants.dart';
import 'package:kairos/providers/schedule_provider.dart';
import 'package:kairos/services/api_service.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _loading = false;
  Map<String, dynamic>? _info;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/calendar',
    ],
    serverClientId: AppConstants.googleServerClientId,
    forceCodeForRefreshToken: true,
  );

  Future<String> _requestServerAuthCode() async {
    await _googleSignIn.signOut();
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('Google sign-in was cancelled');
    }

    final code = account.serverAuthCode?.trim();
    if (code != null && code.isNotEmpty) {
      return code;
    }

    throw StateError(
      'Google did not return a server auth code. Create an Android OAuth client in the same Google Cloud project as your Web client (package: com.example.kairos, SHA-1: 0E:71:A3:18:04:8A:5C:68:4A:A1:41:18:A7:9E:E9:93:C4:24:D6:AD).',
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    try {
      final data = await api.getGoogleAccount();
      if (!mounted) return;
      setState(() => _info = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load account: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    try {
      final serverAuthCode = await _requestServerAuthCode();

      await api.connectGoogle(serverAuthCode: serverAuthCode);
      final imported = await api.syncGoogleCalendar();
      await ref.read(scheduleProvider.notifier).refreshSchedule();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected successfully${imported > 0 ? ' — imported $imported calendar event(s)' : ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        DioException(:final response, :final message) =>
          response?.data is Map ? (response!.data['detail']?.toString() ?? message) : message,
        _ => e.toString().replaceFirst('StateError: ', ''),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to connect Google: $message')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncCalendar() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    try {
      final imported = await api.syncGoogleCalendar();
      await ref.read(scheduleProvider.notifier).refreshSchedule();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(imported > 0 ? 'Imported $imported calendar event(s)' : 'No new calendar events to import')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to sync calendar: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    try {
      final ok = await api.disconnectGoogle();
      await _googleSignIn.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Disconnected' : 'Nothing to disconnect')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final linked = _info != null && (_info!['linked'] == true);
    final info = _info?['info'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text('Google Calendar', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(linked ? 'Connected' : 'Not connected'),
            const SizedBox(height: 12),
            if (linked && info != null) ...[
              Text('Scopes: ${info['scopes'] ?? []}'),
              const SizedBox(height: 6),
              Text('Expiry: ${info['expiry'] ?? 'unknown'}'),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                ElevatedButton(
                  onPressed: _connect,
                  child: const Text('Connect'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: linked ? _disconnect : null,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            if (linked) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _syncCalendar,
                child: const Text('Sync calendar events'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
