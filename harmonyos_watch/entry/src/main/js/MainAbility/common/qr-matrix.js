import qrcode from './vendor/qrcode.js';

export function startQr(bytes) {
  var text = '';
  for (var i = 0; i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
  var qr = qrcode(0, 'M'); qr.addData(text, 'Byte'); var step = qr.start();
  return function() {
    if (!step()) return null;
    var at = Date.now(), matrix = pack(qr);
    var t = qr.times;
    console.info('TechPie QR size=' + matrix.size + ' select=' + t.select + ' data=' + t.data +
      ' layout=' + t.layout + ' score=' + t.score + ' pack=' + (Date.now() - at));
    return matrix;
  };
}
function pack(qr) {
  var size = qr.getModuleCount(), packed = [];
  for (var row = 0; row < size; row++) for (var col = 0; col < size; col++) {
    var bit = row * size + col, index = Math.floor(bit / 8);
    if (bit % 8 === 0) packed[index] = 0;
    if (qr.isDark(row, col)) packed[index] |= 1 << (7 - bit % 8);
  }
  return {size: size, bytes: packed};
}
