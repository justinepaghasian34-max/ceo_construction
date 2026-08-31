import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/firebase_service.dart';

/// Pulls every usable photo source from a progress-report Firestore document.
class ProgressReportImages {
  ProgressReportImages._();

  static List<String> extract(Map<String, dynamic> data) {
    final out = <String>[];

    void add(dynamic value) {
      if (value == null) return;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty && !out.contains(trimmed)) {
          out.add(trimmed);
        }
        return;
      }
      if (value is Map) {
        add(value['imageUrl'] ??
            value['image_url'] ??
            value['downloadUrl'] ??
            value['url'] ??
            value['source'] ??
            value['storagePath'] ??
            value['storage_path']);
        return;
      }
      if (value is Iterable) {
        for (final item in value) {
          add(item);
        }
      }
    }

    add(data['imageUrls']);
    add(data['images']);
    add(data['image_urls']);
    add(data['photos']);
    add(data['imageUrl']);
    add(data['image_url']);
    add(data['storagePath']);
    add(data['storage_path']);
    add(data['storagePaths']);
    add(data['perImageResults']);
    add(data['blueprintUrls']);

    final analysis = data['analysis'];
    if (analysis is Map) {
      add(analysis['imageUrls']);
      add(analysis['imageUrl']);
      add(analysis['perImageResults']);
      add(analysis['photos']);
    }

    return out;
  }
}

/// Loads a Firebase download URL or Storage path. On web, prefers an HTML
/// <img> so Firebase Storage photos render even when CanvasKit hits CORS.
class StorageNetworkImage extends StatelessWidget {
  const StorageNetworkImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.errorIconColor,
    this.semanticLabel,
  });

  final String source;
  final BoxFit fit;
  final Color? errorIconColor;
  final String? semanticLabel;

  String _normalizeHttpUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.contains('firebasestorage.googleapis.com') &&
        u.contains('/o/') &&
        !u.contains('alt=media')) {
      final join = u.contains('?') ? '&' : '?';
      return '$u${join}alt=media';
    }
    return u;
  }

  Future<String> _resolveUrl() async {
    final s = source.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return _normalizeHttpUrl(s);
    }
    try {
      if (s.startsWith('gs://')) {
        final ref = FirebaseService.instance.storage.refFromURL(s);
        return _normalizeHttpUrl(await ref.getDownloadURL());
      }
      final ref = FirebaseService.instance.storage.ref(s);
      return _normalizeHttpUrl(await ref.getDownloadURL());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolveUrl(),
      builder: (context, snap) {
        final url = (snap.data ?? '').trim();
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (url.isEmpty) {
          return Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: errorIconColor,
            ),
          );
        }
        return Image.network(
          url,
          fit: fit,
          semanticLabel: semanticLabel,
          filterQuality: FilterQuality.medium,
          webHtmlElementStrategy: kIsWeb
              ? WebHtmlElementStrategy.prefer
              : WebHtmlElementStrategy.never,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: errorIconColor,
            ),
          ),
        );
      },
    );
  }
}
