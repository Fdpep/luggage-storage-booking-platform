import 'package:flutter/foundation.dart'; // serve per kIsWeb
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carica variabili da .env
  await dotenv.load(fileName: kIsWeb ? ".env" : ".env.android");

  // Inizializza Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BagDrop Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const ConnectionTestPage(),
    );
  }
}

class ConnectionTestPage extends StatefulWidget {
  const ConnectionTestPage({super.key});

  @override
  State<ConnectionTestPage> createState() => _ConnectionTestPageState();
}

class _ConnectionTestPageState extends State<ConnectionTestPage> {
  String message = 'Verifica connessione...';

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    try {
      // Esegui una query semplice al DB Supabase
      final response = await Supabase.instance.client.from('ping').select().limit(1);
      setState(() => message = '✅ Connessione riuscita! (${response.length} tabelle trovate)');
    } catch (e) {
      setState(() => message = '❌ Errore connessione: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Supabase')),
      body: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}
