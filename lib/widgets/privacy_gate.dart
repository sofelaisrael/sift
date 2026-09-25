import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Show the one-time privacy consent dialog before cloud chat.
/// Returns true when the user has already consented or grants consent now.
/// A declined consent is not stored, so the prompt can appear again.
Future<bool> showPrivacyConsentIfNeeded(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('localOnly') ?? true) return true;
  if (prefs.getBool('privacy_consent') ?? false) return true;

  if (!context.mounted) return false;

  final granted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('One thing before we start'),
      content: const Text(
        'Screenshot images and OCR text stay on this device. Google Play '
        'services may download the small image-labeling model on first use. '
        'Cloud chat sends screenshot-derived text and context to the provider '
        'you choose. Optional source lookup can also query the web.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  if (granted == true) {
    await prefs.setBool('privacy_consent', true);
  }
  return granted ?? false;
}
