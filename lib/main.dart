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
      title: '경상북도농업기술원 농업현장 AI 진단시스템',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        primaryColor: const Color(0xFF38BDF8),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
        ),
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
  
  // 하단 탭 인덱스
  int _currentIndex = 0;

  // --- 진단 접수 폼 컨트롤러 ---
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController(); // 주소 추가됨!
  final TextEditingController _symptomController = TextEditingController();

  final List<String> crops = [
    '감', '거베라', '고추', '국화', '당귀', '딸기', '마늘', 
    '버터헤드', '복숭아', '오미자', '인삼', '자두', '장미', '참외'
  ];
  String selectedCrop = '감';
  File? _selectedImage;
  bool _isLoading = false;
  String _resultText = '증상 입력 및 사진 첨부 후 [AI 병해충 진단 요청] 버튼을 누르세요.';
  String? _dbImageUrl;

  final ImagePicker _picker = ImagePicker();

  // --- 통계 및 이력 데이터 ---
  List<dynamic> allHistoryData = [];
  List<dynamic> filteredHistoryData = [];
  Map<String, dynamic> statsData = {};
  bool _isHistoryLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  // --- API 통신: 이력 가져오기 ---
  Future<void> _fetchHistory() async {
    setState(() => _isHistoryLoading = true);
    try {
      var uri = Uri.parse('$serverUrl/api/history');
      var res = await http.get(uri);
      var data = jsonDecode(utf8.decode(res.bodyBytes)); // 한글 깨짐 방지
      setState(() {
        allHistoryData = data['history'] ?? [];
        filteredHistoryData = allHistoryData;
        statsData = data['stats'] ?? {};
      });
    } catch (e) {
      debugPrint('History fetch error: $e');
    } finally {
      setState(() => _isHistoryLoading = false);
    }
  }

  // --- 카메라/앨범 사진 선택 ---
  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  // --- API 통신: AI 진단 요청 ---
  Future<void> _runConsult() async {
    FocusScope.of(context).unfocus(); // 실행 시 키보드 내림

    if (_symptomController.text.trim().isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진을 첨부하시거나 증상을 입력해 주세요.')),
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
        
        RegExp exp = RegExp(r'참조_표준사진:\s*([^\n\r\]]+)', caseSensitive: false);
        var match = exp.firstMatch(prescription);

        if (match != null) {
          String filename = match.group(1)!.trim().replaceAll(']', '').trim();
          prescription = prescription.replaceAll(RegExp(r'\[?참조_표준사진:\s*[^\n\r\]]+\]?', caseSensitive: false), '').trim();
          _dbImageUrl = '$serverUrl/api/image/$selectedCrop/${Uri.encodeComponent(filename)}';
        }

        prescription = prescription.replaceAll('[', '').replaceAll(']', '');

        setState(() {
          _resultText = prescription;
        });
        
        // 진단 성공 시 이력 데이터 백그라운드 새로고침
        _fetchHistory();
      } else {
        setState(() => _resultText = '진단 실패: ${json['message']}');
      }
    } catch (e) {
      setState(() => _resultText = '통신 에러가 발생했습니다: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addSymptomChip(String text) {
    if (_symptomController.text.isEmpty) {
      _symptomController.text = text;
    } else {
      _symptomController.text += ', $text';
    }
    FocusScope.of(context).unfocus();
  }

  // 💡 작물 선택 팝업창 (BottomSheet) UI
  void _showCropPicker() {
    FocusScope.of(context).unfocus(); // 키보드 숨기기
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('작물 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      // 💡 명확한 닫기 버튼
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.grey),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: crops.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(crops[index], style: const TextStyle(fontSize: 15)),
                        trailing: crops[index] == selectedCrop ? const Icon(Icons.check, color: Color(0xFF38BDF8)) : null,
                        onTap: () {
                          setState(() => selectedCrop = crops[index]);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- UI: 탭 1 (진단 접수 화면) ---
  Widget _buildConsultTab() {
    return GestureDetector(
      // 💡 화면 빈 곳 터치 시 키보드 완벽하게 내려감
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. 민원인 정보', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '민원인 성명', border: OutlineInputBorder()), textInputAction: TextInputAction.next),
            const SizedBox(height: 8),
            TextField(controller: _phoneController, decoration: const InputDecoration(labelText: '연락처', border: OutlineInputBorder()), keyboardType: TextInputType.phone, textInputAction: TextInputAction.next),
            const SizedBox(height: 8),
            // 💡 누락되었던 주소 입력란 추가
            TextField(controller: _addressController, decoration: const InputDecoration(labelText: '농장 주소 (예: 영주 부석면)', border: OutlineInputBorder()), textInputAction: TextInputAction.done),
            const SizedBox(height: 16),

            const Text('2. 작물 선택', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // 💡 팝업창(BottomSheet)을 부르는 직관적인 버튼으로 변경
            InkWell(
              onTap: _showCropPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(selectedCrop, style: const TextStyle(fontSize: 16)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text('3. 현장 사진 첨부', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () { FocusScope.of(context).unfocus(); _pickImage(ImageSource.camera); },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('카메라 촬영'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () { FocusScope.of(context).unfocus(); _pickImage(ImageSource.gallery); },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('앨범 선택'),
                  ),
                ),
              ],
            ),
            if (_selectedImage != null) 
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Center(child: Image.file(_selectedImage!, height: 150)),
              ),
            const SizedBox(height: 16),

            const Text('4. 상세 증상 입력', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(label: const Text('과실 반점'), onPressed: () => _addSymptomChip('과실 표면 흑색 반점')),
                ActionChip(label: const Text('잎 점무늬/낙엽'), onPressed: () => _addSymptomChip('잎 둥근 점무늬 및 조기 낙엽')),
                ActionChip(label: const Text('줄기/꼭지 무름'), onPressed: () => _addSymptomChip('줄기 및 꼭지 무름')),
              ],
            ),
            // 💡 키보드 '완료(Done)' 버튼 추가
            TextField(
              controller: _symptomController, 
              maxLines: 3, 
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '증상을 상세히 입력해 주세요 (사진만 첨부해도 무방함)')
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                onPressed: _isLoading ? null : _runConsult,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('🔍 AI 병해충 진단 요청 (엑셀 저장)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            const Text('📋 진단 보고서', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_dbImageUrl != null) 
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Image.network(_dbImageUrl!, height: 150),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
              child: Text(_resultText, style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI: 탭 2 (이력 및 통계 화면) ---
  Widget _buildHistoryTab() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          // 통계 차트 (가로 바 형태)
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E293B),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📊 작목별 민원 통계', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (statsData.isEmpty) const Text('누적된 데이터가 없습니다.', style: TextStyle(color: Colors.grey)),
                ...statsData.entries.map((e) {
                  int total = statsData.values.fold(0, (a, b) => a + (b as int));
                  double ratio = total == 0 ? 0 : e.value / total;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        SizedBox(width: 50, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(height: 14, decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(7))),
                              FractionallySizedBox(
                                widthFactor: ratio,
                                child: Container(height: 14, decoration: BoxDecoration(color: const Color(0xFF38BDF8), borderRadius: BorderRadius.circular(7))),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 40, child: Text('${e.value}건', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.grey))),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          
          // 검색창
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              textInputAction: TextInputAction.search,
              onChanged: (val) {
                setState(() {
                  filteredHistoryData = allHistoryData.where((h) {
                    return h['name'].toLowerCase().contains(val.toLowerCase()) || 
                           h['phone'].replaceAll('-', '').contains(val.replaceAll('-', ''));
                  }).toList();
                });
              },
              decoration: InputDecoration(
                hintText: '🔍 이름 또는 연락처 검색',
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),

          // 리스트 출력
          Expanded(
            child: _isHistoryLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredHistoryData.isEmpty
                    ? const Center(child: Text('상담 이력이 없습니다.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: filteredHistoryData.length,
                        itemBuilder: (ctx, i) {
                          var h = filteredHistoryData[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${h['name']} (${h['crop']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                                  Text('${h['date']}'.substring(5, 16), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('📞 ${h['phone']}'),
                                  Text('${h['symptom']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('농업현장 AI 진단시스템', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        // 새로고침 버튼
        actions: [
          if (_currentIndex == 1)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchHistory)
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildConsultTab(),
          _buildHistoryTab(),
        ],
      ),
      // 💡 하단 탭바(Bottom Navigation Bar) 추가
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E293B),
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF38BDF8),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() { _currentIndex = index; });
          if (index == 1) _fetchHistory(); // 탭 이동 시 이력 자동 갱신
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: '진단 접수'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '이력 및 통계'),
        ],
      ),
    );
  }
}
