import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/services/product_image_service.dart';
import '../../theme/app_theme.dart';

/// Smart offline-first product thumbnail widget.
///
/// Tier 1: Local file on disk (from [imagePath]) -> Immediate display via memory cache, zero disk churn.
/// Tier 2: Cloud CDN URL (from [imageUrl]) -> Loaded with network image with loading spinner.
/// Tier 3: Category fallback icon badge.
class ProductThumbnail extends StatefulWidget {
  final String? imagePath;
  final String? imageUrl;
  final String? categoryName;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final double fallbackIconSize;

  const ProductThumbnail({
    super.key,
    this.imagePath,
    this.imageUrl,
    this.categoryName,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.fallbackIconSize = 28,
  });

  @override
  State<ProductThumbnail> createState() => _ProductThumbnailState();
}

class _ProductThumbnailState extends State<ProductThumbnail> {
  File? _resolvedFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAndResolve();
  }

  @override
  void didUpdateWidget(ProductThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _checkAndResolve();
    }
  }

  void _checkAndResolve() {
    final path = widget.imagePath;
    if (path == null || path.trim().isEmpty) {
      _resolvedFile = null;
      _isLoading = false;
      return;
    }

    final cached = ProductImageService.getCachedFile(path);
    if (cached != null) {
      _resolvedFile = cached;
      _isLoading = false;
    } else {
      _isLoading = true;
      ProductImageService.resolveLocalFile(path).then((file) {
        if (mounted && widget.imagePath == path) {
          setState(() {
            _resolvedFile = file;
            _isLoading = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(8);

    if (_resolvedFile != null) {
      final cacheW = widget.width != null ? (widget.width! * 2).toInt() : 200;
      final cacheH = widget.height != null ? (widget.height! * 2).toInt() : 200;
      return ClipRRect(
        borderRadius: effectiveRadius,
        child: Image.file(
          _resolvedFile!,
          width: widget.width,
          height: widget.height,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) => _buildCloudOrFallback(effectiveRadius),
        ),
      );
    }

    if (_isLoading) {
      return _buildLoading(effectiveRadius);
    }

    return _buildCloudOrFallback(effectiveRadius);
  }

  Widget _buildCloudOrFallback(BorderRadius radius) {
    if (widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          widget.imageUrl!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildLoading(radius);
          },
          errorBuilder: (context, error, stackTrace) => _buildFallback(radius),
        ),
      );
    }
    return _buildFallback(radius);
  }

  Widget _buildLoading(BorderRadius radius) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: radius,
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildFallback(BorderRadius radius) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: radius,
      ),
      child: Center(
        child: Icon(
          _getCategoryIcon(widget.categoryName),
          color: AppTheme.primaryColor.withValues(alpha: 0.75),
          size: widget.fallbackIconSize,
        ),
      ),
    );
  }

  static IconData _getCategoryIcon(String? category) {
    final cat = (category ?? '').toLowerCase();
    if (cat.contains('produce') || cat.contains('fruit') || cat.contains('veg') || cat.contains('meat')) {
      return Icons.eco_rounded;
    } else if (cat.contains('beverage') || cat.contains('drink') || cat.contains('juice') || cat.contains('coffee')) {
      return Icons.local_cafe_rounded;
    } else if (cat.contains('bakery') || cat.contains('bread') || cat.contains('pastr')) {
      return Icons.bakery_dining_rounded;
    } else if (cat.contains('snack') || cat.contains('chip') || cat.contains('biscuit')) {
      return Icons.cookie_rounded;
    } else if (cat.contains('dairy') || cat.contains('milk') || cat.contains('cheese') || cat.contains('egg')) {
      return Icons.egg_alt_rounded;
    } else if (cat.contains('canned') || cat.contains('instant') || cat.contains('noodle') || cat.contains('soup')) {
      return Icons.soup_kitchen_rounded;
    } else if (cat.contains('frozen') || cat.contains('ice')) {
      return Icons.ac_unit_rounded;
    } else if (cat.contains('personal') || cat.contains('hygiene') || cat.contains('care')) {
      return Icons.clean_hands_rounded;
    } else if (cat.contains('house') || cat.contains('clean') || cat.contains('laundry')) {
      return Icons.dry_cleaning_rounded;
    }
    return Icons.inventory_2_rounded;
  }
}
