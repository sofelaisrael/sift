import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Show the one-time privacy consent dialog before any AI upload.
/// Returns true when the user has already consented or grants consent now.
/// A declined consent is not stored, so the prompt can appear again.
Future<bool> showPrivacyConsentIfNeeded(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('localOnly') ?? false) return true;
  if (prefs.getBool('privacy_consent') ?? false) return true;

  if (!context.mounted) return false;

  final granted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('One thing before we start'),
      content: const Text(
        'To understand a screenshot, Sift sends the image to the AI provider you choose (Google Gemini, NVIDIA, or Groq). Optional link lookups query DuckDuckGo and YouTube. No analysis or lookups ever happen without your permission, and you can turn on Local-only mode in Settings to keep everything on this device. On-device labeling may download a small labeling model from Google Play services (no images leave the device).',
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
