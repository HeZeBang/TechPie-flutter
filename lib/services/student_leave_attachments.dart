import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'campus/campus_errors.dart';
import 'campus/emap_client.dart';
import 'student_leave_service.dart';

class LeaveAttachmentFile {
  const LeaveAttachmentFile(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

/// Each populated form field gets its own token. An edited application keeps
/// its existing tokens until the replacement files have been saved and read back.
class StudentLeaveAttachments {
  const StudentLeaveAttachments(this.client);
  final EmapClient client;

  static const extensions = [
    'doc',
    'jpg',
    'png',
    'jpeg',
    'bmp',
    'docx',
    'zip',
    'rar',
    'pdf',
    'xls',
    'xlsx',
    'txt',
  ];
  static const maxProofBytes = 5 * 1024 * 1024;
  static final _random = Random.secure();

  Future<String> persist(
    List<LeaveAttachmentFile> files, {
    required bool courseProof,
    required void Function() checkAccount,
  }) async {
    checkAccount();
    if (files.isEmpty) return '';
    for (final file in files) {
      if (file.name.trim().isEmpty || file.name.contains(RegExp(r'[/\\\x00-\x1f\x7f]'))) {
        throw const CampusRequestException(CampusErrorKind.rejected, '附件文件名无效');
      }
      if (!courseProof &&
          (file.bytes.length > maxProofBytes ||
              !file.name.contains('.') ||
              !extensions.contains(file.name.split('.').last.toLowerCase()))) {
        throw const CampusRequestException(CampusErrorKind.rejected, '证明材料格式不支持或超过 5 MiB');
      }
    }

    final scope = '${DateTime.now().millisecondsSinceEpoch}${_random.nextInt(100)}';
    final token = '${scope}1';
    Future<Map<String, dynamic>> post(String path, Object data, {bool write = false}) async {
      checkAccount();
      final result = await client.postFileComponent(
        app: StudentLeaveService.app,
        appId: StudentLeaveService.appId,
        path: path,
        form: data,
        singleSubmission: write,
      );
      checkAccount();
      return result;
    }

    final order = <String, int>{};
    for (final file in files) {
      final uploaded = await post(
        'uploadTempFile.do',
        FormData.fromMap({
          'scope': scope,
          'fileToken': token,
          'size': courseProof ? '0' : '5120',
          'type': courseProof ? '' : extensions.join(','),
          'storeId': 'file',
          'isSingle': '0',
          'fileName': '',
          (courseProof ? 'files[]' : 'bhFile'):
              MultipartFile.fromBytes(file.bytes, filename: file.name),
        }),
        write: true,
      );
      final id = uploaded['id'];
      if (uploaded['success'] != true || id is! String || id.isEmpty || order.containsKey(id)) {
        throw const CampusRequestException(CampusErrorKind.rejected, '附件上传失败');
      }
      if (!courseProof) {
        final checked = await post('tempFileCheck.do', {
          'scope': scope,
          'fileToken': token,
          'fileId': id,
        });
        if (checked['check'] != true) {
          throw const CampusRequestException(CampusErrorKind.rejected, '学校未能校验上传的附件');
        }
      }
      order[id] = order.length + 1;
    }

    final identity = {'scope': scope, 'fileToken': token};
    final save = await post(
      'saveAttachment/$scope/$token.do',
      <String, String>{
        if (courseProof) ...identity,
        'attachmentParam': jsonEncode({
          'storeId': 'file',
          if (!courseProof) ...identity,
          'orderMap': order,
        }),
      },
      write: true,
    );
    if (save['success'] != true) {
      throw const CampusRequestException(CampusErrorKind.rejected, '学校未保存附件');
    }
    final saved = courseProof
        ? await post('getUploadedAttachment.do', {'fileToken': token})
        : await post('getUploadedAttachment/$token.do', const <String, String>{});
    final items = saved['items'];
    final ids = items is List
        ? items.whereType<Map<String, dynamic>>().map((entry) => entry['id']).toSet()
        : null;
    if (saved['success'] != true ||
        ids == null ||
        ids.length != order.length ||
        !ids.containsAll(order.keys)) {
      throw const CampusRequestException(CampusErrorKind.rejected, '学校附件记录与所选文件不一致');
    }
    return token;
  }
}
