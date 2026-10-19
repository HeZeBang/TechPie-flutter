import { WearLink } from '../../common/wear-link.js';

var link, paintTimer, refreshTimer;
function short(value, length) { return value.length > length ? value.slice(0, length - 1) + '…' : value; }
function dueLabel(ms) {
  var date = new Date(ms + 28800000);
  return (date.getUTCMonth() + 1) + '/' + date.getUTCDate() + ' ' +
    ('0' + date.getUTCHours()).slice(-2) + ':' + ('0' + date.getUTCMinutes()).slice(-2);
}
export default {
  data: {
    view: 'home', connected: false, status: '未连接', name: '', studentId: '',
    detail: '打开手机 TechPie 连接手表', nextTitle: '连接后同步待办', nextDue: '',
    deadlines: [], ddlReady: false, ddlEmpty: '等待手机同步', pageNumber: 0,
    pageLabel: '', hasPrevious: false, hasNext: false, truncated: false,
    syncing: false, syncLabel: '更新待办', codeVisible: false, codeLoading: false,
    codeLabel: '获取校园码', codeMessage: '校园码仅在连接期间可用', codeSeconds: 0,
    error: '', updated: ''
  },
  onInit() {
    var page = this;
    link = new WearLink(function(state) { page.applyState(state); });
    link.start();
  },
  onShow() { if (link) link.start(); },
  onReady() { this.drawCode(); },
  onHide() {
    this.view = 'home'; this.codeVisible = false;
    if (paintTimer) clearTimeout(paintTimer);
    if (refreshTimer) clearTimeout(refreshTimer);
    if (link) link.stop();
  },
  onDestroy() {
    if (paintTimer) clearTimeout(paintTimer);
    if (refreshTimer) clearTimeout(refreshTimer);
    if (link) link.stop(); link = null;
  },
  onBackPress() {
    if (this.view !== 'home') { this.goHome(); return true; }
    return false;
  },
  applyState(state) {
    this.connected = state.connected; this.status = state.connected ? '已连接' : '未连接';
    this.name = state.name || ''; this.studentId = state.studentId || '';
    this.error = state.error || ''; this.syncing = state.syncing || false;
    this.syncLabel = this.syncing ? '正在更新…' : '更新待办';
    this.ddlReady = state.ddlReady || false; this.truncated = state.truncated || false;
    this.updated = state.updatedAt ? '更新于 ' + dueLabel(state.updatedAt) : '';
    var all = (state.ddl || []).filter(function(item) { return item.status === 'open'; });
    this.pageNumber = Math.min(this.pageNumber, Math.max(0, Math.ceil(all.length / 6) - 1));
    var now = link && link.connection.ready ? link.connection.phoneNow() : Date.now();
    this.deadlines = all.slice(this.pageNumber * 6, (this.pageNumber + 1) * 6).map(function(item) {
      return {id: item.id, title: short(item.title, 32), course: short(item.courseName, 20),
        due: dueLabel(item.dueAtMs), hint: item.dueAtMs <= now ? '已逾期' :
          (item.dueAtMs - now < 86400000 ? '24 小时内截止' : '待完成')};
    });
    this.ddlEmpty = this.ddlReady ? '暂时没有待办' : '等待手机同步';
    this.pageLabel = all.length ? (this.pageNumber + 1) + ' / ' + Math.ceil(all.length / 6) : '';
    this.hasPrevious = this.pageNumber > 0; this.hasNext = (this.pageNumber + 1) * 6 < all.length;
    var next = all.filter(function(item) { return item.dueAtMs > now; })[0];
    this.nextTitle = next ? short(next.title, 20) : (this.ddlReady ? '还没有即将截止的待办哦' : '连接后同步待办');
    this.nextDue = next ? dueLabel(next.dueAtMs) + ' 截止' : '';
    this.detail = state.connected ? '与手机 TechPie 保持连接' : '打开手机 TechPie 连接手表';
    this.codeLoading = state.codeLoading || false;
    this.codeLabel = this.codeLoading ? '正在获取…' : '刷新校园码';
    this.codeSeconds = state.codeSeconds || 0;
    this.codeVisible = this.view === 'code' && !!state.code;
    this.codeMessage = this.codeLoading ? '正在向手机获取校园码' :
      (this.codeVisible ? '剩余 ' + this.codeSeconds + ' 秒' :
        (state.connected ? '点击刷新获取有效校园码' : '请先连接手机 TechPie'));
    if (this.codeVisible && this._paintedCode !== state.code.id) this.drawCode();
    if (!this.codeVisible) this._paintedCode = null;
    if (this.codeVisible && !this.codeLoading && this.codeSeconds <= 10 &&
        this._autoRequested !== state.code.id && link.connection.now() - state.code.requestAt >= 6000) {
      this._autoRequested = state.code.id;
      var page = this, id = state.code.id;
      refreshTimer = setTimeout(function() {
        if (link && page.view === 'code' && link.connection.code && link.connection.code.id === id) {
          link.connection.request('code');
        }
      }, 0);
    }
  },
  goHome() {
    this.view = 'home'; this.codeVisible = false;
    if (refreshTimer) clearTimeout(refreshTimer);
    if (link) link.connection.hideCode();
  },
  showDdl() { this.view = 'ddl'; this.pageNumber = 0; if (link) link.connection.publish(); },
  showAccount() { this.view = 'account'; },
  showGuide() { this.view = 'guide'; },
  showCode() { this.view = 'code'; this.refreshCode(); },
  refreshCode() {
    if (link && !this.codeLoading) link.connection.request('code');
    if (link) link.connection.publish();
  },
  refreshDdl() { if (link && !this.syncing) link.connection.request('sync'); },
  previousPage() { if (this.hasPrevious) { this.pageNumber--; link.connection.publish(); } },
  nextPage() { if (this.hasNext) { this.pageNumber++; link.connection.publish(); } },
  retryConnection() { if (link) { link.stop(); link.start(); } },
  drawCode() {
    var page = this;
    if (paintTimer) clearTimeout(paintTimer);
    paintTimer = setTimeout(function() {
      if (!link || page.view !== 'code' || !page.codeVisible || !link.connection.code) return;
      var code = link.connection.code;
      try {
        var ctx = page.$refs.qr.getContext('2d'), size = code.size;
        var cell = Math.floor(264 / (size + 8)), offset = Math.floor((264 - size * cell) / 2);
        ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, 264, 264);
        ctx.fillStyle = '#000000';
        for (var row = 0; row < size; row++) {
          for (var col = 0; col < size; col++) {
            var bit = row * size + col;
            if (code.bytes[Math.floor(bit / 8)] & (1 << (7 - bit % 8))) {
              ctx.fillRect(offset + col * cell, offset + row * cell, cell, cell);
            }
          }
        }
        page._paintedCode = code.id;
      } catch (_) {
        page.codeVisible = false; link.connection.hideCode();
        page.codeMessage = '呜呜，显示失败了…使用手机校园码吧！可以和开发者反馈哦~';
      }
    }, 0);
  }
};
