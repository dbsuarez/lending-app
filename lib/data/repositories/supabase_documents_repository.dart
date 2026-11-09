import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseDocumentsRepository {
  SupabaseDocumentsRepository(this._client);
  final SupabaseClient _client;

  Future<String> uploadEvidence({
    required String organizationId,
    required String loanId,
    required String documentType,
    required String originalName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > 10485760) {
      throw const FormatException('Evidence must be between 1 byte and 10 MB.');
    }
    if (!const [
      'application/pdf',
      'image/jpeg',
      'image/png',
    ].contains(mimeType)) {
      throw const FormatException(
        'Only PDF, JPG, and PNG evidence is accepted.',
      );
    }
    final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$organizationId/$loanId/${const Uuid().v4()}-$safeName';
    await _client.storage
        .from('loan-evidence')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      final id = await _client.rpc(
        'register_loan_document',
        params: {
          'p_loan_id': loanId,
          'p_document_type': documentType,
          'p_storage_path': path,
          'p_original_name': originalName,
          'p_mime_type': mimeType,
          'p_size_bytes': bytes.length,
        },
      );
      return id as String;
    } catch (_) {
      await _client.storage.from('loan-evidence').remove([path]);
      rethrow;
    }
  }

  Future<List<LoanDocumentSummary>> fetchForLoan(String loanId) async {
    final rows = await _client
        .from('loan_documents')
        .select(
          'id, document_type, storage_path, original_name, mime_type, size_bytes, created_at',
        )
        .eq('loan_id', loanId)
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        LoanDocumentSummary(
          id: row['id'] as String,
          type: row['document_type'] as String,
          storagePath: row['storage_path'] as String,
          name: row['original_name'] as String,
          mimeType: row['mime_type'] as String,
          sizeBytes: row['size_bytes'] as int,
          createdAt: DateTime.parse(row['created_at'] as String),
        ),
    ];
  }

  /// Changes which category an uploaded file is filed under.
  Future<void> setType(String documentId, String type) => _client.rpc(
    'set_loan_document_type',
    params: {'p_document_id': documentId, 'p_document_type': type},
  );

  /// The file itself, for showing it inside the app.
  Future<Uint8List> download(String storagePath) =>
      _client.storage.from('loan-evidence').download(storagePath);

  Future<Uri> signedUrl(String storagePath) async => Uri.parse(
    await _client.storage
        .from('loan-evidence')
        .createSignedUrl(storagePath, 300),
  );
}

class LoanDocumentSummary {
  const LoanDocumentSummary({
    required this.id,
    required this.type,
    required this.storagePath,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });
  final String id, type, storagePath, name, mimeType;
  final int sizeBytes;
  final DateTime createdAt;
}
