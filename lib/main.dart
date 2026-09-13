import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';
import 'services/api.dart';
import 'services/update_service.dart';
import 'models/models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  runApp(const ExchangeApp());
}

final money = NumberFormat('#,##0.00');
final money0 = NumberFormat('#,##0');

class ExchangeApp extends StatelessWidget {
  const ExchangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Narail Express Exchange',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2563EB),
        fontFamily: 'Roboto',
      ),
      home: Api.isLoggedIn ? const HomeShell() : const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final res = await Api.post('/login', {
        'login': _login.text.trim(),
        'password': _password.text,
        'device_name': 'android',
      });
      await Api.setToken(res['token']);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.currency_exchange, size: 64, color: Color(0xFF2563EB)),
                const SizedBox(height: 12),
                const Text('Narail Express Exchange',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: _login,
                  decoration: const InputDecoration(
                    labelText: 'Email or Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Login'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Extra screens reachable from the app menu.
enum AppPage { home, pending, exchanges, users, banks, expenses, dashboard }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Narail Express', 'Pending for Review', 'Exchanges', 'Users', 'More'];

  final _bodies = const <Widget>[
    HomeOverview(),
    PendingContent(),
    ExchangesContent(),
    UsersContent(),
    MoreContent(),
  ];

  Future<void> _open(AppPage page) async {
    Navigator.pop(context);
    Widget screen;
    switch (page) {
      case AppPage.home:
        setState(() => _index = 0);
        return;
      case AppPage.pending:
        setState(() => _index = 1);
        return;
      case AppPage.exchanges:
        setState(() => _index = 2);
        return;
      case AppPage.users:
        setState(() => _index = 3);
        return;
      case AppPage.dashboard:
        screen = const Scaffold(appBar: null, body: DashboardContent());
        break;
      case AppPage.banks:
        screen = const BanksScreen();
        break;
      case AppPage.expenses:
        screen = const ExpensesScreen();
        break;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'Check for updates',
            onPressed: () => UpdateService.check(context, silent: false),
          ),
        ],
      ),
      drawer: AppDrawer(onOpen: _open),
      body: _bodies[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.pending_actions_outlined), selectedIcon: Icon(Icons.pending_actions), label: 'Pending'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Exchanges'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Users'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final void Function(AppPage) onOpen;
  const AppDrawer({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem('Dashboard', Icons.dashboard_outlined, () => onOpen(AppPage.dashboard)),
      _MenuItem('Home / Overview', Icons.home_outlined, () => onOpen(AppPage.home)),
      _MenuItem('Pending for Review', Icons.pending_actions_outlined, () => onOpen(AppPage.pending)),
      _MenuItem('Exchanges', Icons.swap_horiz_outlined, () => onOpen(AppPage.exchanges)),
      _MenuItem('Users', Icons.people_outline, () => onOpen(AppPage.users)),
      _MenuItem('Banks', Icons.account_balance_outlined, () => onOpen(AppPage.banks)),
      _MenuItem('Expenses', Icons.receipt_long_outlined, () => onOpen(AppPage.expenses)),
      _MenuItem('New Exchange', Icons.add_circle_outline, () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateExchangeScreen()));
      }),
      _MenuItem('New User', Icons.person_add_alt_1_outlined, () async {
        Navigator.pop(context);
        final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreateUserScreen()));
        if (created == true) UpdateService.check(context);
      }),
      _MenuItem('Check for updates', Icons.system_update_alt, () {
        Navigator.pop(context);
        UpdateService.check(context, silent: false);
      }),
      _MenuItem('Logout', Icons.logout, () async {
        try { await Api.post('/logout'); } catch (_) {}
        await Api.setToken(null);
        if (!context.mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }),
    ];

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF2563EB)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.currency_exchange, color: Colors.white, size: 40),
                SizedBox(height: 8),
                Text('Narail Express Exchange', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          for (final item in items)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.title),
              onTap: item.onTap,
            ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  _MenuItem(this.title, this.icon, this.onTap);
}

// ---------------------------------------------------------------------------
// HOME OVERVIEW (grid of all menus)
// ---------------------------------------------------------------------------

class HomeOverview extends StatefulWidget {
  const HomeOverview({super.key});
  @override
  State<HomeOverview> createState() => _HomeOverviewState();
}

class _HomeOverviewState extends State<HomeOverview> {
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('/summary');
      if (mounted) setState(() => _summary = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final menus = <_HomeItem>[
      _HomeItem('Dashboard', Icons.dashboard, Colors.indigo, const DashboardScreen()),
      _HomeItem('Exchanges', Icons.swap_horiz, Colors.blue, const AllExchangesScreen()),
      _HomeItem('Pending', Icons.pending_actions, Colors.orange, const PendingListScreen()),
      _HomeItem('Users', Icons.people, Colors.teal, const UsersScreen()),
      _HomeItem('Banks', Icons.account_balance, Colors.purple, const BanksScreen()),
      _HomeItem('Expenses', Icons.receipt_long, Colors.deepOrange, const ExpensesScreen()),
      _HomeItem('New Exchange', Icons.add_circle, Colors.green, const CreateExchangeScreen()),
      _HomeItem('New User', Icons.person_add_alt_1, Colors.cyan, const CreateUserScreen()),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_summary != null)
            Row(
              children: [
                _mini('Pending', '${_summary!['pending']}', Colors.orange),
                _mini('Approved', '${_summary!['approved']}', Colors.green),
                _mini('Canceled', '${_summary!['canceled']}', Colors.red),
              ],
            ),
          const SizedBox(height: 16),
          const Text('All menus', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: menus
                .map((m) => InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => m.screen));
                        if (r == true) _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: m.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: m.color.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(m.icon, color: m.color, size: 28),
                            const SizedBox(height: 10),
                            Text(m.title, style: TextStyle(fontWeight: FontWeight.bold, color: m.color)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ),
      );
}

class _HomeItem {
  final String title;
  final IconData icon;
  final Color color;
  final Widget screen;
  _HomeItem(this.title, this.icon, this.color, this.screen);
}

// ---------------------------------------------------------------------------
// DASHBOARD
// ---------------------------------------------------------------------------

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: const DashboardContent(),
    );
  }
}

class DashboardContent extends StatefulWidget {
  const DashboardContent({super.key});
  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> {
  Map<String, dynamic>? _summary;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('/summary');
      setState(() => _summary = data);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_summary == null)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _stat('Pending', '${_summary!['pending']}', Colors.orange),
                _stat('Approved', '${_summary!['approved']}', Colors.green),
                _stat('Canceled', '${_summary!['canceled']}', Colors.red),
                _stat('Bank Balance', '৳ ${money0.format(_summary!['bank_balance'])}', Colors.indigo),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PENDING
// ---------------------------------------------------------------------------

class PendingListScreen extends StatelessWidget {
  const PendingListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Pending for Review')), body: const PendingContent());
  }
}

class PendingContent extends StatefulWidget {
  const PendingContent({super.key});
  @override
  State<PendingContent> createState() => _PendingContentState();
}

class _PendingContentState extends State<PendingContent> {
  List<ExchangeItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Api.get('/pending');
      setState(() => _items = (res['data'] as List).map((e) => ExchangeItem.fromJson(e)).toList());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(int id, String status) async {
    try {
      await Api.post('/exchanges/$id/status', {'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked $status')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) return const Center(child: Text('No pending orders'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = _items[i];
          return ListTile(
            title: Text('${e.userName ?? 'N/A'} • ${e.type.toUpperCase()}'),
            subtitle: Text('Order ${e.orderNumber ?? '-'}\n৳ ${money.format(e.totalAmount)} • ${e.channel ?? '-'}'),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: () => _setStatus(e.id, 'approved'), child: const Text('Approve', style: TextStyle(color: Colors.green))),
                TextButton(onPressed: () => _setStatus(e.id, 'canceled'), child: const Text('Cancel', style: TextStyle(color: Colors.red))),
              ],
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExchangeDetailScreen(id: e.id))),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// EXCHANGES
// ---------------------------------------------------------------------------

class AllExchangesScreen extends StatelessWidget {
  const AllExchangesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exchanges')),
      body: const ExchangesContent(),
    );
  }
}

class ExchangesContent extends StatefulWidget {
  const ExchangesContent({super.key});
  @override
  State<ExchangesContent> createState() => _ExchangesContentState();
}

class _ExchangesContentState extends State<ExchangesContent> {
  List<ExchangeItem> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Api.get('/exchanges', _filter.isEmpty ? null : {'status': _filter});
      setState(() => _items = (res['data'] as List).map((e) => ExchangeItem.fromJson(e)).toList());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      case 'canceled': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final f in ['', 'pending', 'approved', 'canceled'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.isEmpty ? 'All' : f[0].toUpperCase() + f.substring(1)),
                    selected: _filter == f,
                    onSelected: (_) { _filter = f; _load(); },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = _items[i];
                          final color = _statusColor(e.status);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withOpacity(0.15),
                              child: Text(e.type == 'buy' ? 'B' : 'S', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(e.userName ?? 'N/A'),
                            subtitle: Text('৳ ${money.format(e.totalAmount)} • ${e.channel ?? '-'} • #${e.id}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                              child: Text(e.status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExchangeDetailScreen(id: e.id))),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class ExchangeDetailScreen extends StatefulWidget {
  final int id;
  const ExchangeDetailScreen({super.key, required this.id});
  @override
  State<ExchangeDetailScreen> createState() => _ExchangeDetailScreenState();
}

class _ExchangeDetailScreenState extends State<ExchangeDetailScreen> {
  ExchangeItem? _item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.get('/exchanges/${widget.id}').then((j) {
      setState(() { _item = ExchangeItem.fromJson(j); _loading = false; });
    }).catchError((_) => setState(() => _loading = false));
  }

  Future<void> _setStatus(String s) async {
    await Api.post('/exchanges/${widget.id}/status', {'status': s});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked $s')));
    Navigator.pop(context, true);
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final status = _item?.status ?? '';
    final showActions = status != 'approved' && status != 'canceled';
    return Scaffold(
      appBar: AppBar(title: Text('Exchange #${widget.id}')),
      body: _loading || _item == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('User', _item!.userName ?? 'N/A'),
                  _row('Order', _item!.orderNumber ?? '-'),
                  _row('Type', _item!.type.toUpperCase()),
                  _row('Channel', _item!.channel ?? '-'),
                  _row('Bank', _item!.bankName ?? 'No bank matched'),
                  _row('Amount', '৳ ${money.format(_item!.totalAmount)}'),
                  _row('Rate', '${_item!.rate}'),
                  _row('Paid', '৳ ${money.format(_item!.paidAmount)}'),
                  _row('Due', '৳ ${money.format(_item!.dueAmount)}'),
                  _row('Status', _item!.status),
                  const Spacer(),
                  if (showActions)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () => _setStatus('approved'),
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => _setStatus('canceled'),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class CreateExchangeScreen extends StatefulWidget {
  const CreateExchangeScreen({super.key});
  @override
  State<CreateExchangeScreen> createState() => _CreateExchangeScreenState();
}

class _CreateExchangeScreenState extends State<CreateExchangeScreen> {
  final _qty = TextEditingController();
  final _rate = TextEditingController();
  final _orderNumber = TextEditingController();
  String _type = 'buy';
  String _channel = 'NPSB';
  String _status = 'approved';
  int? _userId;
  int? _bankId;
  List<UserItem> _users = [];
  List<BankItem> _banks = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      final results = await Future.wait([Api.get('/users'), Api.get('/banks')]);
      setState(() {
        _users = (results[0]['data'] as List).map((e) => UserItem.fromJson(e)).toList();
        _banks = (results[1]['data'] as List).map((e) => BankItem.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_userId == null) {
      setState(() => _error = 'Please select a user');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await Api.post('/exchanges', {
        'exchange_type': _type,
        'user_id': _userId,
        'quantity': double.tryParse(_qty.text) ?? 0,
        'rate': double.tryParse(_rate.text) ?? 0,
        'bank_id': _bankId,
        'transfer_channel': _channel,
        'exchange_status': _status,
        'binance_order_number': _orderNumber.text.trim().isEmpty ? null : _orderNumber.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Exchange')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'buy', label: Text('Buy')),
                    ButtonSegment(value: 'sell', label: Text('Sell')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'User', border: OutlineInputBorder()),
                  value: _userId,
                  items: _users.map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _userId = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (USDT)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _rate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate (BDT)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Bank', border: OutlineInputBorder()),
                  value: _bankId,
                  items: _banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _bankId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Channel', border: OutlineInputBorder()),
                  value: _channel,
                  items: const [
                    DropdownMenuItem(value: 'NPSB', child: Text('NPSB')),
                    DropdownMenuItem(value: 'BEFTN', child: Text('BEFTN')),
                    DropdownMenuItem(value: 'DB2B', child: Text('DB2B')),
                  ],
                  onChanged: (v) => setState(() => _channel = v ?? 'NPSB'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'approved'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _orderNumber, decoration: const InputDecoration(labelText: 'Binance Order Number (optional)', border: OutlineInputBorder())),
                if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Create Exchange'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// USERS
// ---------------------------------------------------------------------------

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Users')), body: const UsersContent());
  }
}

class UsersContent extends StatefulWidget {
  const UsersContent({super.key});
  @override
  State<UsersContent> createState() => _UsersContentState();
}

class _UsersContentState extends State<UsersContent> {
  List<UserItem> _items = [];
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.get('/users', _search.text.isEmpty ? null : {'q': _search.text});
      setState(() => _items = (res['data'] as List).map((e) => UserItem.fromJson(e)).toList());
    } catch (_) {
      setState(() => _items = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreateUserScreen()));
          if (created == true) _load();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New User'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search name / phone / username',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = _items[i];
                        return ListTile(
                          leading: CircleAvatar(child: Text(u.fullName.isNotEmpty ? u.fullName[0] : '?')),
                          title: Text(u.fullName),
                          subtitle: Text('${u.phone ?? '-'} • ${u.role ?? 'N/A'}'),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserDetailScreen(id: u.id))),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});
  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await Api.post('/users', {
        'full_name': _name.text.trim(),
        'phone_number': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New User')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder())),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create User'),
            ),
          ),
        ],
      ),
    );
  }
}

class UserDetailScreen extends StatefulWidget {
  final int id;
  const UserDetailScreen({super.key, required this.id});
  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final _captureKey = GlobalKey();
  Map<String, dynamic>? _detail;
  UserItem? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.get('/users/${widget.id}/detail');
      setState(() {
        _detail = j;
        _user = UserItem.fromJson(j['user']);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _payment(String direction) async {
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(direction == 'received' ? 'Received amount' : 'Paid amount'),
        content: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Amount BDT')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/users/${widget.id}/due-payment', {'direction': direction, 'amount': double.tryParse(amount.text) ?? 0});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _copyImage() async {
    try {
      final boundary = _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      await Pasteboard.writeImage(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Summary image copied to clipboard')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy failed: $e')));
    }
  }

  Future<void> _shareImage() async {
    try {
      final boundary = _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      await Share.shareXFiles([XFile.fromData(bytes, name: 'user-summary.png', mimeType: 'image/png')]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('User')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_detail == null || _user == null) {
      return Scaffold(appBar: AppBar(title: const Text('User')), body: const Center(child: Text('User not found')));
    }

    final m = _detail!['metrics'] as Map<String, dynamic>;
    final net = (_detail!['net_due'] as num).toDouble();
    final prev = 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_user!.fullName),
        actions: [
          IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy summary image', onPressed: _copyImage),
          IconButton(icon: const Icon(Icons.share), tooltip: 'Share summary image', onPressed: _shareImage),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepaintBoundary(
            key: _captureKey,
            child: Container(
              color: const Color(0xFFF1F5F9),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _card('Full Name', _user!.fullName, Colors.blue),
                  _card('Email', _user!.email ?? 'N/A', Colors.indigo),
                  _card('Phone', _user!.phone ?? 'N/A', Colors.green),
                  _card('Completed Trade', '${m['completed']}', Colors.teal),
                  _card('Total Buy', '${money.format(m['total_buy_usd'])} USD', Colors.blue),
                  _card('Total Sell', '${money.format(m['total_sell_usd'])} USD', Colors.red),
                  _card('Total Vol USD', '${money.format(m['total_volume_usd'])} USD', Colors.purple),
                  _card('Previous Due', 'Ami Petam = ${money0.format(prev)} BDT', Colors.grey),
                  _dueCard(net),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () => _payment('received'),
                  icon: const Icon(Icons.south_west),
                  label: const Text('Received'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
                  onPressed: () => _payment('paid'),
                  icon: const Icon(Icons.north_east),
                  label: const Text('Paid'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Trading History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _UserTrades(userId: widget.id),
        ],
      ),
    );
  }

  Widget _card(String label, String value, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _dueCard(double net) {
    final color = net > 0 ? Colors.green : (net < 0 ? Colors.red : Colors.grey);
    final text = net > 0 ? 'Ami Pabo = ${money0.format(net)} BDT' : (net < 0 ? 'Apni Paben = ${money0.format(net.abs())} BDT' : 'No Due = 0 BDT');
    return _card('Due Balance', text, color);
  }
}

class _UserTrades extends StatefulWidget {
  final int userId;
  const _UserTrades({required this.userId});
  @override
  State<_UserTrades> createState() => _UserTradesState();
}

class _UserTradesState extends State<_UserTrades> {
  List<ExchangeItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.get('/users/${widget.userId}/exchanges').then((res) {
      setState(() {
        _items = (res['data'] as List).map((e) => ExchangeItem.fromJson(e)).toList();
        _loading = false;
      });
    }).catchError((_) => setState(() => _loading = false));
  }

  Color _c(String s) {
    switch (s) {
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      case 'canceled': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    if (_items.isEmpty) return const Text('No trades found');
    return Column(
      children: _items.map((e) {
        final color = _c(e.status);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${e.type.toUpperCase()} • ৳ ${money.format(e.totalAmount)}'),
            subtitle: Text('${e.channel ?? '-'} • Rate ${e.rate}\nStatus: ${e.status}'),
            isThreeLine: true,
            trailing: Text('#${e.id}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExchangeDetailScreen(id: e.id))),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// BANKS
// ---------------------------------------------------------------------------

class BanksScreen extends StatefulWidget {
  const BanksScreen({super.key});
  @override
  State<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState extends State<BanksScreen> {
  List<BankItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.get('/banks').then((res) {
      setState(() {
        _items = (res['data'] as List).map((e) => BankItem.fromJson(e)).toList();
        _loading = false;
      });
    }).catchError((_) => setState(() => _loading = false));
  }

  Future<void> _copyBank(BankItem b) async {
    final text = 'Bank Name: ${b.name}\n'
        'Beneficiary: ${b.beneficiary ?? '-'}\n'
        'Account Number: ${b.accountNumber ?? '-'}\n'
        'Account Type: ${b.accountType ?? '-'}\n'
        'Routing: ${b.routing ?? '-'}\n'
        'Bank Address: ${b.bankAddress ?? '-'}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: ${b.name}'), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banks')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final b = _items[i];
                return ListTile(
                  leading: const Icon(Icons.account_balance, color: Colors.indigo),
                  title: Text(b.name),
                  subtitle: Text('${b.accountNumber ?? '-'}\nBalance ৳ ${money0.format(b.balance)} • NPSB ${b.npsbLimit} • DB2B ${b.db2bLimit}'),
                  isThreeLine: true,
                  trailing: IconButton(icon: const Icon(Icons.copy, color: Colors.indigo), onPressed: () => _copyBank(b)),
                  onTap: () => _copyBank(b),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// EXPENSES
// ---------------------------------------------------------------------------

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.get('/expenses').then((res) {
      setState(() { _items = res['data'] as List; _loading = false; });
    }).catchError((_) => setState(() => _loading = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.deepOrange),
                  title: Text('${e['title'] ?? ''}'),
                  subtitle: Text('${e['category'] ?? ''} • ${e['expense_date'] ?? ''}'),
                  trailing: Text('৳ ${money.format((e['amount'] ?? 0))}', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              },
            ),
    );
  }
}
