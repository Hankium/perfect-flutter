// Example app for perfect_flutter.
//
// The single `perfect_flutter` import below is the only code change required
// in a consuming app — it has no runtime effect, but it ensures the helper
// class is linked into the debug build so the DevTools panel can call it via
// the VM service. In release builds, tree-shaking removes everything.

import 'package:flutter/material.dart';
// ignore: unused_import, depend_on_referenced_packages
import 'package:perfect_flutter/perfect_flutter.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'perfect_flutter example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mock Home'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: CircleAvatar(child: Text('H')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Featured'),
          _FeatureCard(
            title: 'Pixel-perfect overlay',
            subtitle: 'Compare design to running app in DevTools.',
            color: Colors.indigo.shade100,
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            title: 'Zero widget wrapping',
            subtitle: 'Just one import at the top of main.dart. '
                'No runApp changes, no debug branches.',
            color: Colors.pink.shade100,
          ),
          const SizedBox(height: 24),
          _SectionHeader('Quick actions'),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickAction(icon: Icons.add_photo_alternate, label: 'Upload'),
              _QuickAction(icon: Icons.compare_arrows, label: 'Compare'),
              _QuickAction(icon: Icons.straighten, label: 'Measure'),
              _QuickAction(icon: Icons.bookmark_outline, label: 'Save'),
              _QuickAction(icon: Icons.share, label: 'Share'),
              _QuickAction(icon: Icons.history, label: 'History'),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader('Stats'),
          const Row(
            children: [
              Expanded(child: _StatTile(label: 'Imports', value: '1')),
              SizedBox(width: 12),
              Expanded(child: _StatTile(label: 'runApp edits', value: '0')),
              SizedBox(width: 12),
              Expanded(child: _StatTile(label: 'Tabs added', value: '1')),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader('Recent activity'),
          ..._activity.map(
            (a) => _ActivityTile(
              icon: a.icon,
              title: a.title,
              subtitle: a.subtitle,
              when: a.when,
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader('Tips'),
          _TipCard(
            title: 'Use opacity 0.5 to start',
            body:
                'Half-opacity makes it easy to spot drift between the design '
                'and the running screen. Tweak from there.',
          ),
          const SizedBox(height: 12),
          _TipCard(
            title: 'Toggle "Follow scroll" for long screens',
            body:
                'Designs that span multiple device heights need the overlay '
                'to scroll with content. The Display section in DevTools has '
                'a switch for this.',
          ),
          const SizedBox(height: 12),
          _TipCard(
            title: 'Flip H/V for mirror layouts',
            body:
                'RTL or symmetry checks: flip the overlay horizontally to '
                'verify your layout mirrors correctly.',
          ),
          const SizedBox(height: 24),
          _SectionHeader('Team'),
          ..._team.map(
            (m) => _ActivityTile(
              icon: Icons.person_outline,
              title: m.name,
              subtitle: m.role,
              when: m.location,
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader('FAQ'),
          ..._faq.map(
            (q) => _FaqTile(question: q.question, answer: q.answer),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'You\'ve reached the end.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Section helpers ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.when,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(child: Icon(icon, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(when, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(question, style: Theme.of(context).textTheme.titleSmall),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(answer),
          ),
        ],
      ),
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────

class _Activity {
  const _Activity({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.when,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String when;
}

const List<_Activity> _activity = [
  _Activity(
    icon: Icons.upload,
    title: 'Uploaded home_v3.png',
    subtitle: 'Replaced previous overlay',
    when: '2m',
  ),
  _Activity(
    icon: Icons.straighten,
    title: 'Adjusted offset',
    subtitle: 'X: 4 px · Y: -2 px',
    when: '5m',
  ),
  _Activity(
    icon: Icons.tune,
    title: 'Opacity set to 60%',
    subtitle: 'Easier scan for spacing drift',
    when: '7m',
  ),
  _Activity(
    icon: Icons.swap_horiz,
    title: 'Toggled horizontal flip',
    subtitle: 'Checking RTL mirror',
    when: '12m',
  ),
  _Activity(
    icon: Icons.zoom_out_map,
    title: 'Scaled to 1.10×',
    subtitle: 'Matching design at @3 export',
    when: '20m',
  ),
  _Activity(
    icon: Icons.bookmark_outline,
    title: 'Saved comparison',
    subtitle: 'Onboarding flow · screen 2',
    when: '34m',
  ),
  _Activity(
    icon: Icons.share,
    title: 'Shared snapshot',
    subtitle: 'To #design-review',
    when: '1h',
  ),
  _Activity(
    icon: Icons.history,
    title: 'Reverted overlay',
    subtitle: 'Back to home_v2.png',
    when: '2h',
  ),
];

class _TeamMember {
  const _TeamMember({
    required this.name,
    required this.role,
    required this.location,
  });
  final String name;
  final String role;
  final String location;
}

const List<_TeamMember> _team = [
  _TeamMember(name: 'Avery', role: 'Lead designer', location: 'Berlin'),
  _TeamMember(name: 'Bao', role: 'Mobile engineer', location: 'Singapore'),
  _TeamMember(name: 'Chen', role: 'PM', location: 'Vancouver'),
  _TeamMember(name: 'Devi', role: 'QA', location: 'Bengaluru'),
  _TeamMember(name: 'Erik', role: 'Frontend engineer', location: 'Stockholm'),
  _TeamMember(name: 'Fatima', role: 'Backend engineer', location: 'Cairo'),
];

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

const List<_FaqItem> _faq = [
  _FaqItem(
    question: 'Does perfect_flutter ship in release builds?',
    answer: 'No. The helper class is unreferenced from app code, so Flutter\'s '
        'release tree-shaking removes it entirely.',
  ),
  _FaqItem(
    question: 'Why do I need that one import?',
    answer: 'It links the helper into the debug build so DevTools can call '
        'it through the VM service. The import has no runtime effect.',
  ),
  _FaqItem(
    question: 'Why doesn\'t my IDE\'s "remove unused imports" leave it alone?',
    answer: 'It will try to remove it. Use the // ignore comment shown in the '
        'README so IDE actions skip it.',
  ),
  _FaqItem(
    question: 'Why is the overlay clipped at the bottom on long screens?',
    answer: 'The overlay is bounded by the viewport. Turn on "Follow scroll" '
        'in the Display section so the overlay translates with content as '
        'you scroll.',
  ),
  _FaqItem(
    question: 'Can I overlay multiple images at once?',
    answer: 'Not yet — multi-layer is on the roadmap (Sprint 5).',
  ),
];
