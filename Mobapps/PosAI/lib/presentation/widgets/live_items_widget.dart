/// lib/presentation/widgets/live_items_widget.dart
/// Live Items Display Widget - Shows detected items from AI as a text list.
/// NOT a video stream - just displays item names and quantities.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/websocket/websocket_service.dart';

import 'package:pos_ai/core/utils/ui_helper.dart';

class LiveItemsWidget extends StatelessWidget {
  const LiveItemsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<WebSocketService>(
      builder: (context, wsService, child) {
        final items = wsService.currentItems;
        final isConnected = wsService.isConnected;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(context.scaleW(16)),
            border: Border.all(
              color: isConnected
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.grey.withValues(alpha: 0.3),
              width: context.scaleW(2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: context.scaleW(10),
                offset: Offset(0, context.scaleW(4)),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: context.scaleW(16), vertical: context.scaleH(12)),
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green.withValues(alpha: 0.1)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(context.scaleW(14))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: context.scaleW(12),
                      height: context.scaleW(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? Colors.green : Colors.grey,
                        boxShadow: isConnected
                            ? [
                                BoxShadow(
                                  color: Colors.green.withValues(alpha: 0.5),
                                  blurRadius: context.scaleW(8),
                                  spreadRadius: context.scaleW(2),
                                ),
                              ]
                            : null,
                      ),
                    ),
                    SizedBox(width: context.scaleW(12)),
                    Text(
                      'AI Detection Live',
                      style: GoogleFonts.inter(
                        fontSize: context.scaleSP(14),
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        isConnected ? 'Connected' : wsService.statusMessage,
                        style: GoogleFonts.inter(
                          fontSize: context.scaleSP(12),
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),

              // Items List
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              size: context.scaleW(48),
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3),
                            ),
                            SizedBox(height: context.scaleH(12)),
                            Text(
                              isConnected
                                  ? 'Menunggu deteksi...'
                                  : 'Menunggu koneksi AI...',
                              style: GoogleFonts.inter(
                                fontSize: context.scaleSP(14),
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(context.scaleW(12)),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _LiveItemTile(item: item);
                        },
                      ),
              ),

              // Footer - Last update time
              if (wsService.lastDataTime != null)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: context.scaleW(16), vertical: context.scaleH(8)),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(context.scaleW(14))),
                  ),
                  child: Text(
                    'Update: ${_formatTime(wsService.lastDataTime!)}',
                    style: GoogleFonts.inter(
                      fontSize: context.scaleSP(11),
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

class _LiveItemTile extends StatelessWidget {

  const _LiveItemTile({required this.item});
  final DetectedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: context.scaleH(8)),
      padding: EdgeInsets.symmetric(horizontal: context.scaleW(16), vertical: context.scaleH(12)),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.scaleW(12)),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(context.scaleW(8)),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(context.scaleW(8)),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: context.scaleW(20),
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(width: context.scaleW(12)),
          Expanded(
            child: Text(
              item.label,
              style: GoogleFonts.inter(
                fontSize: context.scaleSP(15),
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: context.scaleW(12), vertical: context.scaleH(6)),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(context.scaleW(20)),
            ),
            child: Text(
              'x${item.qty}',
              style: GoogleFonts.inter(
                fontSize: context.scaleSP(14),
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DetectedItem>('item', item));
  }
}
