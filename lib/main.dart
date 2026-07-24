import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FarmAgentApp());
}

class FarmAgentApp extends StatelessWidget {
  const FarmAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '경북농업기술원 AI 보조',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        primaryColor: const Color(0xFF38BDF8),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final String serverUrl = 'https://farm-agent-app.onrender.com';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _symptomController = TextEditingController();

  String selectedCrop = '감';
  File? _selectedImage;
  bool _isLoading = false;
  String _resultText = '증상 입력 및 사진 첨부 후 [AI 병해충 진단 요청] 버튼을 누르세요.';
  String? _dbImageUrl;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _runConsult() async {
    if (_symptomController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('증상을 입력해 주세요.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _resultText = '⏳ Render 서버에서 AI 진단 및 엑셀 저장 중...';
      _dbImageUrl = null;
    });

    try {
      var uri = Uri.parse('$serverUrl/api/consult');
      var request = http.MultipartRequest('POST', uri);

      request.fields['user_name'] = _nameController.text.isEmpty ? '미상' : _nameController.text;
      request.fields['user_phone'] = _phoneController.text.isEmpty ? '미상' : _phoneController.text;
      request.fields['user_address'] = _addressController.text.isEmpty ? '미상' : _addressController.text;
      request.fields['crop_name'] = selectedCrop;
      request.fields['symptom'] = _symptomController.text;

      if (_selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('image', _selectedImage!.path));
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      if (json['status'] == 'success') {
        String prescription = json['prescription'];
        RegExp exp = RegExp(r'\[참조_표준사진:\s*([^\]]+)\]', caseSensitive: false);
        var match = exp.firstMatch(prescription);

        if (match != null) {
          String filename = match.group(1)!.trim();
          prescription = prescription.replaceAll(exp, '').trim();
          _dbImageUrl = '$serverUrl/api/image/$selectedCrop/${Uri.encodeComponent(filename)}';
        }

        setState(() {
          _resultText = prescription;
        });
      } else {
        setState(() {
          _resultText = '진단 실패: ${json['message']}';
        });
      }
    } catch (e) {
      setState(() {
        _resultText = '통신 에러가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addSymptomChip(String text) {
    if (_symptomController.text.isEmpty) {
      _symptomController.text = text;
    } else {
      _symptomController.text += ', $text';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('경북농업기술원 병해충 AI진단'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            const Text('1. 민원인 정보', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '민원인 성명', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _phoneController, decoration: const InputDecoration(labelText: '연락처', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),

            const Text('2. 작물 선택', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: selectedCrop,
              isExpanded: true,
              items: ['감', '고추', '딸기', '참외', '복숭아'].map((String crop) {
                return DropdownMenuItem<String>(value: crop, child: Text(crop));
              }).toList(),
              onChanged: (val) => setState(() => selectedCrop = val!),
            ),
            const SizedBox(height: 16),

            const Text('3. 현장 사진 첨부', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('카메라 촬영'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('앨범 선택'),
                ),
              ],
            ),
            if (_selectedImage != null) Image.file(_selectedImage!, height: 150),
            const SizedBox(height: 16),

            const Text('4. 상세 증상 입력', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(label: const Text('과실 흑색 반점'), onPressed: () => _addSymptomChip('과실 표면 검은색 반점')),
                ActionChip(label: const Text('잎 점무늬'), onPressed: () => _addSymptomChip('잎 둥근 점무늬 및 조기 낙엽')),
                ActionChip(label: const Text('꼭지 무름'), onPressed: () => _addSymptomChip('감 꼭지 무름 및 낙과')),
              ],
            ),
            TextField(controller: _symptomController, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '증상을 상세히 입력해 주세요')),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                onPressed: _isLoading ? null : _runConsult,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('🔍 AI 병해충 진단 요청 (엑셀 누적)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            const Text('📋 진단 보고서', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 18, fontWeight: FontWeight.bold)),
            if (_dbImageUrl != null) Image.network(_dbImageUrl!, height: 150),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
              child: Text(_resultText, style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
          ],
        ),
      ),
    );
  }
}