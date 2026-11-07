import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/formatting.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../data/repositories/supabase_documents_repository.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import 'loan_schedule_pdf.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  int sortColumnIndex = 1;
  bool sortAscending = true;
  String statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansControllerProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Documents', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text('Generate an A4 payment schedule from stored loan terms.'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: statusFilter,
                decoration: const InputDecoration(labelText: 'Loan status'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'fully_paid', child: Text('Paid')),
                  DropdownMenuItem(
                    value: 'refinanced',
                    child: Text('Refinanced'),
                  ),
                  DropdownMenuItem(
                    value: 'cancelled',
                    child: Text('Cancelled'),
                  ),
                ],
                onChanged: (value) => setState(() => statusFilter = value!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loans.when(
              data: _buildLoans,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('Documents could not be loaded.')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoans(List<LoanSummary> source) {
    if (source.isEmpty) {
      return const Center(child: Text('No loans available.'));
    }
    final items =
        source
            .where(
              (loan) => statusFilter == 'all' || loan.status == statusFilter,
            )
            .toList()
          ..sort((left, right) {
            final comparison = switch (sortColumnIndex) {
              0 => left.id.compareTo(right.id),
              1 => left.borrowerName.toLowerCase().compareTo(
                right.borrowerName.toLowerCase(),
              ),
              2 => left.totalCentavos.compareTo(right.totalCentavos),
              3 => left.status.compareTo(right.status),
              _ => 0,
            };
            return sortAscending ? comparison : -comparison;
          });
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _DocumentLoanCard(
                items[index],
                onEvidence: () => _manageEvidence(context, items[index]),
                onSchedule: () => _printSchedule(items[index]),
              ),
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: DataTable(
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  columns: [
                    DataColumn(label: const Text('Reference'), onSort: _sort),
                    DataColumn(label: const Text('Borrower'), onSort: _sort),
                    DataColumn(
                      label: const Text('Total'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(label: const Text('Status'), onSort: _sort),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final loan in items)
                      DataRow(
                        cells: [
                          DataCell(Text(_reference(loan.id))),
                          DataCell(Text(loan.borrowerName)),
                          DataCell(Text(formatPeso(loan.totalCentavos))),
                          DataCell(AppStatusBadge(loan.status)),
                          DataCell(
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _manageEvidence(context, loan),
                                  icon: const Icon(Icons.attach_file),
                                  label: const Text('Evidence'),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _printSchedule(loan),
                                  icon: const Icon(Icons.print_outlined),
                                  label: const Text('Schedule'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _sort(int columnIndex, bool ascending) => setState(() {
    sortColumnIndex = columnIndex;
    sortAscending = ascending;
  });

  Future<void> _printSchedule(LoanSummary loan) async {
    final detail = await ref
        .read(loansControllerProvider.notifier)
        .fetchDetail(loan.id);
    await Printing.layoutPdf(
      name: '${_reference(loan.id)}-schedule.pdf',
      onLayout: (_) => LoanSchedulePdf.build(detail),
    );
  }

  Future<void> _uploadEvidence(BuildContext context, LoanSummary loan) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return;
    final extension = file.extension?.toLowerCase();
    final mime = extension == 'pdf'
        ? 'application/pdf'
        : extension == 'png'
        ? 'image/png'
        : 'image/jpeg';
    try {
      final bytes = await file.readAsBytes();
      await SupabaseDocumentsRepository(
        Supabase.instance.client,
      ).uploadEvidence(
        organizationId: loan.organizationId,
        loanId: loan.id,
        documentType: 'disbursement_evidence',
        originalName: file.name,
        mimeType: mime,
        bytes: bytes,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Evidence uploaded to private storage.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Evidence upload failed. Use a PDF, JPG, or PNG no larger than 10 MB.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _manageEvidence(BuildContext context, LoanSummary loan) async {
    final repository = SupabaseDocumentsRepository(Supabase.instance.client);
    var documents = await repository.fetchForLoan(loan.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Private loan evidence'),
          content: SizedBox(
            width: 620,
            child: documents.isEmpty
                ? const Text('No evidence has been uploaded for this loan.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: documents.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, index) {
                      final document = documents[index];
                      return ListTile(
                        leading: Icon(
                          document.mimeType == 'application/pdf'
                              ? Icons.picture_as_pdf
                              : Icons.image_outlined,
                        ),
                        title: Text(document.name),
                        subtitle: Text(
                          '${(document.sizeBytes / 1048576).toStringAsFixed(2)} MB · ${formatPhilippineDateTime(document.createdAt)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Open for 5 minutes',
                          onPressed: () async => launchUrl(
                            await repository.signedUrl(document.storagePath),
                          ),
                          icon: const Icon(Icons.open_in_new),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await _uploadEvidence(dialogContext, loan);
                documents = await repository.fetchForLoan(loan.id);
                setDialogState(() {});
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Evidence'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentLoanCard extends StatelessWidget {
  const _DocumentLoanCard(
    this.loan, {
    required this.onEvidence,
    required this.onSchedule,
  });
  final LoanSummary loan;
  final VoidCallback onEvidence, onSchedule;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(loan.borrowerName),
      subtitle: Text(
        '${_reference(loan.id)} · ${formatPeso(loan.totalCentavos)}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Document actions',
        onSelected: (value) =>
            value == 'evidence' ? onEvidence() : onSchedule(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'evidence', child: Text('Evidence')),
          PopupMenuItem(value: 'schedule', child: Text('Print schedule')),
        ],
      ),
    ),
  );
}

String _reference(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';
