import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart' as flutter hide Table; // Alias e hide
import 'package:http/http.dart' as http;

// Sqflite imports
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart';

// Drift imports
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

// Hive imports
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Isar imports
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

part 'main.g.dart';

// Model Class
class ApiItem {
  final int id;
  final String name;
  final String value;

  ApiItem({required this.id, required this.name, required this.value});

  factory ApiItem.fromJson(Map<String, dynamic> json) {
    return ApiItem(
      id: json['id'],
      name: json['name'],
      value: json['value'],
    );
  }
}

// Drift Setup
class Items extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Items])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  Future<void> insertItems(List<ApiItem> items) async {
    await batch((driftBatch) {
      driftBatch.insertAll(
        this.items,
        items
            .map(
              (item) => ItemsCompanion(
                id: Value(item.id),
                name: Value(item.name),
                value: Value(item.value),
              ),
            )
            .toList(),
      );
    });
  }

  Future<void> updateItems(List<ApiItem> items) async {
    await batch((driftBatch) {
      for (var item in items) {
        driftBatch.update(
          this.items,
          ItemsCompanion(
            name: Value(item.name),
            value: Value(item.value),
          ),
          where: (tbl) => tbl.id.equals(item.id),
        );
      }
    });
  }
}

// Hive Setup
@HiveType(typeId: 0)
class HiveItem extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String value;

  HiveItem({required this.id, required this.name, required this.value});
}

class HiveItemAdapter extends TypeAdapter<HiveItem> {
  @override
  final typeId = 0;

  @override
  HiveItem read(BinaryReader reader) {
    return HiveItem(
      id: reader.readInt(),
      name: reader.readString(),
      value: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, HiveItem obj) {
    writer.writeInt(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.value);
  }
}

// Isar Setup
@Collection()
class IsarItem {
  Id id = 0;

  late String name;

  late String value;
}

Future<void> main() async {
  flutter.WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(HiveItemAdapter());
  await Hive.openBox<HiveItem>('hive_items');

  // Initialize Isar
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [IsarItemSchema],
    directory: dir.path,
  );

  flutter.runApp(MyApp(isar: isar));
}

class MyApp extends flutter.StatelessWidget {
  final Isar isar;

  const MyApp({flutter.Key? key, required this.isar}) : super(key: key);

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.MaterialApp(
      title: 'Teste de Desempenho DB',
      theme: flutter.ThemeData(
        primarySwatch: flutter.Colors.blue,
      ),
      home: MyHomePage(isar: isar),
    );
  }
}

class MyHomePage extends flutter.StatefulWidget {
  final Isar isar;

  const MyHomePage({flutter.Key? key, required this.isar}) : super(key: key);

  @override
  flutter.State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends flutter.State<MyHomePage> {
  // Drift Database Instance
  late AppDatabase driftDb;

  // Sqflite Database Instance
  sqflite.Database? sqfliteDb;

  // Hive Box
  Box<HiveItem>? hiveBox;

  // Timings
  Map<String, String> timings = {};

  @override
  void initState() {
    super.initState();
    driftDb = AppDatabase();
    _initSqflite();
    _initHive();
  }

  Future<void> _initSqflite() async {
    final databasesPath = await sqflite.getDatabasesPath();
    final path = join(databasesPath, 'sqflite_test.db');

    sqfliteDb = await sqflite.openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY,
            name TEXT,
            value TEXT
          )
        ''');
      },
    );
  }

  Future<void> _initHive() async {
    hiveBox = Hive.box<HiveItem>('hive_items');
  }

  Future<List<ApiItem>> fetchItems() async {
    // Substitua pela URL da sua API real
    final response = await http.get(Uri.parse('https://api.exemplo.com/items'));

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => ApiItem.fromJson(json)).toList();
    } else {
      throw Exception('Falha ao carregar dados da API');
    }
  }

  // Sqflite Operations
  Future<void> populateSqflite() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      sqflite.Batch batch = sqfliteDb!.batch();
      for (var item in items) {
        batch.insert(
          'items',
          {'id': item.id, 'name': item.name, 'value': item.value},
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      stopwatch.stop();
      setState(() {
        timings['Sqflite Populate'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> updateSqflite() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      sqflite.Batch batch = sqfliteDb!.batch();
      for (var item in items) {
        batch.update(
          'items',
          {'name': item.name, 'value': item.value},
          where: 'id = ?',
          whereArgs: [item.id],
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      stopwatch.stop();
      setState(() {
        timings['Sqflite Update'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  // Drift Operations
  Future<void> populateDrift() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      await driftDb.insertItems(items);

      stopwatch.stop();
      setState(() {
        timings['Drift Populate'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> updateDrift() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      await driftDb.updateItems(items);

      stopwatch.stop();
      setState(() {
        timings['Drift Update'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  // Hive Operations
  Future<void> populateHive() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      List<HiveItem> hiveItems = items.map((item) => HiveItem(id: item.id, name: item.name, value: item.value)).toList();

      await hiveBox!.addAll(hiveItems);

      stopwatch.stop();
      setState(() {
        timings['Hive Populate'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> updateHive() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      for (var item in items) {
        final hiveItem = hiveBox!.values.firstWhere(
          (element) => element.id == item.id,
          orElse: () => HiveItem(id: item.id, name: '', value: ''),
        );
        hiveItem.name = item.name;
        hiveItem.value = item.value;
        await hiveItem.save();
      }

      stopwatch.stop();
      setState(() {
        timings['Hive Update'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  // Isar Operations
  Future<void> populateIsar() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      final isarItems = items
          .map((item) => IsarItem()
            ..id = item.id
            ..name = item.name
            ..value = item.value)
          .toList();

      await widget.isar.writeTxn(() async {
        await widget.isar.isarItems.putAll(isarItems);
      });

      stopwatch.stop();
      setState(() {
        timings['Isar Populate'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> updateIsar() async {
    try {
      List<ApiItem> items = await fetchItems();
      final stopwatch = Stopwatch()..start();

      await widget.isar.writeTxn(() async {
        for (var item in items) {
          final isarItem = await widget.isar.isarItems.get(item.id);
          if (isarItem != null) {
            isarItem.name = item.name;
            isarItem.value = item.value;
            await widget.isar.isarItems.put(isarItem);
          }
        }
      });

      stopwatch.stop();
      setState(() {
        timings['Isar Update'] = '${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (e) {
      print(e);
    }
  }

  // Drift Database Disposal
  @override
  void dispose() {
    super.dispose();
  }

  // UI Building
  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Scaffold(
      appBar: flutter.AppBar(
        title: flutter.Text('Teste de Desempenho DB'),
      ),
      body: flutter.SingleChildScrollView(
        padding: flutter.EdgeInsets.all(16.0),
        child: flutter.Column(
          children: [
            // Sqflite Buttons
            flutter.Text(
              'Sqflite',
              style: flutter.TextStyle(fontSize: 20, fontWeight: flutter.FontWeight.bold),
            ),
            flutter.ElevatedButton(
              onPressed: populateSqflite,
              child: flutter.Text('Popular banco de dados usando Sqflite'),
            ),
            flutter.ElevatedButton(
              onPressed: updateSqflite,
              child: flutter.Text('Atualizar banco de dados usando Sqflite'),
            ),
            flutter.SizedBox(height: 20),

            // Drift Buttons
            flutter.Text(
              'Drift',
              style: flutter.TextStyle(fontSize: 20, fontWeight: flutter.FontWeight.bold),
            ),
            flutter.ElevatedButton(
              onPressed: populateDrift,
              child: flutter.Text('Popular banco de dados usando Drift'),
            ),
            flutter.ElevatedButton(
              onPressed: updateDrift,
              child: flutter.Text('Atualizar banco de dados usando Drift'),
            ),
            flutter.SizedBox(height: 20),

            // Hive Buttons
            flutter.Text(
              'Hive',
              style: flutter.TextStyle(fontSize: 20, fontWeight: flutter.FontWeight.bold),
            ),
            flutter.ElevatedButton(
              onPressed: populateHive,
              child: flutter.Text('Popular banco de dados usando Hive'),
            ),
            flutter.ElevatedButton(
              onPressed: updateHive,
              child: flutter.Text('Atualizar banco de dados usando Hive'),
            ),
            flutter.SizedBox(height: 20),

            // Isar Buttons
            flutter.Text(
              'Isar',
              style: flutter.TextStyle(fontSize: 20, fontWeight: flutter.FontWeight.bold),
            ),
            flutter.ElevatedButton(
              onPressed: populateIsar,
              child: flutter.Text('Popular banco de dados usando Isar'),
            ),
            flutter.ElevatedButton(
              onPressed: updateIsar,
              child: flutter.Text('Atualizar banco de dados usando Isar'),
            ),
            flutter.SizedBox(height: 30),

            // Display Timings
            flutter.Text(
              'Tempos de Inserção/Atualização:',
              style: flutter.TextStyle(fontSize: 18, fontWeight: flutter.FontWeight.bold),
            ),
            ...timings.entries.map((entry) => flutter.ListTile(
                  title: flutter.Text(entry.key),
                  trailing: flutter.Text(entry.value),
                )),
          ],
        ),
      ),
    );
  }
}
