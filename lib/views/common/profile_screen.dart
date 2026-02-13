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

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            if (user == null) ...[
              Text(
                'No profile information available.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: _isUploading ? null : _changeProfileImage,
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: AppTheme.deepBlue.withAlpha(40),
                        backgroundImage: (user.profileImageUrl != null &&
                                user.profileImageUrl!.isNotEmpty)
                            ? NetworkImage(user.profileImageUrl!)
                            : null,
                        child: (user.profileImageUrl == null ||
                                user.profileImageUrl!.isEmpty)
                            ? Text(
                                user.displayName.isNotEmpty
                                    ? user.displayName[0].toUpperCase()
                                    : '?',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.deepBlue,
                                    ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Icon(
                          _isUploading ? Icons.hourglass_top : Icons.camera_alt,
                          size: 16,
                          color: AppTheme.deepBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isUploading) ...[
                const SizedBox(height: 8),
                const Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Text(
                  user.displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.deepBlue.withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    user.role,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.deepBlue,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                await AuthService.instance.signOut();
                if (!context.mounted) return;
                context.go(RouteNames.login);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorRed,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
