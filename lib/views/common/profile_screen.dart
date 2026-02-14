import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  _SettingsSection _selectedSection = _SettingsSection.profile;

  Future<void> _changeProfileImage() async {
    final user = AuthService.instance.currentUser;
    final firebaseUser = AuthService.instance.currentFirebaseUser;

    if (user == null || firebaseUser == null) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 60,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();

    if (!AppConstants.allowedImageTypes.contains(ext)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a JPG, JPEG, PNG, or WEBP image.'),
        ),
      );
      return;
    }

    if (bytes.length > AppConstants.maxFileSize) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected image is too large. Please choose a smaller file.'),
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final path = 'users/${firebaseUser.uid}/profile.$ext';
      final url = await FirebaseService.instance.uploadFile(
        path,
        bytes,
        contentType: 'image/$ext',
      );

      await AuthService.instance.updateUserProfile({
        'profileImageUrl': url,
      });

      await AuthService.instance.refreshUserData();

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to upload image. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final firebaseUser = AuthService.instance.currentFirebaseUser;
    final maxWidth = MediaQuery.of(context).size.width >= 1400 ? 1200.0 : 1100.0;
    final isNarrow = MediaQuery.of(context).size.width < 980;

    Widget buildCard({required Widget child}) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      );
    }

    Widget buildProfileAvatar() {
      if (user == null) {
        return const CircleAvatar(radius: 40);
      }

      return Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: _isUploading ? null : _changeProfileImage,
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppTheme.deepBlue.withAlpha(40),
              backgroundImage: (user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
                  ? NetworkImage(user.profileImageUrl!)
                  : null,
              child: (user.profileImageUrl == null || user.profileImageUrl!.isEmpty)
                  ? Text(
                      user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.deepBlue,
                          ),
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(
                _isUploading ? Icons.hourglass_top : Icons.camera_alt,
                size: 18,
                color: AppTheme.deepBlue,
              ),
            ),
          ),
        ],
      );
    }

    Widget buildDetailRow(String label, String value, {Widget? trailing}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
    }

    String sectionLabel(_SettingsSection s) {
      switch (s) {
        case _SettingsSection.workspace:
          return 'Workspace';
        case _SettingsSection.overview:
          return 'Overview';
        case _SettingsSection.members:
          return 'Members';
        case _SettingsSection.label:
          return 'Label';
        case _SettingsSection.projects:
          return 'Projects';
        case _SettingsSection.templates:
          return 'Templates';
        case _SettingsSection.initiatives:
          return 'Initiatives';
        case _SettingsSection.integrations:
          return 'Integrations';
        case _SettingsSection.profile:
          return 'Profile';
        case _SettingsSection.notifications:
          return 'Notifications';
        case _SettingsSection.security:
          return 'Security & Access';
        case _SettingsSection.apiKeys:
          return 'API Keys';
        case _SettingsSection.shortcuts:
          return 'Keyboard shortcuts';
      }
    }

    Widget buildPlaceholderSection(String title, String subtitle) {
      return buildCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSidebarItem({
      required IconData icon,
      required String title,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF3F4F6) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? AppTheme.deepBlue : AppTheme.mediumGray),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final profileContent = user == null
        ? buildCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No profile information available.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildCard(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      buildProfileAvatar(),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.displayName,
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user.email,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.mediumGray,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.deepBlue.withAlpha(18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                user.role,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.deepBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (_isUploading) ...[
                              const SizedBox(height: 12),
                              const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              buildCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Personal details',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 12),
                      buildDetailRow('Full name:', user.displayName),
                      Container(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                      buildDetailRow('Email:', user.email),
                      Container(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                      buildDetailRow('Role:', user.role),
                      if (firebaseUser?.uid != null) ...[
                        Container(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                        buildDetailRow('User ID:', firebaseUser!.uid),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              buildCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Security Settings',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Manage password, login sessions, and account access.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _selectedSection = _SettingsSection.security),
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Security & Access'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () async {
                    await AuthService.instance.signOut();
                    if (!context.mounted) return;
                    context.go(RouteNames.login);
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.errorRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          );

    Widget buildSectionContent(_SettingsSection section) {
      switch (section) {
        case _SettingsSection.profile:
          return profileContent;
        case _SettingsSection.notifications:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildPlaceholderSection(
                'Notifications',
                'View system alerts and project updates.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(RouteNames.notifications),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Notifications Page'),
                ),
              ),
            ],
          );
        case _SettingsSection.security:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildPlaceholderSection(
                'Security & Access',
                'Manage password, login sessions, and account access.',
              ),
            ],
          );
        case _SettingsSection.apiKeys:
          return buildPlaceholderSection(
            'API Keys',
            'Manage API keys and integrations for system access.',
          );
        case _SettingsSection.shortcuts:
          return buildPlaceholderSection(
            'Keyboard shortcuts',
            'Common shortcuts for faster navigation will appear here.',
          );
        case _SettingsSection.workspace:
          return buildPlaceholderSection(
            'Workspace',
            'Workspace settings will appear here.',
          );
        case _SettingsSection.overview:
          return buildPlaceholderSection(
            'Overview',
            'Workspace overview will appear here.',
          );
        case _SettingsSection.members:
          return buildPlaceholderSection(
            'Members',
            'Manage members and permissions here.',
          );
        case _SettingsSection.label:
          return buildPlaceholderSection(
            'Label',
            'Manage labels and categories here.',
          );
        case _SettingsSection.projects:
          return buildPlaceholderSection(
            'Projects',
            'Project preferences will appear here.',
          );
        case _SettingsSection.templates:
          return buildPlaceholderSection(
            'Templates',
            'Manage templates here.',
          );
        case _SettingsSection.initiatives:
          return buildPlaceholderSection(
            'Initiatives',
            'Initiatives configuration will appear here.',
          );
        case _SettingsSection.integrations:
          return buildPlaceholderSection(
            'Integrations',
            'Manage integrations here.',
          );
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 12 : 20,
                vertical: isNarrow ? 12 : 18,
              ),
              child: isNarrow
                  ? ListView(
                      children: [
                        buildCard(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Text(
                                  'My Account',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const Spacer(),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<_SettingsSection>(
                                    value: _selectedSection,
                                    items: _SettingsSection.values
                                        .map(
                                          (s) => DropdownMenuItem<_SettingsSection>(
                                            value: s,
                                            child: Text(sectionLabel(s)),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _selectedSection = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        buildSectionContent(_selectedSection),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: buildCard(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            'Settings',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: AppTheme.mediumGray,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          buildSidebarItem(
                                            icon: Icons.workspaces_outline,
                                            title: 'Workspace',
                                            selected: _selectedSection == _SettingsSection.workspace,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.workspace),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.grid_view_outlined,
                                            title: 'Overview',
                                            selected: _selectedSection == _SettingsSection.overview,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.overview),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.group_outlined,
                                            title: 'Members',
                                            selected: _selectedSection == _SettingsSection.members,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.members),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.label_outline,
                                            title: 'Label',
                                            selected: _selectedSection == _SettingsSection.label,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.label),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.folder_open_outlined,
                                            title: 'Projects',
                                            selected: _selectedSection == _SettingsSection.projects,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.projects),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.description_outlined,
                                            title: 'Templates',
                                            selected: _selectedSection == _SettingsSection.templates,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.templates),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.flag_outlined,
                                            title: 'Initiatives',
                                            selected: _selectedSection == _SettingsSection.initiatives,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.initiatives),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.extension_outlined,
                                            title: 'Integrations',
                                            selected: _selectedSection == _SettingsSection.integrations,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.integrations),
                                          ),
                                          const SizedBox(height: 14),
                                          Container(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                                          const SizedBox(height: 14),
                                          Text(
                                            'My Account',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: AppTheme.mediumGray,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          buildSidebarItem(
                                            icon: Icons.person_outline,
                                            title: 'Profile',
                                            selected: _selectedSection == _SettingsSection.profile,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.profile),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.notifications_none,
                                            title: 'Notifications',
                                            selected: _selectedSection == _SettingsSection.notifications,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.notifications),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.lock_outline,
                                            title: 'Security & Access',
                                            selected: _selectedSection == _SettingsSection.security,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.security),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.vpn_key_outlined,
                                            title: 'API Keys',
                                            selected: _selectedSection == _SettingsSection.apiKeys,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.apiKeys),
                                          ),
                                          buildSidebarItem(
                                            icon: Icons.keyboard_alt_outlined,
                                            title: 'Keyboard shortcuts',
                                            selected: _selectedSection == _SettingsSection.shortcuts,
                                            onTap: () => setState(() => _selectedSection = _SettingsSection.shortcuts),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  OutlinedButton.icon(
                                    onPressed: () => context.push(RouteNames.settings),
                                    icon: const Icon(Icons.settings_outlined),
                                    label: const Text('App Settings'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              buildCard(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Text(
                                        'My Account',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '/ ${sectionLabel(_selectedSection)}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: AppTheme.mediumGray,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: buildSectionContent(_selectedSection),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SettingsSection {
  workspace,
  overview,
  members,
  label,
  projects,
  templates,
  initiatives,
  integrations,
  profile,
  notifications,
  security,
  apiKeys,
  shortcuts,
}
