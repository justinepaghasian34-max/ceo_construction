import 'package:flutter/material.dart';

/// Gemini-inspired light palette for the BuildIQ assistant canvas.
abstract final class BuildIqGemini {
  static const Color bg = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF3F4F6);
  static const Color composer = Color(0xFFF3F4F6);
  static const Color text = Color(0xFF1F2937);
  static const Color muted = Color(0xFF6B7280);
  static const Color faint = Color(0xFF9CA3AF);
  static const Color accent = Color(0xFF2563EB);
  static const Color navy = Color(0xFF2563EB);
  static const Color glow = Color(0xFF2563EB);
  static const Color line = Color(0xFFE5E7EB);

  static const LinearGradient sparkle = LinearGradient(
    colors: [Color(0xFF4285F4), Color(0xFF9B72CB), Color(0xFFD96570)],
  );
}

class BuildIqSparkle extends StatelessWidget {
  const BuildIqSparkle({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => BuildIqGemini.sparkle.createShader(bounds),
      child: Icon(Icons.auto_awesome, size: size, color: Colors.white),
    );
  }
}

/// Renders assistant replies without showing raw markdown asterisks.
class BuildIqMarkdown extends StatelessWidget {
  const BuildIqMarkdown({
    super.key,
    required this.text,
    this.color = BuildIqGemini.text,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final blocks = _splitBlocks(text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _buildBlock(context, blocks[i]),
        ],
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _MdBlock block) {
    switch (block.kind) {
      case _MdKind.table:
        return _InventoryTable(rows: block.rows, color: color);
      case _MdKind.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in block.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _InlineText(text: item, color: color)),
                  ],
                ),
              ),
          ],
        );
      case _MdKind.paragraph:
        return _InlineText(text: block.lines.join('\n'), color: color);
    }
  }

  static List<_MdBlock> _splitBlocks(String raw) {
    final lines = raw.split('\n');
    final blocks = <_MdBlock>[];
    var buffer = <String>[];
    _MdKind? current;

    void flush() {
      if (current == null || buffer.isEmpty) {
        buffer = [];
        current = null;
        return;
      }
      if (current == _MdKind.table) {
        blocks.add(_MdBlock(kind: _MdKind.table, rows: [
          for (final line in buffer) _parseInventoryRow(line),
        ].whereType<_InvRow>().toList()));
      } else {
        blocks.add(_MdBlock(kind: current!, lines: List.of(buffer)));
      }
      buffer = [];
      current = null;
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final inventory = _parseInventoryRow(line);
      final bullet = _stripBullet(line);
      final kind = inventory != null
          ? _MdKind.table
          : bullet != null
              ? _MdKind.list
              : _MdKind.paragraph;
      if (current != kind) flush();
      current = kind;
      buffer.add(bullet ?? line.trim());
    }
    flush();
    return blocks;
  }

  static String? _stripBullet(String line) {
    final m = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+(.*)$').firstMatch(line);
    return m?.group(1)?.trim();
  }

  static _InvRow? _parseInventoryRow(String line) {
    final cleaned = line
        .trim()
        .replaceFirst(RegExp(r'^\s*[-*•]\s*'), '')
        .replaceAll('**', '');
    final lower = cleaned.toLowerCase();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(cleaned)) return null;
    if (lower.contains('rain') ||
        lower.contains('humidity') ||
        lower.contains('forecast') ||
        cleaned.contains('°')) {
      return null;
    }
    final m = RegExp(
      r'^([A-Za-z][A-Za-z0-9 ./%]{1,40})\s*:\s*([\d.]+)\s*(.*)$',
    ).firstMatch(cleaned);
    if (m == null) return null;
    final name = m.group(1)!.trim();
    final qty = m.group(2)!.trim();
    final unit = m.group(3)!.trim();
    if (name.length < 2 || name.length > 42) return null;
    if (RegExp(r'https?://').hasMatch(name)) return null;
    return _InvRow(name: name, qty: qty, unit: unit);
  }
}

class _InlineText extends StatelessWidget {
  const _InlineText({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans(text, color)),
      style: TextStyle(
        color: color,
        fontSize: 15.5,
        height: 1.55,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  static List<InlineSpan> _spans(String source, Color color) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
    var start = 0;
    for (final m in re.allMatches(source)) {
      if (m.start > start) {
        spans.add(TextSpan(text: source.substring(start, m.start)));
      }
      final bold = m.group(1);
      final code = m.group(2);
      if (bold != null) {
        spans.add(TextSpan(
          text: bold,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      } else if (code != null) {
        spans.add(TextSpan(
          text: code,
          style: TextStyle(
            fontFamily: 'monospace',
            color: color.withValues(alpha: 0.9),
          ),
        ));
      }
      start = m.end;
    }
    if (start < source.length) {
      spans.add(TextSpan(text: source.substring(start)));
    }
    if (spans.isEmpty) return [TextSpan(text: source)];
    return spans;
  }
}

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({required this.rows, required this.color});
  final List<_InvRow> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (rows.length < 2) {
      return Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _InlineText(
                text: '**${r.name}**  ${r.qty} ${r.unit}'.trim(),
                color: color,
              ),
            ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        color: BuildIqGemini.surface,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  border: i == rows.length - 1
                      ? null
                      : const Border(
                          bottom: BorderSide(color: BuildIqGemini.line),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${rows[i].qty} ${rows[i].unit}'.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: BuildIqGemini.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _MdKind { paragraph, list, table }

class _MdBlock {
  const _MdBlock({
    required this.kind,
    this.lines = const [],
    this.rows = const [],
  });
  final _MdKind kind;
  final List<String> lines;
  final List<_InvRow> rows;
}

class _InvRow {
  const _InvRow({required this.name, required this.qty, required this.unit});
  final String name;
  final String qty;
  final String unit;
}

class BuildIqChatTurn extends StatelessWidget {
  const BuildIqChatTurn({super.key, required this.isUser, required this.text});

  final bool isUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    final thinking = text == 'Thinking…';
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 18, left: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: BuildIqGemini.composer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              text,
              softWrap: true,
              style: const TextStyle(
                color: BuildIqGemini.text,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: BuildIqSparkle(size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: thinking
                ? const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Thinking…',
                      style: TextStyle(
                        color: BuildIqGemini.faint,
                        fontSize: 15,
                      ),
                    ),
                  )
                : BuildIqMarkdown(text: text),
          ),
        ],
      ),
    );
  }
}

class BuildIqGreeting extends StatelessWidget {
  const BuildIqGreeting({
    super.key,
    required this.firstName,
    required this.chips,
    required this.onChip,
    this.projectName,
    this.weatherLine,
  });

  final String firstName;
  final List<String> chips;
  final ValueChanged<String> onChip;
  final String? projectName;
  final String? weatherLine;

  @override
  Widget build(BuildContext context) {
    final name = firstName.trim().isEmpty ? '' : ', $firstName';
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.85,
                  colors: [
                    BuildIqGemini.glow.withValues(alpha: 0.08),
                    BuildIqGemini.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BuildIqSparkle(size: 36),
                const SizedBox(height: 18),
                Text(
                  'What can I help with$name?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: BuildIqGemini.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                    letterSpacing: -0.4,
                  ),
                ),
                if ((projectName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    [
                      projectName,
                      if ((weatherLine ?? '').isNotEmpty) weatherLine,
                    ].whereType<String>().join('  ·  '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: BuildIqGemini.faint,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in chips)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onChip(chip),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: BuildIqGemini.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: BuildIqGemini.line),
                            ),
                            child: Text(
                              chip,
                              style: const TextStyle(
                                color: BuildIqGemini.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BuildIqComposer extends StatelessWidget {
  const BuildIqComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.hasText,
    required this.onSend,
    this.hint = 'Ask BuildIQ',
  });

  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final bool hasText;
  final VoidCallback onSend;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        decoration: BoxDecoration(
          color: BuildIqGemini.composer,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: BuildIqGemini.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 10),
              child: Icon(Icons.add, color: BuildIqGemini.muted, size: 22),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                cursorColor: BuildIqGemini.navy,
                style: const TextStyle(
                  color: BuildIqGemini.text,
                  fontSize: 15.5,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: BuildIqGemini.faint,
                    fontSize: 15.5,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                onSubmitted: enabled && hasText ? (_) => onSend() : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 2),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BuildIqGemini.accent,
                        ),
                      ),
                    )
                  : IconButton(
                      onPressed: hasText ? onSend : null,
                      icon: Icon(
                        hasText ? Icons.arrow_upward_rounded : Icons.graphic_eq,
                        color: hasText
                            ? BuildIqGemini.bg
                            : BuildIqGemini.muted,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: hasText
                            ? BuildIqGemini.accent
                            : Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        minimumSize: const Size(40, 40),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class BuildIqHistoryItem {
  const BuildIqHistoryItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.preview,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String preview;
}

class BuildIqHistoryDrawer extends StatelessWidget {
  const BuildIqHistoryDrawer({
    super.key,
    required this.items,
    required this.loading,
    required this.activeId,
    required this.onNewChat,
    required this.onOpen,
  });

  final List<BuildIqHistoryItem> items;
  final bool loading;
  final String? activeId;
  final VoidCallback onNewChat;
  final ValueChanged<BuildIqHistoryItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const BuildIqSparkle(size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Chat history',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: BuildIqGemini.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: BuildIqGemini.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: OutlinedButton.icon(
                onPressed: onNewChat,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('New chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BuildIqGemini.navy,
                  side: const BorderSide(color: BuildIqGemini.line),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const Divider(height: 1, color: BuildIqGemini.line),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: BuildIqGemini.navy,
                        strokeWidth: 2,
                      ),
                    )
                  : items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No previous chats yet.\nAsk BuildIQ something to start.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: BuildIqGemini.muted,
                                height: 1.45,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: BuildIqGemini.line,
                          ),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final selected = item.id == activeId;
                            return ListTile(
                              selected: selected,
                              selectedTileColor:
                                  BuildIqGemini.navy.withValues(alpha: 0.06),
                              leading: Icon(
                                Icons.chat_bubble_outline,
                                size: 20,
                                color: selected
                                    ? BuildIqGemini.navy
                                    : BuildIqGemini.muted,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: BuildIqGemini.text,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  _formatWhen(item.updatedAt),
                                  if (item.preview.isNotEmpty) item.preview,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: BuildIqGemini.faint,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => onOpen(item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${local.month}/${local.day}/${local.year}';
  }
}
