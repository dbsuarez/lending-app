import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/widgets/table_columns.dart';
import '../../core/config/app_config.dart';
import '../../core/formatting.dart';
import '../../core/widgets/responsive_card_list.dart';
import '../../core/widgets/clearable_search_field.dart';
import '../../data/repositories/supabase_audit_repository.dart';
import '../../domain/models/models.dart';

class AuditEventsScreen extends StatefulWidget {
  const AuditEventsScreen({super.key});

  @override
  State<AuditEventsScreen> createState() => _AuditEventsScreenState();
}

class _AuditEventsScreenState extends State<AuditEventsScreen> {
  late Future<List<AuditEventSummary>> events = _load();
  String query = '';
  int sortColumnIndex = 0;
  bool sortAscending = false;

  Future<List<AuditEventSummary>> _load() {
    if (!AppConfig.hasSupabase ||
        Supabase.instance.client.auth.currentUser == null) {
      return Future.value(const []);
    }
    return SupabaseAuditRepository(Supabase.instance.client).fetchRecent();
  }

  void _refresh() => setState(() => events = _load());

  @override
  Widget build(BuildContext context) => Padding(
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
                'Audit History',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh audit history',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClearableSearchField(
          onChanged: (value) => setState(() => query = value),
          hintText: 'Search action, record type, or ID',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<AuditEventSummary>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Audit history failed to load. Try Again',
                    ),
                  ),
                );
              }
              final normalized = query.trim().toLowerCase();
              final items = (snapshot.data ?? const <AuditEventSummary>[])
                  .where(
                    (event) =>
                        normalized.isEmpty ||
                        event.action.toLowerCase().contains(normalized) ||
                        event.recordType.toLowerCase().contains(normalized) ||
                        event.recordId.toLowerCase().contains(normalized),
                  )
                  .toList();
              items.sort((left, right) {
                final comparison = switch (sortColumnIndex) {
                  0 => left.createdAt.compareTo(right.createdAt),
                  1 => left.action.compareTo(right.action),
                  2 => left.recordType.compareTo(right.recordType),
                  3 => left.recordId.compareTo(right.recordId),
                  _ => 0,
                };
                return sortAscending ? comparison : -comparison;
              });
              if (items.isEmpty) {
                return const Center(child: Text('No audit events to display.'));
              }
              return LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 760
                    ? ResponsiveCardList(
                        itemCount: items.length,
                        itemBuilder: (_, index) => _AuditCard(items[index]),
                      )
                    : ColumnToggle(
                        tableId: 'audit',
                        labels: const [
                          'Date and time',
                          'Action',
                          'Record type',
                          'Record ID',
                          'Details',
                        ],
                        builder: (view) => Card(
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: DataTable(
                              sortColumnIndex: view.sortIndex(sortColumnIndex),
                              sortAscending: sortAscending,
                              columns: view.columns([
                                DataColumn(
                                  label: const Text('Date and time'),
                                  onSort: _sort,
                                ),
                                DataColumn(
                                  label: const Text('Action'),
                                  onSort: _sort,
                                ),
                                DataColumn(
                                  label: const Text('Record type'),
                                  onSort: _sort,
                                ),
                                DataColumn(
                                  label: const Text('Record ID'),
                                  onSort: _sort,
                                ),
                                const DataColumn(label: Text('Details')),
                              ]),
                              rows: [
                                for (final event in items)
                                  DataRow(
                                    cells: view.cells([
                                      DataCell(
                                        Text(
                                          formatPhilippineDateTime(
                                            event.createdAt,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(_eventLabel(event.action))),
                                      DataCell(Text(event.recordType)),
                                      DataCell(SelectableText(event.recordId)),
                                      DataCell(_PayloadDetails(event.payload)),
                                    ]),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    ),
  );

  void _sort(int columnIndex, bool ascending) => setState(() {
    sortColumnIndex = columnIndex;
    sortAscending = ascending;
  });
}

class _AuditCard extends StatelessWidget {
  const _AuditCard(this.event);
  final AuditEventSummary event;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.history),
      title: Text(_eventLabel(event.action)),
      subtitle: Text(
        '${formatPhilippineDateTime(event.createdAt)}\n${event.recordType} · ${event.recordId}',
      ),
      isThreeLine: true,
      trailing: event.payload.isEmpty
          ? null
          : Tooltip(
              message: event.payload.entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join('\n'),
              child: const Icon(Icons.info_outline),
            ),
    ),
  );
}

class _PayloadDetails extends StatelessWidget {
  const _PayloadDetails(this.payload);
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) => payload.isEmpty
      ? const Text('—')
      : Tooltip(
          message: payload.entries
              .map((entry) => '${entry.key}: ${entry.value}')
              .join('\n'),
          child: const Icon(Icons.info_outline),
        );
}

String _eventLabel(String action) => action
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
