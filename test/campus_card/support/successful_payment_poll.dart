// Response shape from the 2026-09-09 capture. Identity, order, merchant and
// amount values are synthetic; no HAR credentials or live payment codes remain.
const successfulPaymentPoll = <String, Object?>{
  'success': true,
  'message': '',
  'title': '',
  'url': '/pages/common/success/success',
  'data': <String, Object?>{
    'status': '1',
    'message': '支付成功',
    'txamt': '8.80',
    'paytime': '2026-09-09 14:39:44',
    'authcode': 'SYNTHETIC-AUTH-CODE',
    'journo': 'SYNTHETIC-ORDER',
    'merchantname': '示例商户',
  },
};
