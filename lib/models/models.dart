class ExchangeItem {
  final int id;
  final String? orderNumber;
  final String type;
  final String status;
  final String? channel;
  final String? userName;
  final int? userId;
  final String? bankName;
  final int? bankId;
  final double totalAmount;
  final double paidAmount;
  final double dueAmount;
  final double rate;

  ExchangeItem({
    required this.id,
    this.orderNumber,
    required this.type,
    required this.status,
    this.channel,
    this.userName,
    this.userId,
    this.bankName,
    this.bankId,
    required this.totalAmount,
    required this.paidAmount,
    required this.dueAmount,
    required this.rate,
  });

  factory ExchangeItem.fromJson(Map<String, dynamic> j) {
    return ExchangeItem(
      id: j['id'] is int ? j['id'] : int.parse('${j['id']}'),
      orderNumber: j['binance_order_number']?.toString(),
      type: (j['exchange_type'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      channel: j['channel']?.toString(),
      userName: j['user'] != null ? j['user']['name']?.toString() : null,
      userId: j['user'] != null ? j['user']['id'] as int? : null,
      bankName: j['bank'] != null ? j['bank']['name']?.toString() : null,
      bankId: j['bank'] != null ? j['bank']['id'] as int? : null,
      totalAmount: (j['total_amount'] ?? 0).toDouble(),
      paidAmount: (j['paid_to_seller_bdt'] ?? 0).toDouble(),
      dueAmount: (j['due_amount'] ?? 0).toDouble(),
      rate: (j['rate'] ?? 0).toDouble(),
    );
  }
}

class BankItem {
  final int id;
  final String name;
  final String? beneficiary;
  final String? accountNumber;
  final double balance;
  final int npsbLimit;
  final int db2bLimit;

  BankItem({
    required this.id,
    required this.name,
    this.beneficiary,
    this.accountNumber,
    required this.balance,
    required this.npsbLimit,
    required this.db2bLimit,
  });

  factory BankItem.fromJson(Map<String, dynamic> j) => BankItem(
        id: j['id'] as int,
        name: (j['name'] ?? '').toString(),
        beneficiary: j['beneficiary_name']?.toString(),
        accountNumber: j['account_number']?.toString(),
        balance: (j['balance'] ?? 0).toDouble(),
        npsbLimit: (j['npsb_daily_limit'] ?? 20) as int,
        db2bLimit: (j['db2b_daily_limit'] ?? 20) as int,
      );
}

class UserItem {
  final int id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? role;

  UserItem({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.role,
  });

  factory UserItem.fromJson(Map<String, dynamic> j) => UserItem(
        id: j['id'] as int,
        fullName: (j['full_name'] ?? '').toString(),
        phone: j['phone_number']?.toString(),
        email: j['email']?.toString(),
        role: j['role']?.toString(),
      );
}
