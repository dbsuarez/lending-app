import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/undo/undo_controller.dart';
import '../../core/widgets/confirm_action.dart';
import 'payment_qr_provider.dart';

class PaymentQrScreen extends ConsumerStatefulWidget {
  const PaymentQrScreen({super.key});
  @override
  ConsumerState<PaymentQrScreen> createState() => _PaymentQrScreenState();
}

class _PaymentQrScreenState extends ConsumerState<PaymentQrScreen> {
  bool seeding = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_seed);
  }

  Future<void> _seed() async {
    try {
      await ref.read(paymentQrProvider.future);
      final controller = ref.read(paymentQrProvider.notifier);
      if (controller.canManage &&
          (ref.read(paymentQrProvider).value?.isEmpty ?? false)) {
        if (mounted) setState(() => seeding = true);
        await controller.seedBundledDefaults();
      }
    } finally {
      if (mounted) setState(() => seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentQrProvider);
    final controller = ref.read(paymentQrProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to Settings',
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Payment QR Codes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (controller.canManage)
                FilledButton.icon(
                  onPressed: seeding ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Add QR…'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enabled QR codes appear in loan schedules, payment ledgers, and '
            'statements. Owners and managers can add, rename, replace, '
            'disable, or delete them.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Payment QR codes could not be loaded.'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(paymentQrProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text(
                        controller.canManage
                            ? 'No QR codes yet. Add Palawan Pay or another bank or wallet.'
                            : 'No payment QR codes are configured.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) =>
                          _tile(items[index], controller),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(PaymentQrCode qr, PaymentQrController controller) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          FutureBuilder<Uint8List>(
            future: controller.download(qr),
            builder: (context, snapshot) => InkWell(
              onTap: snapshot.hasData
                  ? () => _preview(qr.label, snapshot.data!)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: snapshot.hasData
                      ? Image.memory(snapshot.data!, fit: BoxFit.contain)
                      : const ColoredBox(
                          color: Color(0x11000000),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(qr.label, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  qr.enabled
                      ? 'Shown on borrower documents'
                      : 'Hidden from borrower documents',
                ),
              ],
            ),
          ),
          if (controller.canManage) ...[
            Switch(
              value: qr.enabled,
              onChanged: (value) async {
                if (!await controller.setEnabled(qr, value) && mounted) {
                  undoOf(context).record('QR visibility could not be changed.');
                }
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'QR actions',
              onSelected: (action) => switch (action) {
                'rename' => _rename(qr),
                'replace' => _replace(qr),
                'delete' => _delete(qr),
                _ => Future<void>.value(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename…')),
                PopupMenuItem(value: 'replace', child: Text('Replace image…')),
                PopupMenuItem(value: 'delete', child: Text('Delete…')),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Future<({String name, String mime, Uint8List bytes})?> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    if (file == null) return null;
    return (
      name: file.name,
      mime: file.extension?.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg',
      bytes: await file.readAsBytes(),
    );
  }

  Future<String?> _label([String initial = '']) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Payment QR name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Palawan Pay',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<void> _add() async {
    final file = await _pick();
    if (file == null || !mounted) return;
    final label = await _label();
    if (label == null || !mounted) return;
    final ok = await ref
        .read(paymentQrProvider.notifier)
        .add(
          label: label,
          name: file.name,
          mimeType: file.mime,
          bytes: file.bytes,
        );
    if (mounted) {
      undoOf(context).record(
        ok
            ? 'Payment QR added.'
            : 'QR could not be added. Use a PNG or JPG no larger than 5 MB.',
      );
    }
  }

  Future<void> _rename(PaymentQrCode qr) async {
    final label = await _label(qr.label);
    if (label == null || !mounted) return;
    final ok = await ref.read(paymentQrProvider.notifier).rename(qr, label);
    if (mounted) {
      undoOf(
        context,
      ).record(ok ? 'Payment QR renamed.' : 'QR could not be renamed.');
    }
  }

  Future<void> _replace(PaymentQrCode qr) async {
    final file = await _pick();
    if (file == null || !mounted) return;
    final ok = await ref
        .read(paymentQrProvider.notifier)
        .replace(qr, mimeType: file.mime, bytes: file.bytes);
    if (mounted) {
      undoOf(
        context,
      ).record(ok ? 'QR image replaced.' : 'QR image could not be replaced.');
    }
  }

  Future<void> _delete(PaymentQrCode qr) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${qr.label}?',
      message:
          'This removes the QR image from borrower documents. This cannot be undone.',
      confirmLabel: 'Delete QR',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(paymentQrProvider.notifier).delete(qr);
    if (mounted) {
      undoOf(
        context,
      ).record(ok ? 'Payment QR deleted.' : 'QR could not be deleted.');
    }
  }

  Future<void> _preview(String label, Uint8List bytes) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: InteractiveViewer(
                  minScale: .8,
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pinch or scroll to zoom. Keep the complete QR visible when scanning.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
