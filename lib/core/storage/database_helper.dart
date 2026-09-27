import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/pdf_file.dart';
import '../../models/bookmark.dart';
import '../../models/annotation_meta.dart';
import '../../models/tool_usage_stat.dart';
import '../../models/ocr_cache_entry.dart';
import '../../models/study_item.dart';
import '../../models/study_session.dart';
import '../../models/semantic_chunk.dart';
import '../../models/exam_session.dart';
import '../../models/pdf_version.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('offline_pdf_reader.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pdf_index (
        path TEXT PRIMARY KEY,
        doc_id TEXT,
        name TEXT NOT NULL,
        size_bytes INTEGER,
        modified_at INTEGER,
        page_count INTEGER,
        is_favorite INTEGER DEFAULT 0,
        last_opened_at INTEGER,
        extracted_text TEXT,
        last_opened_page INTEGER DEFAULT 1,
        reading_progress REAL DEFAULT 0.0,
        reading_time INTEGER DEFAULT 0,
        completed INTEGER DEFAULT 0,
        folder TEXT,
        tags TEXT,
        source_type TEXT DEFAULT 'imported',
        created_at INTEGER,
        scan_created_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        label TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notes_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        note_text TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tool_usage (
        tool_name TEXT PRIMARY KEY,
        use_count INTEGER DEFAULT 0,
        last_used_at INTEGER
      )
    ''');

    await _createPhase2Tables(db);
    await _createPhase3Tables(db);
    await _createPhase4Tables(db);
    await _createIndexes(db);

    final tools = ['merge', 'split', 'delete_pages', 'scan', 'ocr', 'compare', 'compress', 'encrypt', 'metadata'];
    for (final tool in tools) {
      await db.insert(
        'tool_usage',
        {'tool_name': tool, 'use_count': 0, 'last_used_at': null},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bookmarks_file_path ON bookmarks(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_file_path ON notes_index(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ocr_cache_file_path ON ocr_cache(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_study_topics_file_path ON study_topics(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_flashcards_file_path ON flashcards(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_study_questions_file_path ON study_questions(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_study_sessions_file_path ON study_sessions(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_semantic_chunks_file_path ON semantic_chunks(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_exam_sessions_file_path ON exam_sessions(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pdf_versions_doc_id ON pdf_versions(doc_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pdf_index_favorite ON pdf_index(is_favorite)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pdf_index_last_opened ON pdf_index(last_opened_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pdf_index_source_type ON pdf_index(source_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pdf_index_scan_created ON pdf_index(scan_created_at)');
  }

  Future<void> _createPhase2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ocr_cache (
        file_path TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        extracted_text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        hash TEXT,
        PRIMARY KEY (file_path, page_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_topics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        title TEXT NOT NULL,
        start_page INTEGER DEFAULT 1,
        end_page INTEGER DEFAULT 1,
        keywords TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        page_number INTEGER DEFAULT 1,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        topic TEXT,
        status INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        page_number INTEGER DEFAULT 1,
        question_type TEXT NOT NULL,
        question TEXT NOT NULL,
        option_a TEXT,
        option_b TEXT,
        option_c TEXT,
        option_d TEXT,
        correct_answer TEXT NOT NULL,
        explanation TEXT,
        marks INTEGER DEFAULT 1,
        topic TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        duration_seconds INTEGER DEFAULT 0,
        questions_attempted INTEGER DEFAULT 0,
        correct_count INTEGER DEFAULT 0,
        accuracy_pct REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        question_id INTEGER NOT NULL,
        user_answer TEXT,
        is_correct INTEGER DEFAULT 0,
        timestamp INTEGER NOT NULL,
        topic TEXT
      )
    ''');
  }

  Future<void> _createPhase3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_cache (
        cache_key TEXT PRIMARY KEY,
        response TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        file_path TEXT,
        model_version TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS semantic_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        chunk_text TEXT NOT NULL,
        vector_data TEXT NOT NULL,
        keywords TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        ai_title TEXT,
        ai_explanation TEXT,
        key_points TEXT,
        important_terms TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        topic TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        num_questions INTEGER DEFAULT 10,
        score_pct REAL DEFAULT 0.0,
        duration_seconds INTEGER DEFAULT 0,
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createPhase4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pdf_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        source_operation TEXT NOT NULL,
        hash TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    Future<void> safeAddColumn(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column may already exist, ignore duplicate column error safely
      }
    }

    if (oldVersion < 2) {
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN last_opened_page INTEGER DEFAULT 1;');
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN reading_progress REAL DEFAULT 0.0;');
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN reading_time INTEGER DEFAULT 0;');
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN completed INTEGER DEFAULT 0;');
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN folder TEXT;');
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN tags TEXT;');
    }
    if (oldVersion < 3) {
      await _createPhase2Tables(db);
    }
    if (oldVersion < 4) {
      await _createPhase3Tables(db);
    }
    if (oldVersion < 5) {
      await _createPhase4Tables(db);
    }
    if (oldVersion < 6) {
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN doc_id TEXT;');
      try {
        await db.execute('UPDATE pdf_index SET doc_id = path WHERE doc_id IS NULL;');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      await safeAddColumn("ALTER TABLE pdf_index ADD COLUMN source_type TEXT DEFAULT 'imported';");
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN created_at INTEGER;');
      await safeAddColumn('ALTER TABLE pdf_index ADD COLUMN scan_created_at INTEGER;');
    }
    // Always ensure indexes exist after any upgrade
    await _createIndexes(db);
  }

  // --- PDF Index Operations ---
  Future<void> upsertPdfFile(PdfFile file) async {
    final db = await instance.database;
    await db.insert('pdf_index', file.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> bulkUpsertPdfFiles(List<PdfFile> files) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final f in files) {
      batch.insert('pdf_index', f.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<PdfFile?> getPdfFile(String path) async {
    final db = await instance.database;
    final maps = await db.query('pdf_index', where: 'path = ?', whereArgs: [path], limit: 1);
    if (maps.isNotEmpty) return PdfFile.fromMap(maps.first);
    return null;
  }

  Future<bool> renamePdfFile({
    required String oldPath,
    required String newPath,
    required String newName,
  }) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      final maps = await txn.query('pdf_index', where: 'path = ?', whereArgs: [oldPath], limit: 1);
      if (maps.isEmpty) return false;

      final existing = maps.first;
      final updatedMap = Map<String, dynamic>.from(existing);
      updatedMap['path'] = newPath;
      updatedMap['name'] = newName;
      updatedMap['modified_at'] = DateTime.now().millisecondsSinceEpoch;

      await txn.insert('pdf_index', updatedMap, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('pdf_index', where: 'path = ?', whereArgs: [oldPath]);

      await txn.update('bookmarks', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('notes_index', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('ocr_cache', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('study_topics', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('flashcards', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('study_questions', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('study_sessions', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('semantic_chunks', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('ai_cache', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('exam_sessions', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);
      await txn.update('pdf_versions', {'file_path': newPath}, where: 'file_path = ?', whereArgs: [oldPath]);

      return true;
    });
  }

  Future<void> deletePdfFileFromIndex(String path) async {
    final db = await instance.database;
    final maps = await db.query('pdf_index', columns: ['doc_id'], where: 'path = ?', whereArgs: [path]);
    final docId = maps.isNotEmpty ? maps.first['doc_id'] as String? : null;

    await db.transaction((txn) async {
      await txn.delete('bookmarks', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('notes_index', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('ocr_cache', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('study_topics', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('flashcards', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('study_questions', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('study_sessions', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('semantic_chunks', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('ai_cache', where: 'file_path = ?', whereArgs: [path]);
      await txn.delete('exam_sessions', where: 'file_path = ?', whereArgs: [path]);
      if (docId != null) {
        await txn.delete('pdf_versions', where: 'doc_id = ?', whereArgs: [docId]);
      } else {
        await txn.delete('pdf_versions', where: 'doc_id = ?', whereArgs: [path]);
      }
      await txn.delete('pdf_index', where: 'path = ?', whereArgs: [path]);
    });
  }

  Future<List<PdfFile>> getAllPdfFiles() async {
    final db = await instance.database;
    final maps = await db.query('pdf_index', orderBy: 'name ASC');
    return maps.map((m) => PdfFile.fromMap(m)).toList();
  }

  Future<List<PdfFile>> getRecentScannedPdfFiles({int limit = 10}) async {
    final db = await instance.database;
    final maps = await db.query(
      'pdf_index',
      where: "source_type = 'scanned' OR scan_created_at IS NOT NULL",
      orderBy: 'COALESCE(scan_created_at, created_at, modified_at) DESC',
      limit: limit,
    );
    return maps.map((m) => PdfFile.fromMap(m)).toList();
  }

  Future<List<PdfFile>> getRecentlyOpenedPdfFiles({int limit = 10}) async {
    final db = await instance.database;
    final maps = await db.query(
      'pdf_index',
      where: 'last_opened_at IS NOT NULL',
      orderBy: 'last_opened_at DESC',
      limit: limit,
    );
    return maps.map((m) => PdfFile.fromMap(m)).toList();
  }

  Future<List<PdfFile>> getFavoritePdfFiles() async {
    final db = await instance.database;
    final maps = await db.query('pdf_index', where: 'is_favorite = 1', orderBy: 'name ASC');
    return maps.map((m) => PdfFile.fromMap(m)).toList();
  }

  Future<void> toggleFavorite(String path, bool isFavorite) async {
    final db = await instance.database;
    await db.update('pdf_index', {'is_favorite': isFavorite ? 1 : 0}, where: 'path = ?', whereArgs: [path]);
  }

  Future<void> updateLastOpened(String path) async {
    final db = await instance.database;
    await db.update(
      'pdf_index',
      {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  Future<void> updateReadingProgress(
    String path, {
    required int page,
    required double progress,
    required bool completed,
  }) async {
    final db = await instance.database;
    await db.update(
      'pdf_index',
      {
        'last_opened_page': page,
        'reading_progress': progress,
        'completed': completed ? 1 : 0,
        'last_opened_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  Future<void> addReadingTime(String path, int additionalSeconds) async {
    if (additionalSeconds <= 0) return;
    final db = await instance.database;
    await db.rawUpdate('''
      UPDATE pdf_index
      SET reading_time = COALESCE(reading_time, 0) + ?
      WHERE path = ?
    ''', [additionalSeconds, path]);
  }

  Future<void> updateExtractedText(String path, String extractedText) async {
    final db = await instance.database;
    await db.update('pdf_index', {'extracted_text': extractedText}, where: 'path = ?', whereArgs: [path]);
  }

  Future<List<PdfFile>> searchPdfFiles(String query, {bool searchInside = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final db = await instance.database;
    final exact = trimmed;
    final startsWith = '$trimmed%';
    final contains = '%$trimmed%';

    if (searchInside) {
      const sql = '''
        SELECT *,
          CASE
            WHEN LOWER(name) = LOWER(?) THEN 1
            WHEN LOWER(name) LIKE LOWER(?) THEN 2
            WHEN LOWER(name) LIKE LOWER(?) THEN 3
            WHEN (folder IS NOT NULL AND LOWER(folder) LIKE LOWER(?)) OR LOWER(path) LIKE LOWER(?) THEN 4
            ELSE 5
          END AS search_rank
        FROM pdf_index
        WHERE LOWER(name) LIKE LOWER(?)
           OR (folder IS NOT NULL AND LOWER(folder) LIKE LOWER(?))
           OR LOWER(path) LIKE LOWER(?)
           OR (extracted_text IS NOT NULL AND LOWER(extracted_text) LIKE LOWER(?))
        ORDER BY search_rank ASC, modified_at DESC, name ASC
      ''';
      final maps = await db.rawQuery(sql, [
        exact, startsWith, contains, contains, contains, // for CASE
        contains, contains, contains, contains, // for WHERE
      ]);
      return maps.map((m) => PdfFile.fromMap(m)).toList();
    } else {
      const sql = '''
        SELECT *,
          CASE
            WHEN LOWER(name) = LOWER(?) THEN 1
            WHEN LOWER(name) LIKE LOWER(?) THEN 2
            WHEN LOWER(name) LIKE LOWER(?) THEN 3
            ELSE 4
          END AS search_rank
        FROM pdf_index
        WHERE LOWER(name) LIKE LOWER(?)
           OR (folder IS NOT NULL AND LOWER(folder) LIKE LOWER(?))
           OR LOWER(path) LIKE LOWER(?)
        ORDER BY search_rank ASC, modified_at DESC, name ASC
      ''';
      final maps = await db.rawQuery(sql, [
        exact, startsWith, contains, // for CASE
        contains, contains, contains, // for WHERE
      ]);
      return maps.map((m) => PdfFile.fromMap(m)).toList();
    }
  }

  Future<List<PdfFile>> getMostOpenedFiles({int limit = 5}) async {
    final db = await instance.database;
    final maps = await db.query(
      'pdf_index',
      where: 'last_opened_at IS NOT NULL',
      orderBy: 'last_opened_at DESC',
      limit: limit,
    );
    return maps.map((m) => PdfFile.fromMap(m)).toList();
  }

  // --- Bookmarks Operations ---
  Future<int> addBookmark(Bookmark bookmark) async {
    final db = await instance.database;
    return await db.insert('bookmarks', bookmark.toMap());
  }

  Future<void> updateBookmarkLabel(int id, String newLabel) async {
    final db = await instance.database;
    await db.update('bookmarks', {'label': newLabel}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bookmark>> getBookmarksForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('bookmarks', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'page_number ASC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  Future<void> deleteBookmark(int id) async {
    final db = await instance.database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // --- Notes Operations ---
  Future<int> addNote(PdfNote note) async {
    final db = await instance.database;
    return await db.insert('notes_index', note.toMap());
  }

  Future<List<PdfNote>> getNotesForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('notes_index', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'page_number ASC');
    return maps.map((m) => PdfNote.fromMap(m)).toList();
  }

  Future<void> deleteNote(int id) async {
    final db = await instance.database;
    await db.delete('notes_index', where: 'id = ?', whereArgs: [id]);
  }

  // --- Tool Usage Operations ---
  Future<void> incrementToolUsage(String toolName) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate('''
      UPDATE tool_usage
      SET use_count = use_count + 1, last_used_at = ?
      WHERE tool_name = ?
    ''', [now, toolName]);
  }

  Future<List<ToolUsageStat>> getToolUsageStats() async {
    final db = await instance.database;
    final maps = await db.query('tool_usage');
    return maps.map((m) => ToolUsageStat.fromMap(m)).toList();
  }

  // --- Phase 2: OCR Cache Operations ---
  Future<void> upsertOcrCacheEntry(OcrCacheEntry entry) async {
    final db = await instance.database;
    await db.insert('ocr_cache', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<OcrCacheEntry?> getOcrCacheEntry(String filePath, int pageNumber) async {
    final db = await instance.database;
    final maps = await db.query('ocr_cache', where: 'file_path = ? AND page_number = ?', whereArgs: [filePath, pageNumber], limit: 1);
    if (maps.isNotEmpty) return OcrCacheEntry.fromMap(maps.first);
    return null;
  }

  Future<List<OcrCacheEntry>> getOcrCacheForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('ocr_cache', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'page_number ASC');
    return maps.map((m) => OcrCacheEntry.fromMap(m)).toList();
  }

  Future<void> invalidateOcrCacheForFile(String filePath) async {
    final db = await instance.database;
    await db.delete('ocr_cache', where: 'file_path = ?', whereArgs: [filePath]);
  }

  // --- Phase 2: Study Items & Flashcards Operations ---
  Future<void> saveStudyTopics(List<StudyTopic> topics) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final t in topics) {
      batch.insert('study_topics', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<StudyTopic>> getStudyTopics(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('study_topics', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'start_page ASC');
    return maps.map((m) => StudyTopic.fromMap(m)).toList();
  }

  Future<void> saveFlashcards(List<Flashcard> cards) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final c in cards) {
      batch.insert('flashcards', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Flashcard>> getFlashcards(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('flashcards', where: 'file_path = ?', whereArgs: [filePath]);
    return maps.map((m) => Flashcard.fromMap(m)).toList();
  }

  Future<void> updateFlashcardStatus(int id, int status) async {
    final db = await instance.database;
    await db.update('flashcards', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveStudyQuestions(List<StudyQuestion> questions) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final q in questions) {
      batch.insert('study_questions', q.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<StudyQuestion>> getStudyQuestions(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('study_questions', where: 'file_path = ?', whereArgs: [filePath]);
    return maps.map((m) => StudyQuestion.fromMap(m)).toList();
  }

  Future<int> saveStudySession(StudySession session) async {
    final db = await instance.database;
    return await db.insert('study_sessions', session.toMap());
  }

  Future<void> recordStudyAttempt(StudyAttempt attempt) async {
    final db = await instance.database;
    await db.insert('study_attempts', attempt.toMap());
  }

  Future<List<StudySession>> getStudySessionsForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('study_sessions', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'start_time DESC');
    return maps.map((m) => StudySession.fromMap(m)).toList();
  }

  Future<Map<String, double>> getTopicAccuracyForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.rawQuery('''
      SELECT topic, COUNT(*) as total, SUM(is_correct) as correct
      FROM study_attempts
      WHERE topic IS NOT NULL AND topic != ''
      GROUP BY topic
      HAVING total >= 3
    ''');

    final Map<String, double> result = {};
    for (final m in maps) {
      final topic = m['topic'] as String;
      final total = m['total'] as int;
      final correct = m['correct'] as int;
      result[topic] = (correct / total);
    }
    return result;
  }

  // --- Phase 3: AI Cache, Chunks & Exam Operations ---
  Future<void> cacheAiResponse(String cacheKey, String response, String filePath) async {
    final db = await instance.database;
    await db.insert(
      'ai_cache',
      {
        'cache_key': cacheKey,
        'response': response,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'file_path': filePath,
        'model_version': '1.0.0_local',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getCachedAiResponse(String cacheKey) async {
    final db = await instance.database;
    final maps = await db.query('ai_cache', where: 'cache_key = ?', whereArgs: [cacheKey], limit: 1);
    if (maps.isNotEmpty) return maps.first['response'] as String;
    return null;
  }

  Future<void> saveSemanticChunks(List<SemanticChunk> chunks) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final c in chunks) {
      batch.insert('semantic_chunks', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<SemanticChunk>> getSemanticChunksForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('semantic_chunks', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'page_number ASC');
    return maps.map((m) => SemanticChunk.fromMap(m)).toList();
  }

  Future<void> saveExamSession(ExamSession exam) async {
    final db = await instance.database;
    await db.insert('exam_sessions', exam.toMap());
  }

  Future<List<ExamSession>> getExamSessionsForFile(String filePath) async {
    final db = await instance.database;
    final maps = await db.query('exam_sessions', where: 'file_path = ?', whereArgs: [filePath], orderBy: 'timestamp DESC');
    return maps.map((m) => ExamSession.fromMap(m)).toList();
  }

  // --- Phase 4: Version History Operations ---
  Future<int> addPdfVersion(PdfVersion version) async {
    final db = await instance.database;
    return await db.insert('pdf_versions', version.toMap());
  }

  Future<List<PdfVersion>> getVersionsForDocument(String docId) async {
    final db = await instance.database;
    final maps = await db.query('pdf_versions', where: 'doc_id = ?', whereArgs: [docId], orderBy: 'version_number DESC');
    return maps.map((m) => PdfVersion.fromMap(m)).toList();
  }

  Future<void> deletePdfVersion(int id) async {
    final db = await instance.database;
    await db.delete('pdf_versions', where: 'id = ?', whereArgs: [id]);
  }

  // --- AI Notes Operations ---
  Future<int> addAiNote({
    required int noteId,
    String? aiTitle,
    String? aiExplanation,
    String? keyPoints,
    String? importantTerms,
  }) async {
    final db = await instance.database;
    return await db.insert(
      'ai_notes',
      {
        'note_id': noteId,
        'ai_title': aiTitle,
        'ai_explanation': aiExplanation,
        'key_points': keyPoints,
        'important_terms': importantTerms,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getAiNoteForNote(int noteId) async {
    final db = await instance.database;
    final maps = await db.query(
      'ai_notes',
      where: 'note_id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> deleteAiNote(int noteId) async {
    final db = await instance.database;
    await db.delete('ai_notes', where: 'note_id = ?', whereArgs: [noteId]);
  }

  Future<void> clearOcrIndex() async {
    final db = await instance.database;
    await db.update('pdf_index', {'extracted_text': null});
    await db.delete('ocr_cache');
  }

  Future<void> clearDatabase() async {
    final db = await instance.database;
    await db.delete('pdf_index');
    await db.delete('bookmarks');
    await db.delete('notes_index');
    await db.delete('ocr_cache');
    await db.delete('study_topics');
    await db.delete('flashcards');
    await db.delete('study_questions');
    await db.delete('study_sessions');
    await db.delete('study_attempts');
    await db.delete('ai_cache');
    await db.delete('semantic_chunks');
    await db.delete('ai_notes');
    await db.delete('exam_sessions');
    await db.delete('pdf_versions');
  }
}
