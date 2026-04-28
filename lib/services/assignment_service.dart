import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/assignment.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'storage_service.dart';

const String _devBaseUrl = 'http://localhost:3000/api';
const String _prodBaseUrl = 'https://techpie.geekpie.club/api';

class AssignmentService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final AuthService _auth;

  List<Assignment> _assignments = [];
  bool _loading = false;
  String? _error;

  String get _baseUrl => _storage.useLocalhost ? _devBaseUrl : _prodBaseUrl;

  List<Assignment> get assignments => _assignments;
  bool get loading => _loading;
  String? get error => _error;

  AssignmentService(this._storage, this._http, this._auth);

  Map<String, String> _jsonHeaders() => {
    'Content-Type': 'application/json; charset=UTF-8',
  };

  Map<String, dynamic> _authBody() {
    final session = _auth.session!;
    final baseCookies = session.cookies;
    final tgc = session.tgc;
    final cookies = tgc.isNotEmpty
        ? (baseCookies.isNotEmpty ? '$baseCookies; CASTGC=$tgc' : 'CASTGC=$tgc')
        : baseCookies;
    return {'studentId': session.studentId, 'cookies': cookies};
  }

  Future<void> fetchAssignments() async {
    if (!_auth.isLoggedIn) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final body = _authBody();
      
      // Try to fetch from NextDDL integrated API endpoint
      var resp = await _http.post(
        Uri.parse('$_baseUrl/deadlines'),
        headers: _jsonHeaders(),
        body: jsonEncode(body),
        tag: 'fetchAssignments',
      );

      if (resp.statusCode == 401) {
        final renewed = await _auth.tryRenewSession();
        if (renewed) {
          final newBody = {...body, ..._authBody()};
          resp = await _http.post(
            Uri.parse('$_baseUrl/deadlines'),
            headers: _jsonHeaders(),
            body: jsonEncode(newBody),
            tag: 'fetchAssignments-retry',
          );
        }
      }

      if (resp.statusCode != 200) {
        // Fallback or throw error. We can use dummy data for demonstration if not integrated yet.
        _error = 'Failed to fetch assignments: ${resp.statusCode}. Make sure NextDDL is integrated.';
        // Optional: generate dummy data if error
        _generateDummyData();
      } else {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>? ?? [];
        _assignments = items.map((e) => Assignment.fromJson(e)).toList();
      }
    } catch (e) {
      _error = e.toString();
      _generateDummyData(); // Add some dummy data so the user can see the UI
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _generateDummyData() {
    // Generate some placeholder NextDDL style assignments so the UI can be tested
    final now = DateTime.now();
    _assignments = [
      Assignment(
        id: '1',
        platform: 'blackboard',
        title: 'Homework 4: Networking',
        course: 'CS110 Computer Architecture',
        due: now.add(const Duration(days: 2, hours: 5)),
        status: 'Needs Grading',
        url: 'https://bb.shanghaitech.edu.cn',
        submitted: true,
      ),
      Assignment(
        id: '2',
        platform: 'gradescope',
        title: 'Lab 5: Cache Simulator',
        course: 'CS110 Computer Architecture',
        due: now.add(const Duration(hours: 12)),
        status: 'No Submission',
        url: 'https://gradescope.com',
        submitted: false,
      ),
      Assignment(
        id: '3',
        platform: 'hydro',
        title: 'Project 2: RISC-V CPU',
        course: 'CS110 Computer Architecture',
        due: now.add(const Duration(days: 14)),
        status: null,
        url: 'https://hydro.ac',
        submitted: false,
      ),
      Assignment(
        id: '4',
        platform: 'blackboard',
        title: 'Reading Reflection',
        course: 'EG105 English',
        due: now.subtract(const Duration(days: 1)),
        status: 'Graded',
        url: 'https://bb.shanghaitech.edu.cn',
        submitted: true,
      ),
    ];
  }
}
