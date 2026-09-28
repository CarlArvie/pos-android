import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../data/local/daos/pos_dao.dart';
import '../presentation/theme/app_theme.dart';

class TransactionExportService {
  static const MethodChannel _downloadChannel = MethodChannel('com.example.pos/download_saver');

  /// Generates a professional multi-sheet Microsoft Excel (.xlsx) file
  static Uint8List generateExcelWorkbook({
    required List<TransactionDetail> transactions,
    String companyName = 'Apex Supermarket & POS',
    String storeName = 'Main Retail Branch',
    DateTimeRange? dateRange,
  }) {
    final excel = Excel.createExcel();
    const summarySheetName = 'Transactions Summary';
    const itemsSheetName = 'Itemized Sales';

    // Set up sheets
    excel.rename('Sheet1', summarySheetName);
    final sheet1 = excel[summarySheetName];
    final sheet2 = excel[itemsSheetName];

    // Computed totals
    double totalGross = 0.0;
    double totalDiscounts = 0.0;
    double totalTax = 0.0;
    double totalNet = 0.0;

    for (final t in transactions) {
      totalGross += t.transaction.subtotal;
      totalDiscounts += t.transaction.discountTotal;
      totalTax += t.transaction.taxTotal;
      totalNet += t.transaction.grandTotal;
    }

    // 1. Sheet 1: Header & KPI Blocks
    sheet1.appendRow([TextCellValue(companyName)]);
    sheet1.appendRow([TextCellValue('$storeName • Sales Transactions Report')]);
    sheet1.appendRow([
      TextCellValue(
        dateRange != null
            ? 'Period: ${dateRange.start.toLocal().toString().substring(0, 10)} to ${dateRange.end.toLocal().toString().substring(0, 10)}'
            : 'Period: All Time (Generated: ${DateTime.now().toLocal().toString().substring(0, 16)})',
      ),
    ]);
    sheet1.appendRow([TextCellValue('')]); // Blank row

    // Executive Summary block
    sheet1.appendRow([TextCellValue('EXECUTIVE SUMMARY'), TextCellValue('')]);
    sheet1.appendRow([TextCellValue('Total Transactions:'), IntCellValue(transactions.length)]);
    sheet1.appendRow([TextCellValue('Gross Sales (Subtotal):'), DoubleCellValue(totalGross)]);
    sheet1.appendRow([TextCellValue('Total Discounts:'), DoubleCellValue(totalDiscounts)]);
    sheet1.appendRow([TextCellValue('Total VAT Tax:'), DoubleCellValue(totalTax)]);
    sheet1.appendRow([TextCellValue('Net Sales (Grand Total):'), DoubleCellValue(totalNet)]);
    sheet1.appendRow([TextCellValue('')]); // Blank row

    // Master Table Headers
    final tableHeaders = [
      TextCellValue('Invoice No'),
      TextCellValue('Date & Time'),
      TextCellValue('Items Count'),
      TextCellValue('Subtotal (₱)'),
      TextCellValue('Discount (₱)'),
      TextCellValue('Tax (₱)'),
      TextCellValue('Grand Total (₱)'),
      TextCellValue('Payment Method'),
      TextCellValue('Amount Tendered (₱)'),
      TextCellValue('Change Due (₱)'),
      TextCellValue('Reference No'),
      TextCellValue('Status'),
    ];
    sheet1.appendRow(tableHeaders);

    // Populate Transactions rows
    for (final t in transactions) {
      final tx = t.transaction;
      final tender = t.tenders.isNotEmpty ? t.tenders.first : null;
      final paymentMethod = tender?.paymentMethod.toUpperCase() ?? 'CASH';
      final tendered = tender?.amountTendered ?? tx.grandTotal;
      final change = tender?.changeAmount ?? 0.0;
      final ref = tender?.referenceNo ?? '';

      sheet1.appendRow([
        TextCellValue(tx.invoiceNo),
        TextCellValue(tx.transactionDatetime.toLocal().toString().substring(0, 16)),
        IntCellValue(t.items.length),
        DoubleCellValue(tx.subtotal),
        DoubleCellValue(tx.discountTotal),
        DoubleCellValue(tx.taxTotal),
        DoubleCellValue(tx.grandTotal),
        TextCellValue(paymentMethod),
        DoubleCellValue(tendered),
        DoubleCellValue(change),
        TextCellValue(ref),
        TextCellValue(tx.status.toUpperCase()),
      ]);
    }

    // 2. Sheet 2: Itemized Sales Breakdown
    sheet2.appendRow([TextCellValue('$companyName - Itemized Sales Line Items')]);
    sheet2.appendRow([TextCellValue('')]);
    final itemHeaders = [
      TextCellValue('Invoice No'),
      TextCellValue('Date & Time'),
      TextCellValue('Product Name'),
      TextCellValue('SKU'),
      TextCellValue('Variant'),
      TextCellValue('Sell Mode'),
      TextCellValue('Quantity / Weight'),
      TextCellValue('Unit Price (₱)'),
      TextCellValue('Discount (₱)'),
      TextCellValue('Tax (₱)'),
      TextCellValue('Line Total (₱)'),
    ];
    sheet2.appendRow(itemHeaders);

    for (final t in transactions) {
      for (final i in t.items) {
        final sellMode = i.product.sellBy == 'fraction' ? '1:1000 Fractional (kg)' : 'Discrete Unit';
        final qtyDisplay = i.product.sellBy == 'fraction'
            ? '${i.item.quantity.toStringAsFixed(3)} kg'
            : i.item.quantity.toInt().toString();

        sheet2.appendRow([
          TextCellValue(t.transaction.invoiceNo),
          TextCellValue(t.transaction.transactionDatetime.toLocal().toString().substring(0, 16)),
          TextCellValue(i.product.productName),
          TextCellValue(i.product.sku ?? ''),
          TextCellValue(i.product.variantName ?? ''),
          TextCellValue(sellMode),
          TextCellValue(qtyDisplay),
          DoubleCellValue(i.item.unitPrice),
          DoubleCellValue(i.item.discountAmount),
          DoubleCellValue(i.item.taxAmount),
          DoubleCellValue(i.item.subtotal),
        ]);
      }
    }

    final bytes = excel.save();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Generates an Excel-compatible CSV string with UTF-8 BOM
  static String generateCsvReport({
    required List<TransactionDetail> transactions,
    String companyName = 'Apex Supermarket & POS',
    DateTimeRange? dateRange,
    bool includeItemDetails = false,
  }) {
    final List<List<dynamic>> rows = [];

    // Header Metadata
    rows.add([companyName, 'Sales Transactions Report']);
    rows.add([
      dateRange != null
          ? 'Date Range: ${dateRange.start.toLocal().toString().substring(0, 10)} to ${dateRange.end.toLocal().toString().substring(0, 10)}'
          : 'Date Range: All Time',
      'Generated: ${DateTime.now().toLocal().toString().substring(0, 16)}',
    ]);
    rows.add([]);

    if (!includeItemDetails) {
      // Summary CSV Table
      rows.add([
        'Invoice No',
        'Date & Time',
        'Items Count',
        'Subtotal (PHP)',
        'Discount (PHP)',
        'Tax (PHP)',
        'Grand Total (PHP)',
        'Payment Method',
        'Amount Tendered (PHP)',
        'Change (PHP)',
        'Reference No',
        'Status',
      ]);

      for (final t in transactions) {
        final tx = t.transaction;
        final tender = t.tenders.isNotEmpty ? t.tenders.first : null;
        rows.add([
          tx.invoiceNo,
          tx.transactionDatetime.toLocal().toString().substring(0, 16),
          t.items.length,
          tx.subtotal.toStringAsFixed(2),
          tx.discountTotal.toStringAsFixed(2),
          tx.taxTotal.toStringAsFixed(2),
          tx.grandTotal.toStringAsFixed(2),
          tender?.paymentMethod.toUpperCase() ?? 'CASH',
          (tender?.amountTendered ?? tx.grandTotal).toStringAsFixed(2),
          (tender?.changeAmount ?? 0.0).toStringAsFixed(2),
          tender?.referenceNo ?? '',
          tx.status.toUpperCase(),
        ]);
      }
    } else {
      // Detailed Itemized CSV Table
      rows.add([
        'Invoice No',
        'Date & Time',
        'Product Name',
        'SKU',
        'Variant',
        'Sell Type',
        'Quantity / Weight',
        'Unit Price (PHP)',
        'Line Total (PHP)',
        'Payment Method',
        'Status',
      ]);

      for (final t in transactions) {
        final tender = t.tenders.isNotEmpty ? t.tenders.first : null;
        for (final i in t.items) {
          final sellMode = i.product.sellBy == 'fraction' ? 'Weighed (kg)' : 'Unit';
          final qty = i.product.sellBy == 'fraction'
              ? '${i.item.quantity.toStringAsFixed(3)} kg'
              : i.item.quantity.toInt().toString();

          rows.add([
            t.transaction.invoiceNo,
            t.transaction.transactionDatetime.toLocal().toString().substring(0, 16),
            i.product.productName,
            i.product.sku ?? '',
            i.product.variantName ?? '',
            sellMode,
            qty,
            i.item.unitPrice.toStringAsFixed(2),
            i.item.subtotal.toStringAsFixed(2),
            tender?.paymentMethod.toUpperCase() ?? 'CASH',
            t.transaction.status.toUpperCase(),
          ]);
        }
      }
    }

    final csvString = Csv().encode(rows);
    // Prepend UTF-8 BOM so Excel opens it with proper encoding
    return '\uFEFF$csvString';
  }

  /// Resolves the most accessible Downloads directory across Android, Desktop, and iOS
  static Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // 1. Request runtime storage permission on Android (crucial for Android 9 & below, e.g. Oppo A5s)
      try {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          await Permission.storage.request();
        }
      } catch (e) {
        debugPrint('permission_handler request error: $e');
      }

      // 2. Direct Path Way: Point directly to the public Download folder
      try {
        final publicDownloadDir = Directory('/storage/emulated/0/Download');
        if (!await publicDownloadDir.exists()) {
          await publicDownloadDir.create(recursive: true);
        }
        return publicDownloadDir;
      } catch (e) {
        debugPrint('Could not access /storage/emulated/0/Download: $e');
      }
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final dir = await getDownloadsDirectory();
        if (dir != null && await dir.exists()) {
          return dir;
        }
      } catch (_) {}
    }

    // Fallback to application documents directory
    return await getApplicationDocumentsDirectory();
  }

  /// Direct Path Way (dart:io) to write directly into /storage/emulated/0/Download
  /// on Android with runtime permission requests via permission_handler.
  static Future<File> saveReportFile({
    required List<int> bytes,
    required String extension, // 'xlsx' or 'csv'
    String baseName = 'Sales_Transactions',
  }) async {
    final timestamp = DateTime.now().toLocal().toString().replaceAll(RegExp(r'[: -]'), '_').substring(0, 15);
    final fileName = '${baseName}_$timestamp.$extension';

    if (Platform.isAndroid) {
      // 1. Request storage permission (Required for Android 9 and below, e.g. Oppo A5s)
      try {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          await Permission.storage.request();
        }
      } catch (e) {
        debugPrint('permission_handler request error: $e');
      }

      // 2. Direct Path Way: Point directly to the public Download folder
      try {
        final downloadDirectory = Directory('/storage/emulated/0/Download');
        if (!await downloadDirectory.exists()) {
          await downloadDirectory.create(recursive: true);
        }

        final file = File('${downloadDirectory.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);

        // Notify Android system scanner so file shows immediately in Downloads tab
        try {
          await _downloadChannel.invokeMethod('scanFile', {'path': file.path});
        } catch (_) {}

        debugPrint('Direct Path Way successfully saved to: ${file.path}');
        return file;
      } catch (e) {
        debugPrint('Direct public Download write error: $e. Attempting MediaStore native fallback.');
      }

      // 3. Fallback: If direct path failed (e.g. Scoped Storage on newer Android 11+ devices), use native MediaStore channel
      try {
        final mimeType = extension == 'xlsx'
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : 'text/csv';
        final savedPath = await _downloadChannel.invokeMethod<String>('saveToPublicDownloads', {
          'bytes': Uint8List.fromList(bytes),
          'fileName': fileName,
          'mimeType': mimeType,
        });
        if (savedPath != null && savedPath.isNotEmpty) {
          return File(savedPath);
        }
      } catch (e) {
        debugPrint('Native channel fallback error: $e');
      }
    }

    // 4. Desktop (Windows, macOS, Linux): Save to platform downloads directory
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final dir = await getDownloadsDirectory();
        if (dir != null && await dir.exists()) {
          final file = File('${dir.path}/$fileName');
          await file.writeAsBytes(bytes, flush: true);
          return file;
        }
      } catch (_) {}
    }

    // 5. Ultimate fallback if external storage unavailable: application documents directory
    final fallbackDir = await getApplicationDocumentsDirectory();
    final fallbackFile = File('${fallbackDir.path}/$fileName');
    await fallbackFile.writeAsBytes(bytes, flush: true);
    return fallbackFile;
  }

  /// Shares or opens the report using platform share UI.
  /// Writes directly to cache directory first to ensure 100% FileProvider compatibility and avoid PathAccessException.
  static Future<void> shareFile(
    File file, {
    String subject = 'Sales Transactions Export',
    List<int>? fallbackBytes,
  }) async {
    final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'report';
    File shareableFile = file;

    try {
      final cacheDir = await getTemporaryDirectory();
      final cacheFile = File('${cacheDir.path}/$fileName');

      if (fallbackBytes != null && fallbackBytes.isNotEmpty) {
        await cacheFile.writeAsBytes(fallbackBytes, flush: true);
        shareableFile = cacheFile;
      } else {
        if (await file.exists()) {
          shareableFile = await file.copy(cacheFile.path);
        }
      }
    } catch (_) {
      // Keep original file if cache creation fails
    }

    final isXlsx = fileName.toLowerCase().endsWith('.xlsx');
    final mimeType = isXlsx
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        : 'text/csv';

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(shareableFile.path, mimeType: mimeType)],
        subject: subject,
        text: 'Exported transaction report from Apex POS',
      ),
    );
  }

  /// Generates a comprehensive multi-sheet Sales, Profit & Analytics Excel report
  static Uint8List generateSalesReportWorkbook({
    required SalesReportData reportData,
    String companyName = 'Apex Supermarket & POS',
    String storeName = 'Main Retail Branch',
    String periodLabel = 'All Time',
  }) {
    final excel = Excel.createExcel();

    // 1. Sheet 1: Financial & P&L Summary
    const pnlSheetName = 'Financial P&L';
    excel.rename('Sheet1', pnlSheetName);
    final sheet1 = excel[pnlSheetName];

    sheet1.appendRow([TextCellValue(companyName)]);
    sheet1.appendRow([TextCellValue('$storeName • Executive Sales & Financial Report')]);
    sheet1.appendRow([TextCellValue('Reporting Period: $periodLabel • Generated: ${DateTime.now().toLocal().toString().substring(0, 16)}')]);
    sheet1.appendRow([TextCellValue('')]);

    sheet1.appendRow([TextCellValue('FINANCIAL PERFORMANCE SUMMARY'), TextCellValue('')]);
    sheet1.appendRow([TextCellValue('Gross Sales:'), DoubleCellValue(reportData.grossSales)]);
    sheet1.appendRow([TextCellValue('Discounts (Senior/PWD/Promo):'), DoubleCellValue(reportData.discountTotal)]);
    sheet1.appendRow([TextCellValue('VAT Tax (12%):'), DoubleCellValue(reportData.taxTotal)]);
    sheet1.appendRow([TextCellValue('Net Sales (Total Revenue):'), DoubleCellValue(reportData.netSales)]);
    sheet1.appendRow([TextCellValue('Cost of Goods Sold (COGS):'), DoubleCellValue(reportData.totalCogs)]);
    sheet1.appendRow([TextCellValue('Gross Profit (Sales - Cost):'), DoubleCellValue(reportData.grossProfit)]);
    sheet1.appendRow([TextCellValue('Gross Profit Margin:'), TextCellValue('${reportData.grossMarginPercent.toStringAsFixed(1)}%')]);
    sheet1.appendRow([TextCellValue('Store Operating Expenses:'), DoubleCellValue(reportData.totalExpenses)]);
    sheet1.appendRow([TextCellValue('Net Profit (Gross Profit - Expenses):'), DoubleCellValue(reportData.netProfit)]);
    sheet1.appendRow([TextCellValue('Net Profit Margin:'), TextCellValue('${reportData.netMarginPercent.toStringAsFixed(1)}%')]);
    sheet1.appendRow([TextCellValue('')]);

    sheet1.appendRow([TextCellValue('TRANSACTION METRICS'), TextCellValue('')]);
    sheet1.appendRow([TextCellValue('Total Receipt Count:'), IntCellValue(reportData.totalReceipts)]);
    sheet1.appendRow([TextCellValue('Average Order Value (AOV):'), DoubleCellValue(reportData.avgSalesValue)]);
    sheet1.appendRow([TextCellValue('')]);

    // Itemized Expenses Table
    if (reportData.recentExpenses.isNotEmpty) {
      sheet1.appendRow([TextCellValue('OPERATING EXPENSES BREAKDOWN'), TextCellValue(''), TextCellValue('')]);
      sheet1.appendRow([TextCellValue('Date'), TextCellValue('Category'), TextCellValue('Amount (₱)'), TextCellValue('Description')]);
      for (final exp in reportData.recentExpenses) {
        sheet1.appendRow([
          TextCellValue(exp.createdAt.toLocal().toString().substring(0, 10)),
          TextCellValue(exp.category),
          DoubleCellValue(exp.amount),
          TextCellValue(exp.description ?? ''),
        ]);
      }
    }

    // 2. Sheet 2: Top Stocks (Best-Sellers)
    final sheet2 = excel['Top Selling Stocks'];
    sheet2.appendRow([TextCellValue('TOP SELLING STOCKS & PRODUCTS')]);
    sheet2.appendRow([TextCellValue('Rank'), TextCellValue('Product Name'), TextCellValue('Variant'), TextCellValue('Category'), TextCellValue('Qty Sold'), TextCellValue('Total Revenue (₱)'), TextCellValue('COGS (₱)'), TextCellValue('Profit (₱)'), TextCellValue('Margin %')]);

    int rank = 1;
    for (final prod in reportData.topProducts) {
      sheet2.appendRow([
        IntCellValue(rank++),
        TextCellValue(prod.productName),
        TextCellValue(prod.variantName ?? '-'),
        TextCellValue(prod.categoryName ?? 'General'),
        DoubleCellValue(prod.quantitySold),
        DoubleCellValue(prod.totalRevenue),
        DoubleCellValue(prod.totalCost),
        DoubleCellValue(prod.profit),
        TextCellValue('${prod.profitMarginPercent.toStringAsFixed(1)}%'),
      ]);
    }

    // 3. Sheet 3: Top Categories & Payment Modes
    final sheet3 = excel['Categories & Payments'];
    sheet3.appendRow([TextCellValue('CATEGORY SALES BREAKDOWN')]);
    sheet3.appendRow([TextCellValue('Category'), TextCellValue('Items Sold'), TextCellValue('Total Revenue (₱)'), TextCellValue('Share %')]);

    for (final cat in reportData.topCategories) {
      sheet3.appendRow([
        TextCellValue(cat.categoryName),
        DoubleCellValue(cat.quantitySold),
        DoubleCellValue(cat.totalRevenue),
        TextCellValue('${cat.sharePercentage.toStringAsFixed(1)}%'),
      ]);
    }

    sheet3.appendRow([TextCellValue('')]);
    sheet3.appendRow([TextCellValue('PAYMENT MODES DISTRIBUTION')]);
    sheet3.appendRow([TextCellValue('Payment Method'), TextCellValue('Transactions'), TextCellValue('Total Amount (₱)'), TextCellValue('Share %')]);

    for (final pm in reportData.paymentModes) {
      sheet3.appendRow([
        TextCellValue(pm.displayName),
        IntCellValue(pm.count),
        DoubleCellValue(pm.totalAmount),
        TextCellValue('${pm.sharePercentage.toStringAsFixed(1)}%'),
      ]);
    }

    // 4. Sheet 4: Customers & Staff (Sold By)
    final sheet4 = excel['Customers & Staff'];
    sheet4.appendRow([TextCellValue('TOP CUSTOMERS')]);
    sheet4.appendRow([TextCellValue('Customer Name'), TextCellValue('Loyalty Tier'), TextCellValue('Visits / Orders'), TextCellValue('Total Spend (₱)')]);

    for (final cust in reportData.topCustomers) {
      sheet4.appendRow([
        TextCellValue(cust.customerName),
        TextCellValue(cust.loyaltyTier),
        IntCellValue(cust.ordersCount),
        DoubleCellValue(cust.totalSpend),
      ]);
    }

    sheet4.appendRow([TextCellValue('')]);
    sheet4.appendRow([TextCellValue('SALES BY STAFF (SOLD BY)')]);
    sheet4.appendRow([TextCellValue('Staff Member'), TextCellValue('Position'), TextCellValue('Receipts Processed'), TextCellValue('Total Sales (₱)'), TextCellValue('Avg Ticket (₱)')]);

    for (final staff in reportData.soldBy) {
      sheet4.appendRow([
        TextCellValue(staff.employeeName),
        TextCellValue(staff.position),
        IntCellValue(staff.receiptCount),
        DoubleCellValue(staff.totalSales),
        DoubleCellValue(staff.averageTicket),
      ]);
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Exports the executive sales & financial report to Excel and triggers save/share dialog
  static Future<void> exportSalesReport({
    required BuildContext context,
    required SalesReportData reportData,
    String periodLabel = 'All Time',
  }) async {
    final bytes = generateSalesReportWorkbook(
      reportData: reportData,
      periodLabel: periodLabel,
    );

    try {
      final file = await saveReportFile(
        bytes: bytes,
        extension: 'xlsx',
        baseName: 'Sales_Report',
      );
      final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'Sales_Report.xlsx';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to Downloads: $fileName'),
            backgroundColor: AppTheme.inStockColor,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => shareFile(file, subject: 'Sales & Financial Report ($periodLabel)'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save to Downloads: $e. Opening share menu...')),
        );
      }
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/Sales_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await tempFile.writeAsBytes(bytes);
      await shareFile(tempFile, subject: 'Sales & Financial Report ($periodLabel)');
    }
  }
}
