import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import 'product_thumbnail.dart';

/// Reusable offline-first Product Image Picker card for Add & Edit product forms.
class ProductImagePicker extends StatelessWidget {
  final String? imagePath;
  final String? imageUrl;
  final XFile? pickedFile;
  final String? categoryName;
  final ValueChanged<XFile> onImagePicked;
  final VoidCallback onImageRemoved;

  const ProductImagePicker({
    super.key,
    this.imagePath,
    this.imageUrl,
    this.pickedFile,
    this.categoryName,
    required this.onImagePicked,
    required this.onImageRemoved,
  });

  bool get hasImage =>
      pickedFile != null ||
      (imagePath != null && imagePath!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  Future<void> _showPickerOptions(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.add_a_photo_rounded, color: AppTheme.primaryColor),
                    const SizedBox(width: 10),
                    Text(
                      hasImage ? 'Change Product Photo' : 'Add Product Photo',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0F2FE),
                  child: Icon(Icons.camera_alt_rounded, color: Color(0xFF0284C7)),
                ),
                title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Use camera to capture item photo offline', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(context, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3E8FF),
                  child: Icon(Icons.photo_library_rounded, color: Color(0xFF9333EA)),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Select an existing photo from device album', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(context, ImageSource.gallery);
                },
              ),
              if (hasImage) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEE2E2),
                    child: Icon(Icons.delete_outline_rounded, color: Colors.red),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onImageRemoved();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked != null) {
        onImagePicked(picked);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access ${source == ImageSource.camera ? "camera" : "gallery"}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;

          Widget thumbWidget;
          if (pickedFile != null) {
            thumbWidget = ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(pickedFile!.path),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            );
          } else if (hasImage) {
            thumbWidget = ProductThumbnail(
              imagePath: imagePath,
              imageUrl: imageUrl,
              categoryName: categoryName,
              width: 52,
              height: 52,
              borderRadius: BorderRadius.circular(10),
            );
          } else {
            thumbWidget = Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorderColor),
              ),
              child: const Icon(
                Icons.add_a_photo_outlined,
                color: Colors.black38,
                size: 26,
              ),
            );
          }

          final imageInfo = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasImage ? 'Product Photo Attached' : 'Product Photo',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 2),
              Text(
                hasImage
                    ? 'Saved locally • Syncs to cloud when online'
                    : 'Tap to take photo or pick from gallery',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          );

          final actionButtons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                key: const Key('change_picture_button'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(
                  hasImage ? Icons.edit_rounded : Icons.add_photo_alternate_outlined,
                  size: 15,
                ),
                label: Text(
                  hasImage ? 'Change' : 'Add Photo',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () => _showPickerOptions(context),
              ),
              if (hasImage) ...[
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('remove_picture_button'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                  tooltip: 'Remove Photo',
                  onPressed: onImageRemoved,
                ),
              ],
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    thumbWidget,
                    const SizedBox(width: 12),
                    Expanded(child: imageInfo),
                  ],
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actionButtons),
              ],
            );
          }

          return Row(
            children: [
              thumbWidget,
              const SizedBox(width: 12),
              Expanded(child: imageInfo),
              const SizedBox(width: 8),
              actionButtons,
            ],
          );
        },
      ),
    );
  }
}
