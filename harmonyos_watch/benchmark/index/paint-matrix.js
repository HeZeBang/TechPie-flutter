module.exports = function paintMatrix(ctx, code) {
  var size = code.size;
  var cell = Math.floor(264 / (size + 8)), offset = Math.floor((264 - size * cell) / 2);
  ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, 264, 264); ctx.fillStyle = '#000000';
  for (var row = 0; row < size; row++) {
    var start = -1;
    for (var col = 0; col <= size; col++) {
      var bit = row * size + col;
      var dark = col < size && (code.bytes[bit >> 3] & (128 >> (bit % 8)));
      if (dark && start < 0) start = col;
      if (!dark && start >= 0) {
        ctx.fillRect(offset + start * cell, offset + row * cell, (col - start) * cell, cell);
        start = -1;
      }
    }
  }
};
