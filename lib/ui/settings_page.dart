import 'package:flutter/material.dart';

import 'package:zvec_photo_search/services/settings_service.dart';

/// Settings page for the optional LLM-based query rewriter.
///
/// Three mutually-exclusive modes:
///   * Off    — fully offline, the CLIP encoder sees the raw query.
///   * Local  — on-device LLM via flutter_gemma. Zero network at
///              inference time; one-time model download required.
///   * Remote — OpenAI-compatible chat-completions endpoint. Sends only
///              the query text, never any photo / embedding.
///
/// See `docs/llm-query-rewriter.md` for the privacy / latency rationale.
class SettingsPage extends StatefulWidget {
  final SettingsService settings;

  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _modelCtrl = TextEditingController(text: s.model);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(context, 'LLM Query Rewriter (optional)'),
          const SizedBox(height: 4),
          Text(
            'Rewrites your natural-language query into a short English '
            'visual description that the on-device CLIP encoder can match. '
            'Choose Off to stay fully offline; Local for an on-device '
            'LLM (one-time download); Remote for an OpenAI-compatible API.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          RadioListTile<LlmMode>(
            value: LlmMode.off,
            groupValue: s.mode == LlmMode.local ? LlmMode.off : s.mode,
            onChanged: (v) => v != null ? s.setMode(v) : null,
            title: const Text('Off (fully offline)'),
            subtitle: const Text(
                'Recommended default. The CLIP encoder sees the raw query.'),
          ),
          RadioListTile<LlmMode>(
            value: LlmMode.remote,
            groupValue: s.mode == LlmMode.local ? LlmMode.off : s.mode,
            onChanged: (v) => v != null ? s.setMode(v) : null,
            title: const Text('Remote (OpenAI-compatible API)'),
            subtitle: const Text(
                'Sends only the query text \u2014 never photos or embeddings.'),
          ),
          if (s.mode == LlmMode.remote) ..._buildRemoteSection(context),
          const SizedBox(height: 24),
          Text(
            'Privacy: in every mode the photos, thumbnails, and vector '
            'embeddings always stay on the device. Only the search query '
            '(or, in Local mode, nothing at inference time) leaves it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Remote LLM section
  // ---------------------------------------------------------------------
  List<Widget> _buildRemoteSection(BuildContext context) {
    final s = widget.settings;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com/v1',
                border: OutlineInputBorder(),
                helperText:
                    'OpenAI-compatible endpoint. DeepSeek, Together, DashScope, Ollama, etc. supported.',
              ),
              onSubmitted: s.setBaseUrl,
              onEditingComplete: () => s.setBaseUrl(_baseUrlCtrl.text),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              onSubmitted: s.setApiKey,
              onEditingComplete: () => s.setApiKey(_apiKeyCtrl.text),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'gpt-4o-mini',
                border: OutlineInputBorder(),
                helperText:
                    'Any chat-completions model the endpoint exposes. Small / fast models recommended.',
              ),
              onSubmitted: s.setModel,
              onEditingComplete: () => s.setModel(_modelCtrl.text),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                s.setBaseUrl(_baseUrlCtrl.text);
                s.setApiKey(_apiKeyCtrl.text);
                s.setModel(_modelCtrl.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved.')),
                );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
            if (s.mode == LlmMode.remote && !s.remoteReady)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Missing API key — falling back to offline.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _sectionHeader(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      );
}
