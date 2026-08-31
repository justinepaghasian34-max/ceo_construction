import 'package:flutter/material.dart';

/// Generic centered floating dialog utility for all modules
Future<T?> showCenteredDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext dialogContext) builder,
  double maxWidth = 820,
  double maxHeightFactor = 0.78,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color? barrierColor,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
    builder: (dialogContext) {
      final size = MediaQuery.of(dialogContext).size;
      final width =
          size.width < maxWidth + 48 ? size.width * 0.94 : maxWidth;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 8,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: size.height * maxHeightFactor,
          ),
          child: builder(dialogContext),
        ),
      );
    },
  );
}

/// Confirmation dialog with consistent styling
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  Color? confirmColor,
  bool isDangerous = false,
}) {
  return showCenteredDialog<bool>(
    context: context,
    maxWidth: 440,
    builder: (dialogContext) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(cancelText),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor ??
                          (isDangerous ? Colors.red : Colors.blue),
                    ),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(
                      confirmText,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Information dialog with consistent styling
Future<void> showInfoDialog({
  required BuildContext context,
  required String title,
  required String message,
  String buttonText = 'OK',
}) {
  return showCenteredDialog<void>(
    context: context,
    maxWidth: 440,
    builder: (dialogContext) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      );
    },
  );
}
