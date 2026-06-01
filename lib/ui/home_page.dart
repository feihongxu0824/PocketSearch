import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:pocketsearch/services/clip_service.dart';
import 'package:pocketsearch/services/index_service.dart';
import 'package:pocketsearch/services/search_service.dart';
import 'package:pocketsearch/services/settings_service.dart';
import 'package:pocketsearch/services/text_search_service.dart';
import 'package:pocketsearch/services/tokenizer.dart';
import 'package:pocketsearch/services/vector_store.dart';
import 'package:pocketsearch/ui/settings_page.dart';
import 'package:pocketsearch/ui/widgets/index_status_bar.dart';
import 'package:pocketsearch/ui/widgets/search_results_view.dart';
import 'package:pocketsearch/ui/widgets/suggestion_chips.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  ClipService? _clipService;
  VectorStore? _vectorStore;
  late Tokenizer _tokenizer;
  IndexService? _indexService;
  late TextSearchService _textSearchService;
  late SearchService _searchService;
  late SettingsService _settings;

  bool _isInitialized = false;
  bool _isSearching = false;
  bool _isSyncingSources = false;
  SearchResponse? _searchResponse;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;
    if (state == AppLifecycleState.detached) {
      _vectorStore?.dispose();
    }
  }

  Future<void> _initializeServices() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Load model data from Flutter assets
      final imageModelData = await _loadRequiredModel(
        'assets/models/mobileclip_s1_image_encoder.mnn',
      );
      final textModelData = await _loadRequiredModel(
        'assets/models/mobileclip_s1_text_encoder.mnn',
      );

      // Initialize CLIP service with model buffers
      final clipService = ClipService.instance;
      await clipService.initialize(
        imageModelData: imageModelData.buffer.asUint8List(),
        textModelData: textModelData.buffer.asUint8List(),
      );
      _clipService = clipService;

      // Initialize tokenizer
      _tokenizer = Tokenizer();
      await _tokenizer.load('assets/tokenizer/bpe_vocab.json');

      // Initialize vector store
      final vectorStore = VectorStore();
      // ignore: unused_local_variable — migration triggers full re-index via startIndexing()
      final migrated = await vectorStore.initialize(
        '${appDir.path}/zvec_photos',
      );
      _vectorStore = vectorStore;

      // Load persisted user settings (LLM rewriter config). When the
      // toggle is OFF or the API key is missing, buildRewriter()
      // returns the no-op IdentityQueryRewriter so the offline path
      // is byte-for-byte identical to before this feature existed.
      _settings = SettingsService();
      await _settings.load();
      _settings.addListener(_onSettingsChanged);

      // Initialize services
      final indexService = IndexService(clip: clipService, store: vectorStore);
      _indexService = indexService;
      _textSearchService = TextSearchService();
      _searchService = SearchService(
        clip: clipService,
        store: vectorStore,
        tokenizer: _tokenizer,
        rewriter: _settings.buildRewriter(),
      );

      setState(() => _isInitialized = true);

      // Start background indexing
      indexService.startIndexing();
      unawaited(_syncPersonalSources());
    } catch (e) {
      setState(() => _initError = e.toString());
    }
  }

  Future<ByteData> _loadRequiredModel(String assetPath) async {
    try {
      return await rootBundle.load(assetPath);
    } on FlutterError catch (_) {
      throw StateError(
        'Missing required model asset: $assetPath\n\n'
        'Run these commands before building:\n'
        '  python scripts/export_onnx.py\n'
        '  bash scripts/convert_mnn.sh\n'
        '  bash scripts/check_models.sh\n\n'
        'See README.md -> Model Preparation for details.',
      );
    }
  }

  void _onSettingsChanged() {
    if (!_isInitialized) return;
    _searchService.updateRewriter(_settings.buildRewriter());
  }

  Future<void> _performSearch(String query) async {
    if (!_isInitialized || query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    final photoResponse = await _searchService.search(query.trim());
    final textResults = _textSearchService.search(query.trim());
    final response = SearchResponse(
      results: photoResponse.results,
      textResults: textResults,
      queryTimeMs: photoResponse.queryTimeMs,
      rewriteTimeMs: photoResponse.rewriteTimeMs,
      totalPhotos: photoResponse.totalPhotos,
      rewrite: photoResponse.rewrite,
    );

    if (!mounted) return;
    setState(() {
      _searchResponse = response;
      _isSearching = false;
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsPage(settings: _settings)),
    );
  }

  Future<void> _syncPersonalSources() async {
    if (!_isInitialized || _isSyncingSources) return;
    setState(() => _isSyncingSources = true);
    try {
      await _textSearchService.syncSystemSources();
    } finally {
      if (mounted) setState(() => _isSyncingSources = false);
    }
  }

  Future<void> _importFiles() async {
    if (!_isInitialized || _isSyncingSources) return;
    setState(() => _isSyncingSources = true);
    try {
      await _textSearchService.importFiles();
    } finally {
      if (mounted) setState(() => _isSyncingSources = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _focusNode.dispose();
    if (_isInitialized) {
      _settings.removeListener(_onSettingsChanged);
    }
    _indexService?.dispose();
    _vectorStore?.dispose();
    _clipService?.dispose();
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
            if (_isInitialized && _indexService != null)
              IndexStatusBar(indexService: _indexService!),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          Text(
            'PocketSearch',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Import text files',
            icon: Icon(
              Icons.drive_folder_upload_outlined,
              color: Colors.grey[400],
              size: 22,
            ),
            onPressed: _isInitialized && !_isSyncingSources
                ? _importFiles
                : null,
          ),
          IconButton(
            tooltip: 'Refresh personal sources',
            icon: _isSyncingSources
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey[400],
                    ),
                  )
                : Icon(Icons.sync_rounded, color: Colors.grey[400], size: 22),
            onPressed: _isInitialized && !_isSyncingSources
                ? _syncPersonalSources
                : null,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Icon(
              Icons.settings_outlined,
              color: Colors.grey[400],
              size: 22,
            ),
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
          hintText: 'Describe what you\'re looking for...',
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: Colors.grey[400]),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchResponse = null);
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: const Color(0xFFF2F2F7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: _performSearch,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTimingInfo() {
    final resp = _searchResponse!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Text(
        '${resp.results.length + resp.textResults.length} results \u00b7 '
        '${resp.queryTimeMs}ms',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[400],
          fontWeight: FontWeight.w400,
        ),
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
              Text(
                'Initialization failed:\n$_initError',
                textAlign: TextAlign.center,
              ),
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

    if (_searchResponse != null && _searchResponse!.hasResults) {
      return SearchResultsView(
        photoResults: _searchResponse!.results,
        textResults: _searchResponse!.textResults,
      );
    }

    if (_searchResponse != null && !_searchResponse!.hasResults) {
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
    return SuggestionChips(
      onTap: (query) {
        _searchController.text = query;
        _performSearch(query);
      },
    );
  }
}
