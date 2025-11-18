import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const GymLoadApp());
}

/// MODELOS BÁSICOS

class SetEntry {
  final String exercise;
  final double weight;
  final int reps;
  final double? rpe;
  final DateTime date;

  SetEntry({
    required this.exercise,
    required this.weight,
    required this.reps,
    this.rpe,
    required this.date,
  });
}

class PRRecord {
  final String exercise;
  final int reps;
  final double weight;
  final DateTime date;

  PRRecord({
    required this.exercise,
    required this.reps,
    required this.weight,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'exercise': exercise,
      'reps': reps,
      'weight': weight,
      'date': date.toIso8601String(),
    };
  }

  factory PRRecord.fromMap(Map<String, dynamic> map) {
    return PRRecord(
      exercise: map['exercise'] as String,
      reps: map['reps'] as int,
      weight: (map['weight'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
    );
  }
}

/// CALCULADORA FUERZA (Epley)

class StrengthCalculator {
  static double oneRepMax(double weight, int reps) {
    if (reps <= 0) return 0;
    return weight * (1 + reps / 30.0);
  }

  static double weightForReps(double oneRM, int targetReps) {
    if (targetReps <= 0) return 0;
    return oneRM / (1 + targetReps / 30.0);
  }

  static double adjustForRpe(double weight, double rpe) {
    double delta;
    if (rpe < 7) {
      delta = 0.05;
    } else if (rpe < 8) {
      delta = 0.025;
    } else if (rpe < 9) {
      delta = 0.0;
    } else if (rpe < 10) {
      delta = -0.025;
    } else {
      delta = -0.05;
    }
    return weight * (1 + delta);
  }
}

/// CALCULADORA NUTRICIÓN (Mifflin-St Jeor)

class NutritionCalculator {
  static double tdee({
    required double weightKg,
    required double heightCm,
    required int age,
    required bool isMale,
    required double activityFactor,
  }) {
    double bmr;
    if (isMale) {
      bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + 5;
    } else {
      bmr = 10 * weightKg + 6.25 * heightCm - 5 * age - 161;
    }
    return bmr * activityFactor;
  }
}

/// TEMA APP

enum AppThemeMode { system, light, dark }

class GymLoadApp extends StatefulWidget {
  const GymLoadApp({super.key});

  @override
  State<GymLoadApp> createState() => _GymLoadAppState();
}

class _GymLoadAppState extends State<GymLoadApp> {
  int _currentIndex = 0;

  /// Estado global persistente
  List<PRRecord> _prs = [];
  AppThemeMode _themeMode = AppThemeMode.system;
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // PRs
    final prJson = prefs.getString('prs');
    if (prJson != null) {
      final List<dynamic> list = jsonDecode(prJson);
      _prs = list
          .map((e) => PRRecord.fromMap(e as Map<String, dynamic>))
          .toList();
    }

    // Tema
    final themeStr = prefs.getString('themeMode');
    if (themeStr != null) {
      final found = AppThemeMode.values
          .firstWhere((t) => t.name == themeStr, orElse: () => AppThemeMode.system);
      _themeMode = found;
    }

    // Recordatorio
    _reminderEnabled = prefs.getBool('reminderEnabled') ?? false;
    final timeStr = prefs.getString('reminderTime');
    if (timeStr != null) {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          _reminderTime = TimeOfDay(hour: h, minute: m);
        }
      }
    }

    setState(() {
      _loaded = true;
    });
  }

  Future<void> _savePRs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _prs.map((e) => e.toMap()).toList();
    await prefs.setString('prs', jsonEncode(list));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeMode.name);
    await prefs.setBool('reminderEnabled', _reminderEnabled);
    final timeStr =
        '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}';
    await prefs.setString('reminderTime', timeStr);
  }

  void _addOrUpdatePR(String exercise, double weight, int reps) {
    final name = exercise.trim();
    if (name.isEmpty || reps <= 0 || weight <= 0) return;

    final existingIndex = _prs.indexWhere(
      (pr) =>
          pr.exercise.toLowerCase() == name.toLowerCase() && pr.reps == reps,
    );

    final newRecord = PRRecord(
      exercise: name,
      reps: reps,
      weight: weight,
      date: DateTime.now(),
    );

    setState(() {
      if (existingIndex >= 0) {
        if (weight > _prs[existingIndex].weight) {
          _prs[existingIndex] = newRecord;
        }
      } else {
        _prs.add(newRecord);
      }
    });

    _savePRs();
  }

  void _changeTheme(AppThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    _saveSettings();
  }

  void _setReminder(bool enabled, TimeOfDay time) {
    setState(() {
      _reminderEnabled = enabled;
      _reminderTime = time;
    });
    _saveSettings();
  }

  ThemeMode get _materialThemeMode {
    switch (_themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Gym Load',
      debugShowCheckedModeBanner: false,
      themeMode: _materialThemeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blueAccent,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            TodayPage(),
            LoadCalculatorPage(
              onSavePR: _addOrUpdatePR,
            ),
            PRPage(prs: _prs),
            ProfilePage(
              themeMode: _themeMode,
              onThemeChanged: _changeTheme,
              reminderEnabled: _reminderEnabled,
              reminderTime: _reminderTime,
              onReminderChanged: _setReminder,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined),
              selectedIcon: Icon(Icons.wb_sunny),
              label: 'Hoy',
            ),
            NavigationDestination(
              icon: Icon(Icons.scale_outlined),
              selectedIcon: Icon(Icons.scale),
              label: 'Cargas',
            ),
            NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: 'PR',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

/// TAB 1 – HOY

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  double energy = 3;
  double stress = 3;
  double sleep = 3;

  String get suggestion {
    final score = energy - stress + sleep;
    if (score < 2) {
      return 'Día pesado → mantené cargas o baja un poco el volumen.';
    } else if (score <= 4) {
      return 'Día neutro → entreno normal, sin volverse loco.';
    } else {
      return 'Día bueno → podés intentar subir un poco las cargas.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoy'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '¿Cómo estás hoy?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildSlider(
            label: 'Energía',
            value: energy,
            onChanged: (v) => setState(() => energy = v),
          ),
          _buildSlider(
            label: 'Estrés',
            value: stress,
            onChanged: (v) => setState(() => stress = v),
          ),
          _buildSlider(
            label: 'Sueño',
            value: sleep,
            onChanged: (v) => setState(() => sleep = v),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sugerencia del día',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            suggestion,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)} / 5'),
        Slider(
          value: value,
          min: 1,
          max: 5,
          divisions: 8,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// TAB 2 – CALCULADORA CARGAS

class LoadCalculatorPage extends StatefulWidget {
  final void Function(String exercise, double weight, int reps) onSavePR;

  const LoadCalculatorPage({
    super.key,
    required this.onSavePR,
  });

  @override
  State<LoadCalculatorPage> createState() => _LoadCalculatorPageState();
}

class _LoadCalculatorPageState extends State<LoadCalculatorPage> {
  final _exerciseCtrl = TextEditingController(text: 'Bench press');
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();
  final _targetRepsCtrl = TextEditingController(text: '8');

  double rpe = 8;
  double? oneRm;
  double? suggestedWeight;

  @override
  void dispose() {
    _exerciseCtrl.dispose();
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _targetRepsCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    final reps = int.tryParse(_repsCtrl.text);
    final targetReps = int.tryParse(_targetRepsCtrl.text);

    if (weight == null || reps == null || reps <= 0) {
      setState(() {
        oneRm = null;
        suggestedWeight = null;
      });
      return;
    }

    final rm = StrengthCalculator.oneRepMax(weight, reps);
    double? target;

    if (targetReps != null && targetReps > 0) {
      target = StrengthCalculator.weightForReps(rm, targetReps);
      target = StrengthCalculator.adjustForRpe(target, rpe);
    }

    setState(() {
      oneRm = rm;
      suggestedWeight = target;
    });
  }

  void _saveAsPR() {
    final exercise = _exerciseCtrl.text.trim();
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    final reps = int.tryParse(_repsCtrl.text);

    if (exercise.isEmpty || weight == null || reps == null || reps <= 0) {
      return;
    }

    widget.onSavePR(exercise, weight, reps);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Serie guardada / PR actualizado')),
    );
  }

  bool get _canSavePR {
    final exercise = _exerciseCtrl.text.trim();
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    final reps = int.tryParse(_repsCtrl.text);
    return exercise.isNotEmpty && weight != null && reps != null && reps > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculadora de cargas'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ejercicio',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _exerciseCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Nombre del ejercicio',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Serie que hiciste',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Peso (kg)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Reps',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('RPE:'),
              Expanded(
                child: Slider(
                  value: rpe,
                  min: 6,
                  max: 10,
                  divisions: 8,
                  label: rpe.toStringAsFixed(1),
                  onChanged: (v) => setState(() => rpe = v),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  rpe.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Cálculo 1RM',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            oneRm == null
                ? 'Completá peso y reps para ver tu 1RM.'
                : '1RM estimado: ${oneRm!.toStringAsFixed(1)} kg',
          ),
          const SizedBox(height: 16),
          const Text(
            'Objetivo',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetRepsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Reps objetivo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestedWeight == null
                ? 'Completá los datos para ver el peso sugerido.'
                : 'Peso sugerido: ${suggestedWeight!.toStringAsFixed(1)} kg (ajustado por RPE)',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _calculate,
            child: const Text('Calcular'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _canSavePR ? _saveAsPR : null,
            child: const Text('Guardar como posible PR'),
          ),
        ],
      ),
    );
  }
}

/// TAB 3 – PR

class PRPage extends StatelessWidget {
  final List<PRRecord> prs;

  const PRPage({super.key, required this.prs});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PRRecord>>{};

    for (final pr in prs) {
      grouped.putIfAbsent(pr.exercise, () => []).add(pr);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PR personales'),
      ),
      body: prs.isEmpty
          ? const Center(
              child: Text(
                'Todavía no guardaste ningún PR.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView(
              children: grouped.entries.map((entry) {
                final exercise = entry.key;
                final records = entry.value.toList()
                  ..sort((a, b) => a.reps.compareTo(b.reps));

                return ExpansionTile(
                  title: Text(
                    exercise,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: records
                      .map(
                        (pr) => ListTile(
                          title: Text('${pr.reps} reps'),
                          subtitle: Text(
                              'Peso: ${pr.weight.toStringAsFixed(1)} kg · ${_formatDate(pr.date)}'),
                        ),
                      )
                      .toList(),
                );
              }).toList(),
            ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

/// TAB 4 – PERFIL (NUTRICIÓN + AJUSTES)

class ProfilePage extends StatefulWidget {
  final AppThemeMode themeMode;
  final void Function(AppThemeMode) onThemeChanged;

  final bool reminderEnabled;
  final TimeOfDay reminderTime;
  final void Function(bool enabled, TimeOfDay time) onReminderChanged;

  const ProfilePage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.reminderEnabled,
    required this.reminderTime,
    required this.onReminderChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _weight = '';
  String _height = '';
  String _age = '';
  bool _isMale = true;
  int _activityIndex = 1;
  double? _tdee;

  final List<double> _activityFactors = const [
    1.2,
    1.375,
    1.55,
    1.725,
    1.9,
  ];

  final List<String> _activityLabels = const [
    'Sedentario',
    'Ligero (1–3 días/sem)',
    'Moderado (3–5 días/sem)',
    'Intenso (6–7 días/sem)',
    'Muy intenso (trabajo físico + entreno)',
  ];

  late bool _reminderEnabled;
  late TimeOfDay _reminderTime;

  @override
  void initState() {
    super.initState();
    _reminderEnabled = widget.reminderEnabled;
    _reminderTime = widget.reminderTime;
  }

  void _calculateTdee() {
    final w = double.tryParse(_weight.replaceAll(',', '.'));
    final h = double.tryParse(_height.replaceAll(',', '.'));
    final a = int.tryParse(_age);

    if (w == null ||
        h == null ||
        a == null ||
        _activityIndex < 0 ||
        _activityIndex >= _activityFactors.length) {
      setState(() => _tdee = null);
      return;
    }

    final tdee = NutritionCalculator.tdee(
      weightKg: w,
      heightCm: h,
      age: a,
      isMale: _isMale,
      activityFactor: _activityFactors[_activityIndex],
    );

    setState(() {
      _tdee = tdee;
    });
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (picked != null) {
      setState(() {
        _reminderTime = picked;
      });
      widget.onReminderChanged(_reminderEnabled, _reminderTime);
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Calculadora de calorías (TDEE)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Peso (kg)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => setState(() => _weight = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Altura (cm)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => setState(() => _height = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Edad (años)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() => _age = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Sexo:'),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Masculino'),
                selected: _isMale,
                onSelected: (_) => setState(() => _isMale = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Femenino'),
                selected: !_isMale,
                onSelected: (_) => setState(() => _isMale = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              labelText: 'Nivel de actividad',
              border: OutlineInputBorder(),
            ),
            value: _activityIndex,
            onChanged: (v) => setState(() => _activityIndex = v ?? 1),
            items: List.generate(
              _activityLabels.length,
              (i) => DropdownMenuItem(
                value: i,
                child: Text(_activityLabels[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _calculateTdee,
            child: const Text('Calcular calorías de mantenimiento'),
          ),
          const SizedBox(height: 8),
          Text(
            _tdee == null
                ? 'Completá los datos para ver el resultado.'
                : 'Calorías aproximadas de mantenimiento: ${_tdee!.round()} kcal/día',
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Apariencia',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Sistema'),
                selected: widget.themeMode == AppThemeMode.system,
                onSelected: (_) => widget.onThemeChanged(AppThemeMode.system),
              ),
              ChoiceChip(
                label: const Text('Claro'),
                selected: widget.themeMode == AppThemeMode.light,
                onSelected: (_) => widget.onThemeChanged(AppThemeMode.light),
              ),
              ChoiceChip(
                label: const Text('Oscuro'),
                selected: widget.themeMode == AppThemeMode.dark,
                onSelected: (_) => widget.onThemeChanged(AppThemeMode.dark),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Recordatorio diario',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Activar recordatorio'),
            subtitle: const Text(
                'Por ahora solo se guarda la hora dentro de la app. Para notificaciones reales hay que agregar un plugin.'),
            value: _reminderEnabled,
            onChanged: (v) {
              setState(() => _reminderEnabled = v);
              widget.onReminderChanged(_reminderEnabled, _reminderTime);
            },
          ),
          ListTile(
            title: const Text('Hora del recordatorio'),
            subtitle: Text(_formatTimeOfDay(_reminderTime)),
            trailing: const Icon(Icons.access_time),
            onTap: _reminderEnabled ? _pickReminderTime : null,
          ),
        ],
      ),
    );
  }
}
