import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/models.dart';

const demoOrganizationId = '00000000-0000-0000-0000-000000000001';

class BorrowersNotifier extends Notifier<List<Borrower>> {
  @override
  List<Borrower> build() => const [
    Borrower(
      id: 'b0',
      organizationId: demoOrganizationId,
      firstName: 'Maricar',
      lastName: 'Origino',
    ),
    Borrower(
      id: 'b1',
      organizationId: demoOrganizationId,
      firstName: 'Maria',
      lastName: 'Dela Cruz',
      phone: '0917 555 0101',
      email: 'maria@example.test',
      address: 'Quezon City',
    ),
    Borrower(
      id: 'b2',
      organizationId: demoOrganizationId,
      firstName: 'Ramon',
      lastName: 'Santos',
      phone: '0917 555 0102',
      address: 'Makati City',
    ),
    Borrower(
      id: 'b3',
      organizationId: demoOrganizationId,
      firstName: 'Ana',
      lastName: 'Perez',
      phone: '0917 555 0103',
      address: 'Pasig City',
    ),
  ];
  void save({
    String? id,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String address,
  }) {
    final borrower = Borrower(
      id: id ?? const Uuid().v4(),
      organizationId: demoOrganizationId,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
    );
    state = id == null
        ? [...state, borrower]
        : [for (final item in state) item.id == id ? borrower : item];
  }

  void archive(String id) {
    state = state.where((item) => item.id != id).toList();
  }
}

final borrowersProvider = NotifierProvider<BorrowersNotifier, List<Borrower>>(
  BorrowersNotifier.new,
);
