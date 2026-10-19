import 'package:flutter/material.dart';

/// Asks for a PDF's password. Returns null if the user cancels.
Future<String?> showPdfPasswordDialog(
  BuildContext context, {
  required String fileName,
  bool retry = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(fileName: fileName, retry: retry),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.fileName, required this.retry});
  final String fileName;
  final bool retry;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Password needed'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.retry
                  ? 'That password did not work for "${widget.fileName}". Try again.'
                  : '"${widget.fileName}" is protected. Enter its password to open it.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open')),
      ],
    );
  }
}
