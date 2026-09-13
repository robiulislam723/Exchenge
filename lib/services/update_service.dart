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
  static const String _repo = 'exchenge.narailexpress.net';

  static Future<void> check(BuildContext context, {bool silent = true}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);

      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'exchenge-mobile'},
      );
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] ?? '').toString();
      final latest = _parseVersion(tag.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (latest <= current) return;

      // Find the APK asset.
      final assets = (data['assets'] as List?) ?? [];
      final apk = assets.firstWhere(
        (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
        orElse: () => null,
      );
      if (apk == null) return;

      final url = apk['browser_download_url'].toString();
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
    } catch (_) {
      // silent on failures
    }
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
      final req = http.Request('GET', Uri.parse(url));
      final streamed = await req.send();

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
      await OpenFilex.open(file.path);
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
