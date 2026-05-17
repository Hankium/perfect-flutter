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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

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
