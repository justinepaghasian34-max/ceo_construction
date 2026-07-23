import 'package:flutter/material.dart';

import 'site_manager_govtrack_screen.dart';

/// Legacy route — forwards to unified GovTrack screen (chat tab).
class AiAssistantChatScreen extends StatelessWidget {
  const AiAssistantChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SiteManagerGovtrackScreen(initialTab: 0, showBottomNav: false);
  }
}
