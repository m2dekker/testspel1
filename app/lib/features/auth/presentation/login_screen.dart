import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../data/auth_service.dart';

/// Log in or sign up. In the offline demo it only asks for a captain's name.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BwColors.sea, BwColors.deepSea],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const Icon(
                      Icons.sailing,
                      size: 64,
                      color: BwColors.parchment,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Blackwake Isles',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: BwColors.parchment,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Text(
                      'Build a haven. Rule the trade winds.',
                      style: TextStyle(color: BwColors.parchmentDark),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      color: BwColors.parchment,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: BwColors.wood, width: 3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: switch (auth) {
                          DemoAuthService a => _DemoForm(auth: a),
                          SupabaseAuthService a => _AccountForm(auth: a),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DemoForm extends StatefulWidget {
  const _DemoForm({required this.auth});

  final DemoAuthService auth;

  @override
  State<_DemoForm> createState() => _DemoFormState();
}

class _DemoFormState extends State<_DemoForm> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await widget.auth.startDemo(_name.text);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Offline demo',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: BwColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'No account needed. Your haven is saved in this browser, and keeps '
          'producing while you are away.',
          style: TextStyle(color: BwColors.woodLight),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('captain-name'),
          controller: _name,
          maxLength: 20,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _start(),
          decoration: InputDecoration(
            labelText: 'Captain\'s name',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _start, child: const Text('Set sail')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AccountForm extends StatefulWidget {
  const _AccountForm({required this.auth});

  final SupabaseAuthService auth;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_signUp) {
        if (_username.text.trim().length < 3) {
          throw AuthFailure('Pick a captain\'s name of at least 3 letters.');
        }
        final message = await widget.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          username: _username.text.trim(),
        );
        if (message != null) setState(() => _info = message);
      } else {
        await widget.auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    try {
      await widget.auth.signInWithGoogle();
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Log in')),
              ButtonSegment(value: true, label: Text('Sign up')),
            ],
            selected: {_signUp},
            onSelectionChanged: (s) => setState(() => _signUp = s.first),
          ),
          const SizedBox(height: 16),
          if (_signUp) ...[
            TextField(
              controller: _username,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Captain\'s name'),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: [
              _signUp ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: BwColors.danger)),
          ],
          if (_info != null) ...[
            const SizedBox(height: 10),
            Text(_info!, style: const TextStyle(color: BwColors.ink)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_signUp ? 'Create account' : 'Log in'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _google,
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
        ],
      ),
    );
  }
}
