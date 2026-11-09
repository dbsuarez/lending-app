import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'evidence_counts.dart';
import '../../core/widgets/menu_label.dart';
import '../../core/config/app_config.dart';
import '../../core/export_file.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../data/repositories/supabase_documents_repository.dart';
import '../../domain/models/models.dart';

const evidenceTypes = <(String, String)>[
  ('disbursement_evidence', 'Money release proof'),
  ('payment_evidence', 'Payment proof'),
  ('late_payment_note', 'Late-payment reason / promise'),
  ('agreement', 'Signed agreement'),
  ('acknowledgment', 'Acknowledgment'),
  ('other', 'Other'),
];

String evidenceTypeLabel(String type) => evidenceTypes
    .firstWhere((t) => t.$1 == type, orElse: () => (type, 'Other'))
    .$2;

/// A loan's private evidence: thumbnails for photos, PDFs and photos open
/// inside the app, upload with a chosen type. Used on the loan page and on
/// the Documents page.
class LoanEvidenceSection extends ConsumerStatefulWidget {
  const LoanEvidenceSection({super.key, required this.loan});
  final LoanSummary loan;

  @override
  ConsumerState<LoanEvidenceSection> createState() =>
      _LoanEvidenceSectionState();
}

class _LoanEvidenceSectionState extends ConsumerState<LoanEvidenceSection> {
  SupabaseDocumentsRepository? _repository;
  List<LoanDocumentSummary>? documents;
  String? error;
  bool uploading = false;

  /// Downloaded file contents, shared by thumbnails and the viewer.
  final Map<String, Future<Uint8List>> _bytes = {};

  @override
  void initState() {
    super.initState();
    if (AppConfig.hasSupabase) {
      _repository = SupabaseDocumentsRepository(Supabase.instance.client);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final list = await _repository!.fetchForLoan(widget.loan.id);
      if (mounted) setState(() => documents = list);
    } catch (_) {
      if (mounted) setState(() => error = 'Evidence could not be loaded.');
    }
  }

  Future<Uint8List> _download(LoanDocumentSummary d) =>
      _bytes[d.storagePath] ??= _repository!.download(d.storagePath);

  Future<void> _upload(String type) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null || !mounted) return;
    final extension = file.extension?.toLowerCase();
    final mime = extension == 'pdf'
        ? 'application/pdf'
        : extension == 'png'
        ? 'image/png'
        : 'image/jpeg';
    setState(() => uploading = true);
    try {
      await _repository!.uploadEvidence(
        organizationId: widget.loan.organizationId,
        loanId: widget.loan.id,
        documentType: type,
        originalName: file.name,
        mimeType: mime,
        bytes: await file.readAsBytes(),
      );
      if (mounted) undoOf(context).record('Evidence uploaded.');
      ref.invalidate(evidenceCountsProvider);
      await _load();
    } catch (_) {
      if (mounted) {
        undoOf(
          context,
        ).record('Upload failed. Use a PDF, JPG or PNG no larger than 10 MB.');
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  void _open(LoanDocumentSummary d) => showDialog<void>(
    context: context,
    builder: (_) => _EvidenceViewer(
      document: d,
      bytes: _download(d),
      signedUrl: () => _repository!.signedUrl(d.storagePath),
      onChangeType: (type) => _changeType(d, type),
    ),
  );

  Future<bool> _changeType(LoanDocumentSummary d, String type) async {
    try {
      await _repository!.setType(d.id, type);
      await _load();
      if (mounted) {
        undoOf(context).notify('Moved to ${evidenceTypeLabel(type)}.');
      }
      return true;
    } catch (_) {
      if (mounted) undoOf(context).record('The category could not be changed.');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Row(
      children: [
        const Icon(Icons.attach_file),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Evidence', style: theme.textTheme.titleMedium),
              Text(
                'Receipts, proof of release or payment, signed papers. Private to your team.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_repository != null)
          MenuAnchor(
            menuChildren: [
              for (final (value, label) in evidenceTypes)
                MenuItemButton(
                  onPressed: () => _upload(value),
                  child: Text(label),
                ),
            ],
            builder: (context, controller, _) => FilledButton.icon(
              onPressed: uploading
                  ? null
                  : () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
              icon: uploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: const MenuLabel('Upload'),
            ),
          ),
      ],
    );

    final Widget body;
    if (_repository == null) {
      body = const Text('Evidence is available when connected to the server.');
    } else if (error != null) {
      body = Text(error!, style: TextStyle(color: theme.colorScheme.error));
    } else if (documents == null) {
      body = const LinearProgressIndicator();
    } else if (documents!.isEmpty) {
      body = const Text(
        'Nothing uploaded yet. Use Upload to add a photo or PDF.',
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (type, label) in evidenceTypes)
            if (documents!.any((d) => d.type == type)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '$label (${documents!.where((d) => d.type == type).length})',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final d in documents!.where((d) => d.type == type))
                    _EvidenceTile(
                      document: d,
                      bytes: d.mimeType.startsWith('image/')
                          ? _download(d)
                          : null,
                      onOpen: () => _open(d),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [header, const SizedBox(height: 16), body],
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({
    required this.document,
    required this.bytes,
    required this.onOpen,
  });
  final LoanDocumentSummary document;
  final Future<Uint8List>? bytes;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Icon(
      bytes == null ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
      size: 40,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      width: 160,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 110,
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: bytes == null
                    ? placeholder
                    : FutureBuilder<Uint8List>(
                        future: bytes,
                        builder: (_, snap) => snap.hasData
                            ? Image.memory(
                                snap.data!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 110,
                                cacheWidth: 320,
                                errorBuilder: (_, _, _) => placeholder,
                              )
                            : snap.hasError
                            ? placeholder
                            : const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evidenceTypeLabel(document.type),
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      formatPhilippineDateTime(document.createdAt),
                      style: theme.textTheme.bodySmall,
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
}

class _EvidenceViewer extends StatefulWidget {
  const _EvidenceViewer({
    required this.document,
    required this.bytes,
    required this.signedUrl,
    required this.onChangeType,
  });
  final LoanDocumentSummary document;
  final Future<Uint8List> bytes;
  final Future<Uri> Function() signedUrl;
  final Future<bool> Function(String type) onChangeType;

  @override
  State<_EvidenceViewer> createState() => _EvidenceViewerState();
}

class _EvidenceViewerState extends State<_EvidenceViewer> {
  late String type = widget.document.type;
  LoanDocumentSummary get document => widget.document;
  Future<Uint8List> get bytes => widget.bytes;
  Future<Uri> Function() get signedUrl => widget.signedUrl;

  bool get isPdf => document.mimeType == 'application/pdf';

  Widget _categoryMenu() => MenuAnchor(
    menuChildren: [
      for (final (value, label) in evidenceTypes)
        MenuItemButton(
          leadingIcon: Icon(value == type ? Icons.check : null, size: 18),
          onPressed: value == type
              ? null
              : () async {
                  if (await widget.onChangeType(value) && mounted) {
                    setState(() => type = value);
                  }
                },
          child: Text(label),
        ),
    ],
    builder: (context, controller, _) => IconButton(
      tooltip: 'Change category',
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.label_outline),
    ),
  );

  Future<void> _save(BuildContext context) async {
    final data = await bytes;
    final dot = document.name.lastIndexOf('.');
    final where = await saveExport(
      name: dot > 0 ? document.name.substring(0, dot) : document.name,
      bytes: data,
      extension: isPdf
          ? 'pdf'
          : (document.mimeType == 'image/png' ? 'png' : 'jpg'),
      mimeType: isPdf
          ? MimeType.pdf
          : document.mimeType == 'image/png'
          ? MimeType.png
          : MimeType.jpeg,
    );
    if (context.mounted && where != null) {
      undoOf(context).notify('Saved to $where.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: size.width > 1000 ? 900 : size.width,
        height: size.height * 0.85,
        child: Column(
          children: [
            ListTile(
              title: Text(
                document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${evidenceTypeLabel(type)} · '
                '${formatPhilippineDateTime(document.createdAt)} · '
                '${(document.sizeBytes / 1048576).toStringAsFixed(2)} MB',
              ),
              trailing: Wrap(
                children: [
                  _categoryMenu(),
                  IconButton(
                    tooltip: 'Save a copy',
                    onPressed: () => _save(context),
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: 'Open in a new tab (link works for 5 minutes)',
                    onPressed: () async => launchUrl(await signedUrl()),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: bytes,
                builder: (_, snap) {
                  if (snap.hasError) {
                    return const Center(
                      child: Text('The file could not be loaded.'),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (isPdf) {
                    return PdfPreview(
                      build: (_) async => snap.data!,
                      pdfFileName: document.name,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      allowSharing: false,
                    );
                  }
                  return InteractiveViewer(
                    maxScale: 6,
                    child: Center(child: Image.memory(snap.data!)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
