import 'package:flutter/material.dart';
import '../../../core/sync_engine.dart';
import '../../../data/local/database.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../theme/app_theme.dart';
import 'sync_details_dialog.dart';

/// Compact, tactile status badge displayed in the POS Counter header
/// to give cashiers live visibility into cloud connectivity and queued changes.
class SyncStatusBadge extends StatefulWidget {
  final AppDatabase db;

  const SyncStatusBadge({super.key, required this.db});

  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    SyncEngine.instance?.addListener(_onSyncEngineChanged);
    _checkSpin();
  }

  @override
  void dispose() {
    SyncEngine.instance?.removeListener(_onSyncEngineChanged);
    _rotationController.dispose();
    super.dispose();
  }

  void _onSyncEngineChanged() {
    if (mounted) {
      _checkSpin();
      setState(() {});
    }
  }

  void _checkSpin() {
    final isSyncing = SyncEngine.instance?.isSyncing ?? false;
    if (isSyncing) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
        _rotationController.reset();
      }
    }
  }

  void _openSyncDetails() {
    showDialog(
      context: context,
      builder: (ctx) => SyncDetailsDialog(db: widget.db),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posDao = PosDao(widget.db);
    final engine = SyncEngine.instance;

    return StreamBuilder<int>(
      stream: posDao.watchPendingSyncCount(),
      builder: (context, pendingSnapshot) {
        final pendingCount = pendingSnapshot.data ?? 0;

        return StreamBuilder<int>(
          stream: posDao.watchFailedSyncCount(),
          builder: (context, failedSnapshot) {
            final failedCount = failedSnapshot.data ?? 0;
            final isSyncing = engine?.isSyncing ?? false;

            // Determine display colors and status
            final Color bgColor;
            final Color textColor;
            final Color borderColor;
            final IconData icon;
            final String label;

            if (isSyncing) {
              bgColor = AppTheme.accentColor.withValues(alpha: 0.12);
              textColor = AppTheme.accentColor;
              borderColor = AppTheme.accentColor.withValues(alpha: 0.3);
              icon = Icons.sync_rounded;
              label = 'Syncing...';
            } else if (failedCount > 0) {
              bgColor = Colors.red.shade50;
              textColor = Colors.red.shade700;
              borderColor = Colors.red.shade200;
              icon = Icons.sync_problem_rounded;
              label = '$failedCount Failed';
            } else if (pendingCount > 0) {
              bgColor = Colors.amber.shade50;
              textColor = Colors.amber.shade900;
              borderColor = Colors.amber.shade300;
              icon = Icons.cloud_upload_outlined;
              label = '$pendingCount Pending';
            } else {
              bgColor = AppTheme.inStockBg;
              textColor = AppTheme.inStockColor;
              borderColor = AppTheme.inStockColor.withValues(alpha: 0.25);
              icon = Icons.cloud_done_rounded;
              label = 'Synced';
            }

            return Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('counter_sync_status_badge'),
                onTap: _openSyncDetails,
                borderRadius: BorderRadius.circular(8),
                child: Tooltip(
                  message: 'Cloud Sync: $label • Tap for details',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSyncing)
                          RotationTransition(
                            turns: _rotationController,
                            child: Icon(icon, size: 13, color: textColor),
                          )
                        else
                          Icon(icon, size: 13, color: textColor),
                        const SizedBox(width: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
