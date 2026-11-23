import app from '@system.app';
import {prepareCredential, generateOfflineCode} from '../../common/offline-code.js';

var application, focusTimer, paintTimer;
function time(value) {
  var d = new Date(value + 28800000);
  return ('0' + d.getUTCHours()).slice(-2) + ':' + ('0' + d.getUTCMinutes()).slice(-2);
}
function date(value) {
  var d = new Date(value + 28800000);
  return (d.getUTCMonth() + 1) + '/' + d.getUTCDate();
}
export default {
  data: {
    view: 'deck', crownError: '', pageIndex: 0, connected: false, status: '等待首次同步',
    name: '', studentId: '', error: '', detailTitle: '', rows: [], dayOffset: 0,
    dayLabel: '', courseCount: 0, ddlCount: 0, courseName: '今天没有课程',
    courseTime: '今日课表', courseLocation: '', ddlTitle: '暂无待办',
    ddlDue: '即将截止', ddlCourse: '', codeVisible: false,
    codeMessage: '打开手机完成首次同步', lastSync: '', alertTitle: ''
  },
  onInit() {
    console.info('TechPie page created');
    try { application = getApp().data.api; }
    catch (error) { this.codeMessage = '应用状态读取失败'; console.error('TechPie app state: ' + String(error)); }
  },
  onReady() {
    try {
      this.observe(); application.watchResume(); this.focusCrown(); this.refreshCode();
      this._started = true; console.info('TechPie page ready');
    } catch (error) {
      this.codeMessage = '数据初始化失败，请重新打开';
      console.error('TechPie page startup: ' + String(error));
    }
  },
  onShow() {
    if (this._started) { this.observe(); application.watchResume(); this.focusCrown(); }
  },
  observe() {
    var page = this;
    application.watchObserve(function(state) { page.applyState(state); });
  },
  onHide() { this.view = 'deck'; this.pageIndex = 0; this.codeVisible = false; this._localCode = null; if (this._started) application.watchPause(); },
  onDestroy() {
    if (focusTimer) clearTimeout(focusTimer);
    if (paintTimer) clearTimeout(paintTimer);
    if (this._started) application.watchPause();
  },
  onBackPress() { if (this.view !== 'deck') { this.goBack(); return true; } return false; },
  onSwipe(event) { if (event.direction === 'right') this.goBack(); },
  goBack() {
    if (this.view === 'deck') { app.terminate(); return; }
    this.view = 'deck'; this.focusCrown();
    if (this.pageIndex === 0) this.refreshCode();
  },
  onPageChange(event) {
    this.pageIndex = event.index;
    if (event.index === 0) { this.applyState(application.watchState()); this.refreshCode(); }
    else application.watchHideCode();
  },
  focusCrown() {
    var page = this;
    if (focusTimer) clearTimeout(focusTimer);
    focusTimer = setTimeout(function() {
      try {
        var control = page.view === 'deck' ? page.$refs.deck : page.$refs.details;
        control.rotation({focus: true}); page.crownError = '';
      } catch (error) {
        page.crownError = '表冠初始化失败';
        console.error('TechPie Crown focus: ' + String(error));
      }
    }, 50);
  },
  showSchedule() { this.view = 'schedule'; this.dayOffset = 0; this.applyState(application.watchState()); this.focusCrown(); },
  showDdl() { this.view = 'ddl'; this.applyState(application.watchState()); this.focusCrown(); },
  showAccount() { this.view = 'account'; this.detailTitle = '我的信息'; this.focusCrown(); },
  previousDay() { if (this.dayOffset > 0) { this.dayOffset--; this.applyState(application.watchState()); } },
  nextDay() { if (this.dayOffset < 6) { this.dayOffset++; this.applyState(application.watchState()); } },
  synchronize() { application.watchSync(); },
  applyState(state) {
    if (!state) return;
    var now = application.watchNow(), d = new Date(now + 28800000);
    var start = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - 28800000;
    var becameConnected = state.connected && !this.connected;
    this.connected = state.connected;
    this.lastSync = state.updatedAt ? date(state.updatedAt) + ' ' + time(state.updatedAt) : '尚未同步';
    this.status = state.connected ? '已同步' : (state.updatedAt ? '本地数据 · ' + this.lastSync : '等待首次同步');
    this.name = state.name || '待同步'; this.studentId = state.studentId || '待同步';
    this.error = state.error || ''; this.alertTitle = state.alert ? state.alert.title : '';
    if (!state.alert) this._alertId = null;
    if (state.alert && this._alertId !== state.alert.id) {
      this._alertId = state.alert.id;
      var page = this;
      try {
        require('../../common/wear-vibrator.js').default.vibrate({mode: 'long', fail: function() { page.error = '振动失败，请查看待办'; }});
      } catch (error) { this.error = '振动不可用，请查看待办'; console.error('TechPie vibration: ' + String(error)); }
    }
    var courses = state.schedule || [], all = (state.ddl || []).filter(function(item) { return item.status === 'open'; });
    var today = courses.filter(function(item) { return item.startAtMs >= start && item.startAtMs < start + 86400000; });
    var next = today.filter(function(item) { return item.endAtMs > now; })[0];
    this.courseCount = today.length; this.ddlCount = all.length;
    this.courseName = next ? next.name : (today.length ? '今天的课程已结束' : '今天没有课程');
    this.courseTime = next ? time(next.startAtMs) + ' – ' + time(next.endAtMs) : '好好安排今天';
    this.courseLocation = next ? next.location : '';
    var due = all.filter(function(item) { return item.dueAtMs > now; })[0] || all[0];
    this.ddlTitle = due ? due.title : '暂无待办'; this.ddlCourse = due ? due.courseName : '';
    this.ddlDue = due ? (due.dueAtMs < now ? '已逾期 · ' : '') + date(due.dueAtMs) + ' ' + time(due.dueAtMs) : '今天轻松一点';
    var from = start + this.dayOffset * 86400000;
    this.dayLabel = date(from) + ' 周' + '日一二三四五六'.charAt(new Date(from + 28800000).getUTCDay());
    if (this.view === 'schedule') {
      this.detailTitle = '课表';
      this.rows = courses.filter(function(item) { return item.startAtMs >= from && item.startAtMs < from + 86400000; })
        .map(function(item) { return {title: item.name, caption: time(item.startAtMs) + ' – ' + time(item.endAtMs), detail: item.location}; });
    } else if (this.view === 'ddl') {
      this.detailTitle = '待办';
      this.rows = all.map(function(item) { return {title: item.title, caption: date(item.dueAtMs) + ' ' + time(item.dueAtMs), detail: item.courseName}; });
    }
    var credential = application.watchCredential();
    if (!credential || (this._prepared && this._prepared.grant !== credential)) {
      this._localCode = null; this._prepared = null;
    }
    if (this._localCode && this._localCode.until <= now) this._localCode = null;
    var code = this._localCode || state.code;
    var seconds = code ? Math.max(0, Math.ceil((code.until - now) / 1000)) : 0;
    this.codeVisible = !!code && this.pageIndex === 0 && this.view === 'deck';
    this.codeMessage = code ? (this._localCode ? '离线码 · ' : '') + seconds + ' 秒' :
      (state.codeLoading ? '正在更新校园码' : (state.connected ? '轻触此处获取校园码' : '连接手机同步离线授权'));
    if (this.codeVisible && this._codeId !== code.id) this.drawCode(code);
    if (this.pageIndex === 0 && this.view === 'deck' && !this._generating &&
        ((credential && !code) || (becameConnected && !code) || (code && seconds <= 10 && !state.codeLoading && this._requested !== code.id))) {
      this._requested = code ? code.id : 'initial'; this.refreshCode();
    }
    if (!this.codeVisible) this._codeId = null;
  },
  refreshCode() {
    var credential = application.watchCredential();
    if (!credential) { application.watchCode(); return; }
    if (this._generating) return;
    this._generating = true;
    var began = Date.now();
    try {
      if (!this._prepared || this._prepared.grant !== credential) this._prepared = prepareCredential(credential, application.watchRandom);
      var frame = generateOfflineCode(this._prepared, application.watchNow());
      var matrix = application.watchMatrix(frame.payload);
      matrix.id = 'local-' + application.watchNow(); matrix.until = frame.until;
      this._localCode = matrix; this._codeStarted = began;
      this.applyState(application.watchState());
    } catch (error) {
      this._localCode = null;
      this.codeVisible = false; this.codeMessage = '离线码生成失败，请重新同步授权';
      console.error('TechPie offline generation failed: ' + error.message);
    }
    this._generating = false;
  },
  drawCode(code) {
    var page = this;
    if (paintTimer) clearTimeout(paintTimer);
    paintTimer = setTimeout(function() {
      if (!page.codeVisible) return;
      var ctx = page.$refs.qr.getContext('2d'), size = code.size;
      var cell = Math.floor(264 / (size + 8)), offset = Math.floor((264 - size * cell) / 2);
      ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, 264, 264); ctx.fillStyle = '#000000';
      for (var row = 0; row < size; row++) for (var col = 0; col < size; col++) {
        var bit = row * size + col;
        if (code.bytes[Math.floor(bit / 8)] & (1 << (7 - bit % 8))) ctx.fillRect(offset + col * cell, offset + row * cell, cell, cell);
      }
      page._codeId = code.id;
      if (page._codeStarted && code.id.indexOf('local-') === 0) {
        console.info('TechPie offline code totalMs=' + (Date.now() - page._codeStarted)); page._codeStarted = null;
      }
    }, 50);
  }
};
