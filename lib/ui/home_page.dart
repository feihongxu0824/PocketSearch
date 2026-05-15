import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:zvec_photo_search/services/clip_service.dart';
import 'package:zvec_photo_search/services/index_service.dart';
import 'package:zvec_photo_search/services/search_service.dart';
import 'package:zvec_photo_search/services/settings_service.dart';
import 'package:zvec_photo_search/services/tokenizer.dart';
import 'package:zvec_photo_search/services/vector_store.dart';
import 'package:zvec_photo_search/ui/settings_page.dart';
import 'package:zvec_photo_search/ui/widgets/index_status_bar.dart';
import 'package:zvec_photo_search/ui/widgets/photo_grid.dart';
import 'package:zvec_photo_search/ui/widgets/suggestion_chips.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  late ClipService _clipService;
  late VectorStore _vectorStore;
  late Tokenizer _tokenizer;
  late IndexService _indexService;
  late SearchService _searchService;
  late SettingsService _settings;

  bool _isInitialized = false;
  bool _isSearching = false;
  SearchResponse? _searchResponse;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Load model data from Flutter assets
      final imageModelData = await rootBundle.load(
        'assets/models/mobileclip_s1_image_encoder.mnn',
      );
      final textModelData = await rootBundle.load(
        'assets/models/mobileclip_s1_text_encoder.mnn',
      );

      // Initialize CLIP service with model buffers
      _clipService = ClipService.instance;
      await _clipService.initialize(
        imageModelData: imageModelData.buffer.asUint8List(),
        textModelData: textModelData.buffer.asUint8List(),
      );

      // Initialize tokenizer
      _tokenizer = Tokenizer();
      await _tokenizer.load('assets/tokenizer/bpe_vocab.json');

      // Initialize vector store
      _vectorStore = VectorStore();
      // ignore: unused_local_variable — migration triggers full re-index via startIndexing()
      final migrated = await _vectorStore.initialize('${appDir.path}/zvec_photos');

      // Load persisted user settings (LLM rewriter config). When the
      // toggle is OFF or the API key is missing, buildRewriter()
      // returns the no-op IdentityQueryRewriter so the offline path
      // is byte-for-byte identical to before this feature existed.
      _settings = SettingsService();
      await _settings.load();
      _settings.addListener(_onSettingsChanged);

      // Initialize services
      _indexService = IndexService(clip: _clipService, store: _vectorStore);
      _searchService = SearchService(
        clip: _clipService,
        store: _vectorStore,
        tokenizer: _tokenizer,
        rewriter: _settings.buildRewriter(),
      );

      setState(() => _isInitialized = true);

      // Start background indexing
      _indexService.startIndexing();
    } catch (e) {
      setState(() => _initError = e.toString());
    }
  }

  void _onSettingsChanged() {
    if (!_isInitialized) return;
    _searchService.updateRewriter(_settings.buildRewriter());
  }

  Future<void> _performSearch(String query) async {
    if (!_isInitialized || query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    final response = await _searchService.search(query.trim());

    if (!mounted) return;
    setState(() {
      _searchResponse = response;
      _isSearching = false;
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(settings: _settings),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    if (_isInitialized) {
      _settings.removeListener(_onSettingsChanged);
    }
    _indexService.dispose();
    _vectorStore.dispose();
    _clipService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // App header
            _buildHeader(),
            // Search bar
            _buildSearchBar(),
            // Index status
            if (_isInitialized)
              IndexStatusBar(indexService: _indexService),
            // Search timing info
            if (_searchResponse != null) _buildTimingInfo(),
            // Results or suggestions
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Icon(
            Icons.image_search_rounded,
            size: 28,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(
            'Zvec Photo Search',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _isInitialized ? _openSettings : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        enabled: _isInitialized,
        decoration: InputDecoration(
          hintText: 'Describe what you are looking for...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchResponse = null);
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: _performSearch,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTimingInfo() {
    final resp = _searchResponse!;
    final rewrite = resp.rewrite;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: theme.colorScheme.tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Found ${resp.results.length} results from ${resp.totalPhotos} photos '
                  'in ${resp.queryTimeMs}ms',
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                ),
              ),
            ],
          ),
          if (rewrite.wasRewritten)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 18),
              child: Text(
                'LLM rewrote "${rewrite.original}" → "${rewrite.effectiveQuery}" '
                '(${resp.rewriteTimeMs}ms)',
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          if (rewrite.wasRewritten && rewrite.filters != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 18),
              child: Text(
                '🔍 ${rewrite.filters!.toDisplayString()}',
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
              ),
            )
          else if (rewrite.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 18),
              child: Text(
                'LLM rewrite failed (${rewrite.error}); used the original query.',
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Initialization failed:\n$_initError',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading models...'),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResponse != null && _searchResponse!.results.isNotEmpty) {
      return PhotoGrid(results: _searchResponse!.results);
    }

    if (_searchResponse != null && _searchResponse!.results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No matching photos found'),
          ],
        ),
      );
    }

    // Default: show suggestion chips
    return SuggestionChips(onTap: (query) {
      _searchController.text = query;
      _performSearch(query);
    });
  }
}
