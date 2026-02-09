import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:clothes/env/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ElectronicWardrobeApp());
}

class ElectronicWardrobeApp extends StatelessWidget {
  const ElectronicWardrobeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Wardrobe AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Map<String, String>> _wardrobe = [];
  final ImagePicker _picker = ImagePicker();
  
  final String _geminiApiKey = Env.geminiKey;
  final String _weatherApiKey = Env.weatherKey;

  bool _isLoading = false;
  bool _isManualTemp = false; // Flag to track if user touched the slider
  String _selectedMood = "Happy";
  String _selectedTravel = "Walking";
  String _currentFolder = "All"; 
  double _currentTemp = 20.0;
  String _weatherDescription = "Loading...";

  final List<String> _folders = ["All", "Tops", "Bottoms", "Shoes", "Socks", "Jewelry", "Other"];
  final List<String> _moods = ["Happy", "Low-key", "Professional", "Date", "Relaxed"];
  
  final Map<String, IconData> _travelOptions = {
    "Walking": Icons.directions_walk,
    "Cycling": Icons.directions_bike,
    "Driving": Icons.directions_car,
    "Public Transit": Icons.directions_bus,
  };

  @override
  void initState() {
    super.initState();
    _loadWardrobe();
    _fetchLocalWeather();
  }

  List<Map<String, String>> get _filteredItems {
    if (_currentFolder == "All") return _wardrobe;
    return _wardrobe.where((item) => item['folder'] == _currentFolder).toList();
  }

  // --- Persistence ---
  Future<void> _loadWardrobe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString('wardrobe_data');
      if (savedData != null) {
        final List<dynamic> decodedData = json.decode(savedData);
        setState(() {
          _wardrobe.clear();
          _wardrobe.addAll(decodedData.map((item) => Map<String, String>.from(item)).toList());
        });
      }
    } catch (e) {
      debugPrint("Load Error: $e");
    }
  }

  Future<void> _saveWardrobe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wardrobe_data', json.encode(_wardrobe));
  }

  // --- Weather: Auto-fetch with Overwrite Logic ---
  Future<void> _fetchLocalWeather() async {
    // If user has manually moved the slider, we do not overwrite their setting
    if (_isManualTemp) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      final url = 'https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&appid=$_weatherApiKey&units=metric';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!_isManualTemp) { // Double check before state update
          setState(() {
            _currentTemp = data['main']['temp'].toDouble();
            _weatherDescription = data['weather'][0]['description'];
          });
        }
      }
    } catch (e) {
      if (!_isManualTemp) {
        setState(() => _weatherDescription = "Offline");
      }
    }
  }

  // --- AI Identification ---
  Future<void> _pickAndIdentifyImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _isLoading = true);

    try {
      final model = GenerativeModel(model: "gemini-3-flash-preview", apiKey: _geminiApiKey);
      final imageBytes = await image.readAsBytes();
      
      final prompt = TextPart("Analyze the clothing. Return exactly 4 words comma separated: Type, Color, Style, Folder. "
          "Folders must be one of: Tops, Bottoms, Shoes, Socks, Jewelry, Other.");
      final imagePart = DataPart('image/jpeg', imageBytes);
      
      final response = await model.generateContent([Content.multi([prompt, imagePart])]);
      final tags = (response.text ?? "Item,Color,Style,Other").split(',');

      setState(() {
        _wardrobe.add({
          'path': image.path,
          'type': tags.isNotEmpty ? tags[0].trim() : "Item",
          'color': tags.length > 1 ? tags[1].trim() : "Color",
          'style': tags.length > 2 ? tags[2].trim() : "Style",
          'folder': tags.length > 3 ? tags[3].trim() : "Other",
        });
      });
      await _saveWardrobe();
    } catch (e) {
      _showError("AI Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- FEATURE: Visual AI Recommendation ---
  Future<void> _generateMatch() async {
    if (_wardrobe.isEmpty) return _showError("Wardrobe is empty!");
    setState(() => _isLoading = true);
    try {
      final model = GenerativeModel(model: "gemini-3-flash-preview", apiKey: _geminiApiKey);
      
      String wardrobeData = _wardrobe.map((i) => "ID:${_wardrobe.indexOf(i)} - ${i['color']} ${i['type']}").join(", ");
      
      final prompt = """
        I have these clothes: $wardrobeData. 
        Weather: ${_currentTemp.toInt()}°C, $_weatherDescription. Mood: $_selectedMood. Travel: $_selectedTravel. 
        Suggest the best outfit. 
        IMPORTANT: Start your response with 'PICKED_IDS:' followed by the comma-separated IDs of the items you chose (e.g., PICKED_IDS: 0, 2). 
        Then provide your explanation.
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      final aiText = response.text ?? "";

      List<String> pickedPaths = [];
      if (aiText.contains("PICKED_IDS:")) {
        final idLine = aiText.split('\n').firstWhere((l) => l.contains("PICKED_IDS:"));
        final idString = idLine.replaceAll("PICKED_IDS:", "").trim();
        final ids = idString.split(',').map((s) => s.trim());
        
        for (var id in ids) {
          int? index = int.tryParse(id);
          if (index != null && index < _wardrobe.length) {
            pickedPaths.add(_wardrobe[index]['path']!);
          }
        }
      }

      _showVisualResultDialog("Recommended Outfit", aiText.replaceAll(RegExp(r'PICKED_IDS:.*'), "").trim(), pickedPaths);
    } catch (e) {
      _showError("Matching Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showVisualResultDialog(String title, String explanation, List<String> paths) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite, 
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (paths.isNotEmpty) ...[
                  const Text("Items selected:", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150, 
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: paths.length,
                      itemBuilder: (context, i) => Container(
                        margin: const EdgeInsets.only(right: 10),
                        width: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[200],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb 
                            ? Image.network(paths[i], fit: BoxFit.cover)
                            : Image.file(File(paths[i]), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 30),
                ],
                Text(explanation),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c), 
            child: const Text("Awesome!")
          )
        ],
      ),
    );
  }

  // --- UI Layout ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Smart Wardrobe AI"), centerTitle: true),
      body: Column(
        children: [
          _buildControlPanel(),
          _buildFolderBar(),
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(child: Text("No items in $_currentFolder"))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: kIsWeb ? 8 : 5, 
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) => _buildClothingCard(_filteredItems[index]),
                  ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndIdentifyImage,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  _isManualTemp ? Icons.edit_location_alt : Icons.wb_sunny_outlined, 
                  size: 20, 
                  color: _isManualTemp ? Colors.orange : Colors.orangeAccent
                ),
                const SizedBox(width: 8),
                Text(
                  "${_currentTemp.toInt()}°C", 
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isManualTemp ? Colors.orange : Colors.black
                  )
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isManualTemp ? "$_weatherDescription (Manual)" : _weatherDescription, 
                    style: const TextStyle(fontSize: 12), 
                    overflow: TextOverflow.ellipsis
                  )
                ),
                // Toggle Button: If manual, show "Auto" reset; else show "Refresh"
                if (_isManualTemp)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isManualTemp = false;
                        _weatherDescription = "Refreshing...";
                      });
                      _fetchLocalWeather();
                    },
                    icon: const Icon(Icons.autorenew, size: 16),
                    label: const Text("Auto", style: TextStyle(fontSize: 10)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18), 
                    onPressed: _fetchLocalWeather
                  ),
              ],
            ),
            // Temperature Slider
            Slider(
              value: _currentTemp.clamp(-10.0, 45.0),
              min: -10,
              max: 45,
              divisions: 55,
              label: "${_currentTemp.toInt()}°C",
              activeColor: _isManualTemp ? Colors.orange : Colors.teal,
              onChanged: (double value) {
                setState(() {
                  _isManualTemp = true; // Set manual flag to TRUE on touch
                  _currentTemp = value;
                  _weatherDescription = "Manual Override";
                });
              },
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DropdownButton<String>(
                  value: _selectedMood,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.face, size: 16),
                  items: _moods.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _selectedMood = v!),
                ),
                DropdownButton<String>(
                  value: _selectedTravel,
                  underline: const SizedBox(),
                  items: _travelOptions.keys.map((String key) => DropdownMenuItem<String>(
                    value: key,
                    child: Row(children: [
                      Icon(_travelOptions[key], size: 16, color: Colors.teal),
                      const SizedBox(width: 5),
                      Text(key, style: const TextStyle(fontSize: 12)),
                    ]),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedTravel = v!),
                ),
                ElevatedButton.icon(
                  onPressed: _generateMatch,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text("Match", style: TextStyle(fontSize: 12)),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderBar() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _folders.map((folder) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(folder, style: const TextStyle(fontSize: 11)),
            selected: _currentFolder == folder,
            onSelected: (selected) => setState(() => _currentFolder = folder),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildClothingCard(Map<String, String> item) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: kIsWeb 
                  ? Image.network(item['path']!, fit: BoxFit.cover, width: double.infinity)
                  : Image.file(File(item['path']!), fit: BoxFit.cover, width: double.infinity),
              ),
              Padding(
                padding: const EdgeInsets.all(2.0),
                child: Text(item['type']!, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold), maxLines: 1),
              ),
            ],
          ),
          Positioned(
            top: 0, right: 0,
            child: GestureDetector(
              onTap: () { setState(() => _wardrobe.remove(item)); _saveWardrobe(); },
              child: Container(
                color: Colors.white.withOpacity(0.7),
                child: const Icon(Icons.close, size: 14, color: Colors.red),
              ),
            ),
          )
        ],
      ),
    );
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}