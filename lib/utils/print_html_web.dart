import 'dart:async';
import 'dart:js_util' as js_util;

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void printHtmlDocument(String title, String htmlBody) {
  final safeTitle = title
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final htmlString = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$safeTitle</title>
  <style>
    body { font-family: "Times New Roman", Georgia, serif; color: #111; padding: 28px; max-width: 800px; margin: 0 auto; }
    .letterhead { text-align: center; border-bottom: 3px solid #0B2A4A; padding-bottom: 12px; margin-bottom: 18px; }
    .letterhead h1 { margin: 0; font-size: 18px; letter-spacing: 0.4px; }
    .letterhead p { margin: 4px 0 0; font-size: 12px; color: #333; }
    h2 { font-size: 15px; margin: 0 0 12px; text-align: center; text-decoration: underline; }
    table { width: 100%; border-collapse: collapse; margin: 10px 0 16px; }
    th, td { border: 1px solid #222; padding: 6px 8px; font-size: 12px; vertical-align: top; text-align: left; }
    th { background: #f3f4f6; width: 32%; }
    .section { font-size: 13px; font-weight: bold; margin: 16px 0 6px; }
    .sign { display: flex; justify-content: space-between; margin-top: 48px; gap: 24px; }
    .sign div { flex: 1; text-align: center; font-size: 12px; }
    .line { border-top: 1px solid #111; margin: 40px 16px 6px; }
    @media print { .no-print { display: none; } }
  </style>
</head>
<body>
$htmlBody
<script>window.addEventListener('load', function() { setTimeout(function() { window.print(); }, 250); });</script>
</body>
</html>
''';

  final blob = html.Blob([htmlString], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final iframe = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  html.document.body?.append(iframe);
  iframe.onLoad.listen((_) {
    final win = iframe.contentWindow;
    if (win != null) {
      js_util.callMethod(win, 'print', const []);
    }
    Future<void>.delayed(const Duration(seconds: 2), () {
      iframe.remove();
      html.Url.revokeObjectUrl(url);
    });
  });
}
