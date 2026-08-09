import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Show the one-time privacy consent dialog before any AI upload.
/// Returns true when the user has already consented or grants consent now.
/// A declined consent is not stored, so the prompt can appear again.
Future<bool> showPrivacyConsentIfNeeded(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('localOnly') ?? false) return true;
  if (prefs.getBool('privacy_consent') ?? false) return true;

  final granted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.r2xl),
      ),
      title: const Text('One thing before we start'),
      content: const Text(
        'To understand a screenshot, Sift sends the image to the AI provider you choose (Google Gemini, NVIDIA, or Groq). Optional link lookups query DuckDuckGo and YouTube. No analysis or lookups ever happen without your permission, and you can turn on Local-only mode in Settings to keep everything on this device.',
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
