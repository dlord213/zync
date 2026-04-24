import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/activity_log.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path = '';

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final Directory appSupportDir = await getApplicationSupportDirectory();
      path = join(appSupportDir.path, 'activity_log_db.db');
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'activity_log_db.db');
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE activity_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fileName TEXT,
        targetDeviceName TEXT,
        type TEXT,
        timestamp INTEGER
      )
    ''');
    
    // Insert mock data right away as previously requested
    final now = DateTime.now().millisecondsSinceEpoch;
    final mockEntries = [
      {'fileName': 'presentation.pdf', 'targetDeviceName': 'Alice Laptop', 'type': 'sent', 'timestamp': now - 100000},
      {'fileName': 'holiday_photo.jpg', 'targetDeviceName': 'Bob Phone', 'type': 'received', 'timestamp': now - 200000},
      {'fileName': 'document.docx', 'targetDeviceName': 'Alice Laptop', 'type': 'sent', 'timestamp': now - 300000},
      {'fileName': 'video.mp4', 'targetDeviceName': 'Charlie Mac', 'type': 'received', 'timestamp': now - 400000},
      {'fileName': 'notes.txt', 'targetDeviceName': 'Bob Phone', 'type': 'sent', 'timestamp': now - 500000},
      {'fileName': 'archive.zip', 'targetDeviceName': 'Charlie Mac', 'type': 'received', 'timestamp': now - 600000},
      {'fileName': 'report.pdf', 'targetDeviceName': 'Alice Laptop', 'type': 'sent', 'timestamp': now - 700000},
      {'fileName': 'music.mp3', 'targetDeviceName': 'Bob Phone', 'type': 'received', 'timestamp': now - 800000},
      {'fileName': 'code.dart', 'targetDeviceName': 'Charlie Mac', 'type': 'sent', 'timestamp': now - 900000},
      {'fileName': 'backup.tar', 'targetDeviceName': 'Alice Laptop', 'type': 'received', 'timestamp': now - 1000000},
      {'fileName': 'design.fig', 'targetDeviceName': 'Charlie Mac', 'type': 'sent', 'timestamp': now - 1100000},
      {'fileName': 'receipt.pdf', 'targetDeviceName': 'Bob Phone', 'type': 'received', 'timestamp': now - 1200000},
    ];

    for (var entry in mockEntries) {
      await db.insert('activity_log', entry);
    }
  }

  Future<List<ActivityLog>> getLogs({int? limit}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'activity_log',
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return ActivityLog.fromMap(maps[i]);
    });
  }

  Future<void> insertLog(ActivityLog log) async {
    final db = await database;
    await db.insert(
      'activity_log',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
