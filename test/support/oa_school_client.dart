import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sanitized OA protocol fixture: never connects to a school or API server.
class OaSchoolClient extends http.BaseClient {
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? intercept;

  Future<http.Response> respond(http.BaseRequest base) async {
    final request = base as http.Request;
    requests.add(request);
    final overridden = await intercept?.call(request);
    if (overridden != null) return overridden;
    final uri = request.url;
    switch (uri.path) {
      case '/formmode/browser/CommonSingleBrowser.jsp':
        return text(
          'var __tableStringKey__ = "${uri.queryParameters['customid'] == '7102' ? 'AA' : 'BB'}";',
        );
      case '/weaver/weaver.common.util.taglib.SplitPageXmlServlet':
        final fields = {...uri.queryParameters, ...Uri.splitQueryString(request.body)};
        final table = fields['tableString'];
        return text(
          switch (table) {
            'AA' => '<rows><row><col>8</col><col/><col showvalue="18:00－19:00"/></row></rows>',
            'BB' => '<rows>'
                '<row><col>13</col><col/><col showvalue="羽毛球场地 １ 号（东馆）"/></row>'
                '<row><col>25</col><col/><col showvalue="网球场1号"/></row>'
                '<row><col>43</col><col/><col showvalue="匹克球1号场地"/></row>'
                '<row><col>44</col><col/><col showvalue="匹克球2号场地"/></row>'
                '</rows>',
            'CC' => '<rows><row><col><![CDATA[2026-11-03]]></col>'
                '<col showvalue="&lt;b&gt;已通过&lt;/b&gt;"/></row></rows>',
            _ => throw StateError('Unexpected OA table'),
          },
        );
      case '/formmode/tree/treebrowser/CustomTreeBrowserAjax.jsp':
        final form = Uri.splitQueryString(request.body);
        if (form['pid'] == '63_1') {
          return text(
            jsonEncode(
              [
                {'id': '63_bad', 'name': '室内羽毛球场', 'isParent': 'true'},
                {'id': '63_ten', 'name': '网球场', 'isParent': 'true'},
                {'id': '63_pic', 'name': '匹克球场', 'isParent': 'true'},
              ],
            ),
          );
        }
        final prefix = switch (form['pid']) {
          '63_bad' => '羽毛球场地',
          '63_ten' => '网球场',
          _ => '匹克球',
        };
        return text(
          jsonEncode(
            [
              {'name': '${prefix}1号场地'},
              {'name': '${prefix}2号场地'},
            ],
          ),
        );
      case '/formmode/search/CustomSearchBySimpleIframe.jsp':
        return text('var __tableStringKey__ = "CC";');
      case '/workflow/request/AddRequest.jsp':
        return text(
          '<html>current user workflow form</html>',
          headers: {
            'set-cookie': 'loginidweaver=fixture-current-user; Path=/; Secure',
          },
        );
      case '/workflow/request/RequestOperation.jsp':
        return text(
          "<script>wfforward('/workflow/request/WorkflowDirection.jsp?requestid=synthetic')</script>",
        );
      case '/hrm/resource/HrmResourceContactEdit.jsp':
        return contacts();
      default:
        throw StateError('Unexpected request: ${uri.path}');
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await respond(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  static http.Response text(String body, {int status = 200, Map<String, String>? headers}) =>
      http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'text/plain; charset=utf-8', ...?headers},
      );

  static http.Response contacts({
    String id = 'fixture-current-user',
    String phone = '13900000000',
    String email = 'student@shanghaitech.edu.cn',
  }) =>
      text(
        '<form id="resource" name="resourcebasicinfo" method="post">'
        '<input name="id" value="$id"><input name="mobile" value="$phone">'
        '<input name="email" value="$email"></form>',
      );
}
