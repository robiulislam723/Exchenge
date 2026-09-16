import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks GitHub Releases for a newer APK and installs it in-app.
class UpdateService {
  static const String _owner = 'robiulislam723';
  static const String _repo = 'Exchenge';
  static const String _apkName = 'app-release.apk';

  static Future<void> check(BuildContext context, {bool silent = true}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);

      final tag = await _latestTag();
      if (tag == null) {
        if (!silent && context.mounted) {
          _toast(context, 'Update check failed: could not reach GitHub');
        }
        return;
      }

      final latest = _parseVersion(tag.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (latest <= current) {
        if (!silent && context.mounted) {
          _toast(context, 'You are on the latest version (${info.version})');
        }
        return;
      }

      final url = 'https://github.com/$_owner/$_repo/releases/download/$tag/$_apkName';
      if (!context.mounted) return;

      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: Text('A new version ($tag) is available. Update now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      );
      if (go != true) return;

      await _downloadAndInstall(context, url, tag);
    } catch (e) {
      if (!silent && context.mounted) _toast(context, 'Update check failed: $e');
    }
  }

  /// Latest release tag. Uses the GitHub API first and falls back to the plain
  /// web redirect (github.com/<owner>/<repo>/releases/latest), which is not
  /// rate limited and works when the API is blocked.
  static Future<String?> _latestTag() async {
    try {
      final res = await http
          .get(
            Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'exchenge-mobile'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tag = (data['tag_name'] ?? '').toString().trim();
        if (tag.isNotEmpty) return tag;
      }
    } catch (_) {}

    try {
      final req = http.Request('GET', Uri.parse('https://github.com/$_owner/$_repo/releases/latest'));
      req.followRedirects = false;
      final res = await req.send().timeout(const Duration(seconds: 15));
      final loc = res.headers['location'] ?? '';
      final m = RegExp(r'/releases/tag/(.+)$').firstMatch(loc);
      if (m != null) {
        final tag = Uri.decodeComponent(m.group(1)!).trim();
        if (tag.isNotEmpty) return tag;
      }
    } catch (_) {}

    return null;
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> _downloadAndInstall(BuildContext context, String url, String tag) async {
    final progress = ValueNotifier<double>(0);
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Downloading update...'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v <= 0 ? null : v),
                const SizedBox(height: 10),
                Text('${(v * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/exchenge-$tag.apk');
      if (await file.exists()) await file.delete();

      final req = http.Request('GET', Uri.parse(url));
      final streamed = await req.send();
      if (streamed.statusCode != 200) {
        throw Exception('download failed (${streamed.statusCode})');
      }

      final total = streamed.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      final opened = await OpenFilex.open(file.path);
      if (opened.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Install blocked (${opened.message}). Allow "Install unknown apps" for Exchange and try again.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  static int _parseVersion(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 10000 + parts[1] * 100 + parts[2];
  }
}
