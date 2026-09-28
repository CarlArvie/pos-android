import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync_engine.dart';
import '../../../data/local/database.dart';
import '../../../data/local/daos/pos_dao.dart';
import '../../theme/app_theme.dart';

/// Modal dialog for store operators and cashiers to inspect cloud synchronization status,
/// view queued outbox transactions, and manually trigger sync.
class SyncDetailsDialog extends StatefulWidget {
  final AppDatabase db;

  const SyncDetailsDialog({super.key, required this.db});

  @override
  State<SyncDetailsDialog> createState() => _SyncDetailsDialogState();
}

class _SyncDetailsDialogState extends State<SyncDetailsDialog> {
  bool _isManualSyncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    SyncEngine.instance?.addListener(_onSyncEngineChanged);
  }

  @override
  void dispose() {
    SyncEngine.instance?.removeListener(_onSyncEngineChanged);
    super.dispose();
  }

  void _onSyncEngineChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleManualSync() async {
    final engine = SyncEngine.instance;
    if (engine == null) {
      setState(() {
        _syncMessage = 'Cloud connection not configured (Local-only database mode)';
      });
      return;
    }

    setState(() {
      _isManualSyncing = true;
      _syncMessage = null;
    });

    try {
      await engine.syncNow();
      if (mounted) {
        setState(() {
          _syncMessage = 'Synchronization completed successfully';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncMessage = 'Sync error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isManualSyncing = false;
        });
      }
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final engine = SyncEngine.instance;
    final posDao = PosDao(widget.db);
    final isSyncing = _isManualSyncing || (engine?.isSyncing ?? false);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: AppTheme.accentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud Sync & Connectivity',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Offline-first real-time cloud replication',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status Summary Cards
              StreamBuilder<int>(
                stream: posDao.watchPendingSyncCount(),
                builder: (context, pendingSnapshot) {
                  final pendingCount = pendingSnapshot.data ?? 0;

                  return StreamBuilder<int>(
                    stream: posDao.watchFailedSyncCount(),
                    builder: (context, failedSnapshot) {
                      final failedCount = failedSnapshot.data ?? 0;
                      final isRealtimeSubscribed = engine?.realtimeStatus == RealtimeSubscribeStatus.subscribed;

                      return Row(
                        children: [
                          // Realtime / Network Status
                          Expanded(
                            child: _buildStatusCard(
                              title: 'Connection',
                              value: isRealtimeSubscribed
                                  ? 'Online'
                                  : (engine != null ? 'Connecting' : 'Offline'),
                              icon: isRealtimeSubscribed
                                  ? Icons.wifi_rounded
                                  : Icons.cloud_off_rounded,
                              iconColor: isRealtimeSubscribed
                                  ? AppTheme.inStockColor
                                  : Colors.grey.shade600,
                              bgColor: isRealtimeSubscribed
                                  ? AppTheme.inStockBg
                                  : Colors.grey.shade100,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Pending Outbox Count
                          Expanded(
                            child: _buildStatusCard(
                              title: 'Outbox Queue',
                              value: pendingCount == 0
                                  ? 'All Synced'
                                  : '$pendingCount Pending',
                              icon: pendingCount == 0
                                  ? Icons.cloud_done_rounded
                                  : Icons.upload_file_rounded,
                              iconColor: pendingCount == 0
                                  ? AppTheme.inStockColor
                                  : (failedCount > 0 ? Colors.red.shade700 : Colors.amber.shade900),
                              bgColor: pendingCount == 0
                                  ? AppTheme.inStockBg
                                  : (failedCount > 0 ? Colors.red.shade50 : Colors.amber.shade50),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Last Synced
                          Expanded(
                            child: _buildStatusCard(
                              title: 'Last Sync',
                              value: engine?.lastSyncTime != null
                                  ? _formatTimeAgo(engine!.lastSyncTime!)
                                  : 'Active',
                              icon: Icons.access_time_rounded,
                              iconColor: AppTheme.accentColor,
                              bgColor: AppTheme.accentColor.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 14),

              // Manual Trigger Button
              ElevatedButton.icon(
                key: const Key('sync_now_action_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  isSyncing ? 'Synchronizing with Cloud...' : 'Sync Now',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                onPressed: isSyncing ? null : _handleManualSync,
              ),

              if (_syncMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _syncMessage!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _syncMessage!.contains('error') ? Colors.red.shade700 : AppTheme.inStockColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 14),

              // Queue Activity Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Outbox Queue Activity',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StreamBuilder<int>(
                    stream: posDao.watchPendingSyncCount(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: count > 0 ? Colors.amber.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count queued',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: count > 0 ? Colors.amber.shade900 : Colors.grey.shade700,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Outbox Queue Items List
              Expanded(
                child: StreamBuilder<List<SyncQueueData>>(
                  stream: posDao.watchRecentSyncItems(),
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? [];

                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 44,
                              color: Colors.green.shade400,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'All changes are synced with the cloud',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Local database is completely up to date',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (context, index) => const Divider(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isFailed = item.status == 'failed' || item.status == 'abandoned';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isFailed ? Colors.red.shade50 : AppTheme.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isFailed ? Colors.red.shade200 : AppTheme.cardBorderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Action chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.action == 'INSERT'
                                      ? Colors.green.shade100
                                      : item.action == 'UPDATE'
                                          ? Colors.blue.shade100
                                          : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.action,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: item.action == 'INSERT'
                                        ? Colors.green.shade900
                                        : item.action == 'UPDATE'
                                            ? Colors.blue.shade900
                                            : Colors.red.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Table name & record ID
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatTableName(item.targetTable),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    Text(
                                      'ID: ${item.recordId.length > 8 ? item.recordId.substring(0, 8) : item.recordId} • ${_formatTimeAgo(item.createdAt)}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),

                              // Status Chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isFailed
                                      ? Colors.red.shade100
                                      : item.status == 'syncing'
                                          ? Colors.blue.shade100
                                          : Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isFailed ? 'Error' : item.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isFailed
                                        ? Colors.red.shade900
                                        : item.status == 'syncing'
                                            ? Colors.blue.shade900
                                            : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Offline Guarantee Footer Note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.inStockBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.inStockColor.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.inStockColor, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '100% Offline Resilient: Sales and operations are recorded instantly to SQLite and will sync once internet connects.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.inStockColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatTableName(String table) {
    switch (table) {
      case 'sales_transactions':
        return 'Sale Transaction';
      case 'transaction_items':
        return 'Sale Item';
      case 'tender_payments':
        return 'Tender Payment';
      case 'inventories':
        return 'Stock Adjustment';
      case 'products':
        return 'Product Catalog';
      case 'customers':
        return 'Customer Record';
      case 'customer_payments':
        return 'Credit Settlement';
      case 'cash_managements':
        return 'Cash Drawer Shift';
      default:
        return table.replaceAll('_', ' ');
    }
  }
}
