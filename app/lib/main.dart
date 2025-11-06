// lib/main.dart
import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const TaskBazaarApp());
}

/// TaskBazaar – Micro-Task Marketplace (Single-file MVP, No backend)
/// Roles: Poster (creates tasks, funds escrow) & Worker (claims, submits)
/// Money Flow (Coins):
/// - Poster tops up coins (mock) -> posts task -> bounty moves to escrow
/// - Worker claims task -> submits proof
/// - Poster approves -> bounty -> worker; platform keeps fee
///
/// Tabs: Browse, Post, Wallet, Profile
/// State: In-memory (resets on restart) – good for demo / investor pitch

class TaskBazaarApp extends StatefulWidget {
  const TaskBazaarApp({Key? key}) : super(key: key);

  @override
  State<TaskBazaarApp> createState() => _TaskBazaarAppState();
}

class _TaskBazaarAppState extends State<TaskBazaarApp> {
  final AppState state = AppState();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskBazaar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: state.currentUser == null
          ? LoginScreen(onLogin: (u) => setState(() => state.currentUser = u))
          : HomeShell(
              state: state,
              onLogout: () => setState(() => state.currentUser = null),
            ),
    );
  }
}

/// ---------------- Models & State ----------------

enum TaskStatus { open, claimed, submitted, approved, rejected }

class User {
  final String id;
  final String name;
  final String avatar;
  int coins; // spendable balance
  int earned; // lifetime earned
  int spent; // lifetime spent
  bool isAdmin;

  User({
    required this.id,
    required this.name,
    required this.avatar,
    this.coins = 100,
    this.earned = 0,
    this.spent = 0,
    this.isAdmin = false,
  });
}

class TaskItem {
  final String id;
  final String title;
  final String description;
  final String tags; // comma separated
  final int bounty; // coins
  final String posterId;
  final DateTime createdAt;

  TaskStatus status;
  String? claimedBy;
  String? submissionNote; // proof text/url
  int platformFee; // coins captured by platform on post
  int escrow; // coins locked until approval

  TaskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.tags,
    required this.bounty,
    required this.posterId,
    required this.createdAt,
    this.status = TaskStatus.open,
    this.claimedBy,
    this.submissionNote,
    this.platformFee = 0,
    this.escrow = 0,
  });
}

class LedgerEntry {
  final String id;
  final String userId; // or "PLATFORM"
  final int delta; // + add coins, - spend
  final String note;
  final DateTime at;
  LedgerEntry({
    required this.id,
    required this.userId,
    required this.delta,
    required this.note,
    required this.at,
  });
}

class AppState {
  User? currentUser;

  // Demo users
  final Map<String, User> users = {
    'u_demoPoster': User(
      id: 'u_demoPoster',
      name: 'Aarav (Poster)',
      avatar: _avatar('poster'),
      coins: 250,
    ),
    'u_demoWorker': User(
      id: 'u_demoWorker',
      name: 'Riya (Worker)',
      avatar: _avatar('worker'),
      coins: 80,
    ),
    'u_admin': User(
      id: 'u_admin',
      name: 'Admin',
      avatar: _avatar('admin'),
      coins: 0,
      isAdmin: true,
    ),
  };

  int platformRevenue = 0;
  final List<LedgerEntry> ledger = [];

  // Seed tasks
  final List<TaskItem> tasks = [
    TaskItem(
      id: 't1',
      title: 'Design 3 YouTube thumbnails',
      description:
          'Channel: tech reviews. Clean, bold fonts. Provide PNG + editable file.',
      tags: 'design,youtube,thumbnail',
      bounty: 60,
      posterId: 'u_demoPoster',
      createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
    ),
    TaskItem(
      id: 't2',
      title: 'Excel: Clean 500 rows',
      description:
          'Remove duplicates, fix casing, standardize phone numbers. Provide .xlsx.',
      tags: 'excel,data,cleanup',
      bounty: 50,
      posterId: 'u_demoPoster',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    TaskItem(
      id: 't3',
      title: 'Voiceover (Hindi, 60s)',
      description: 'Friendly tone, noise-free. Deliver WAV file.',
      tags: 'audio,voiceover,hindi',
      bounty: 70,
      posterId: 'u_demoPoster',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  // Platform fee calculation: 10% (min 3)
  int _feeOn(int amount) {
    final fee = (amount * 0.10).ceil();
    return fee < 3 ? 3 : fee;
  }

  void postTask({
    required String title,
    required String desc,
    required String tags,
    required int bounty,
    required String posterId,
  }) {
    final poster = users[posterId]!;
    final fee = _feeOn(bounty);
    final need = bounty + fee;
    if (poster.coins < need) {
      throw Exception('Not enough coins. Need $need, you have ${poster.coins}');
    }
    poster.coins -= need;
    poster.spent += need;
    platformRevenue += fee;

    final task = TaskItem(
      id: 't_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: desc,
      tags: tags,
      bounty: bounty,
      posterId: posterId,
      createdAt: DateTime.now(),
      platformFee: fee,
      escrow: bounty,
      status: TaskStatus.open,
    );
    tasks.insert(0, task);

    ledger.add(LedgerEntry(
      id: 'l_${DateTime.now().millisecondsSinceEpoch}',
      userId: posterId,
      delta: -need,
      note: 'Post Task: "$title" (bounty $bounty + fee $fee)',
      at: DateTime.now(),
    ));
    ledger.add(LedgerEntry(
      id: 'l_${DateTime.now().millisecondsSinceEpoch + 1}',
      userId: 'PLATFORM',
      delta: fee,
      note: 'Platform fee captured',
      at: DateTime.now(),
    ));
  }

  void claimTask({required String taskId, required String workerId}) {
    final t = tasks.firstWhere((e) => e.id == taskId);
    if (t.status != TaskStatus.open) {
      throw Exception('Task not open.');
    }
    t.status = TaskStatus.claimed;
    t.claimedBy = workerId;
  }

  void submitWork({
    required String taskId,
    required String workerId,
    required String submissionNote,
  }) {
    final t = tasks.firstWhere((e) => e.id == taskId);
    if (t.status != TaskStatus.claimed || t.claimedBy != workerId) {
      throw Exception('Task not claimed by you.');
    }
    t.submissionNote = submissionNote;
    t.status = TaskStatus.submitted;
  }

  void approveWork({required String taskId, required String posterId}) {
    final t = tasks.firstWhere((e) => e.id == taskId);
    if (t.posterId != posterId || t.status != TaskStatus.submitted) {
      throw Exception('Not eligible to approve.');
    }
    final worker = users[t.claimedBy]!;
    worker.coins += t.escrow;
    worker.earned += t.escrow;

    ledger.add(LedgerEntry(
      id: 'l_${DateTime.now().millisecondsSinceEpoch}',
      userId: worker.id,
      delta: t.escrow,
      note: 'Payout for "${t.title}"',
      at: DateTime.now(),
    ));

    t.escrow = 0;
    t.status = TaskStatus.approved;
  }

  void rejectWork({required String taskId, required String posterId, String? reason}) {
    final t = tasks.firstWhere((e) => e.id == taskId);
    if (t.posterId != posterId || t.status != TaskStatus.submitted) {
      throw Exception('Not eligible to reject.');
    }
    final poster = users[posterId]!;
    poster.coins += t.escrow;

    ledger.add(LedgerEntry(
      id: 'l_${DateTime.now().millisecondsSinceEpoch}',
      userId: poster.id,
      delta: t.escrow,
      note: 'Refund on reject "${t.title}"${reason != null ? " ($reason)" : ""}',
      at: DateTime.now(),
    ));

    t.escrow = 0;
    t.status = TaskStatus.rejected;
  }

  void addCoins({required String userId, required int amount}) {
    final u = users[userId]!;
    u.coins += amount;
    ledger.add(LedgerEntry(
      id: 'l_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      delta: amount,
      note: 'Add Coins (mock top-up)',
      at: DateTime.now(),
    ));
  }
}

/// ---------------- Login ----------------

class LoginScreen extends StatefulWidget {
  final void Function(User user) onLogin;
  const LoginScreen({Key? key, required this.onLogin}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final name = TextEditingController();

  void _loginAs(String role) {
    final n = name.text.trim().isEmpty ? role : name.text.trim();
    final u = User(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      name: n,
      avatar: _avatar(n),
      coins: 120,
    );
    widget.onLogin(u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('TaskBazaar',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Post micro-tasks. Get work. Earn coins.'),
              const SizedBox(height: 24),
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Your name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _loginAs('Poster'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Login'),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              const Center(
                child: Text('MVP • Single file • No backend',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------- Home Shell ----------------

class HomeShell extends StatefulWidget {
  final AppState state;
  final VoidCallback onLogout;
  const HomeShell({Key? key, required this.state, required this.onLogout})
      : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  String q = '';

  @override
  Widget build(BuildContext context) {
    final u = widget.state.currentUser!;
    final tabs = [
      BrowseTab(state: widget.state, query: q, onSearch: (v) => setState(() => q = v)),
      PostTaskTab(state: widget.state, onChange: () => setState(() {})),
      WalletTab(state: widget.state, onChange: () => setState(() {})),
      ProfileTab(state: widget.state, onLogout: widget.onLogout),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('TaskBazaar'),
        actions: [
          IconButton(
            onPressed: () => _showAdmin(context, widget.state, () => setState(() {})),
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Admin (platform revenue)',
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('Coins: ${u.coins}')),
          )
        ],
      ),
      body: tabs[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.add_box_outlined), label: 'Post'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// ---------------- Browse Tab ----------------

class BrowseTab extends StatelessWidget {
  final AppState state;
  final String query;
  final ValueChanged<String> onSearch;
  const BrowseTab({Key? key, required this.state, required this.query, required this.onSearch}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final myId = state.currentUser!.id;
    final list = state.tasks.where((t) {
      final text = '${t.title} ${t.description} ${t.tags}'.toLowerCase();
      return query.trim().isEmpty ? true : text.contains(query.trim().toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search: design, excel, audio…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No tasks found'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final t = list[i];
                    final poster = state.users[t.posterId];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            CircleAvatar(backgroundImage: NetworkImage(poster?.avatar ?? _avatar('x'))),
                            const SizedBox(width: 10),
                            Expanded(child: Text(poster?.name ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600))),
                            _taskChip(t.status),
                          ]),
                          const SizedBox(height: 8),
                          Text(t.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(t.description),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, children: t.tags.split(',').map((e) => Chip(label: Text(e.trim()))).toList()),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.monetization_on_outlined, size: 20),
                            const SizedBox(width: 6),
                            Text('Bounty: ${t.bounty}  •  Fee: ${t.platformFee}  •  Escrow: ${t.escrow}'),
                            const Spacer(),
                            if (t.status == TaskStatus.open)
                              FilledButton(
                                onPressed: () {
                                  try {
                                    state.claimTask(taskId: t.id, workerId: myId);
                                    _toast(c, 'Task claimed!');
                                  } catch (e) {
                                    _toast(c, '$e');
                                  }
                                },
                                child: const Text('Claim'),
                              ),
                            if (t.status == TaskStatus.claimed && t.claimedBy == myId)
                              FilledButton.tonal(
                                onPressed: () => _submitDialog(c, t, state, myId),
                                child: const Text('Submit'),
                              ),
                            if (t.status == TaskStatus.submitted && t.claimedBy == myId)
                              const Text('Waiting approval…'),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _taskChip(TaskStatus s) {
    String text = 'Open';
    switch (s) {
      case TaskStatus.open:
        text = 'Open';
        break;
      case TaskStatus.claimed:
        text = 'Claimed';
        break;
      case TaskStatus.submitted:
        text = 'Submitted';
        break;
      case TaskStatus.approved:
        text = 'Approved';
        break;
      case TaskStatus.rejected:
        text = 'Rejected';
        break;
    }
    return Chip(label: Text(text));
  }

  void _submitDialog(BuildContext context, TaskItem t, AppState state, String myId) {
    final proof = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit Work'),
        content: TextField(
          controller: proof,
          decoration: const InputDecoration(
            hintText: 'Proof / URL / Notes',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              try {
                state.submitWork(taskId: t.id, workerId: myId, submissionNote: proof.text.trim());
                Navigator.pop(c);
                _toast(context, 'Submitted!');
              } catch (e) {
                _toast(context, '$e');
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Post Task Tab ----------------

class PostTaskTab extends StatefulWidget {
  final AppState state;
  final VoidCallback onChange;
  const PostTaskTab({Key? key, required this.state, required this.onChange}) : super(key: key);

  @override
  State<PostTaskTab> createState() => _PostTaskTabState();
}

class _PostTaskTabState extends State<PostTaskTab> {
  final title = TextEditingController();
  final desc = TextEditingController();
  final tags = TextEditingController();
  final bounty = TextEditingController(text: '50');

  @override
  Widget build(BuildContext context) {
    final u = widget.state.currentUser!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        const Text('Create a Task', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: desc,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: tags,
          decoration: const InputDecoration(labelText: 'Tags (comma separated)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: bounty,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bounty (coins)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Post Task'),
          onPressed: () {
            final b = int.tryParse(bount
