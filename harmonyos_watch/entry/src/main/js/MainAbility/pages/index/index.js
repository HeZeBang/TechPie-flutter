import app from '@system.app';
import {startOfflineCode} from '../../common/offline-code.js';

var application, focusTimer, paintTimer;
var QR_SIDE = 265;
function time(value) {
  var d = new Date(value + 28800000);
  return ('0' + d.getUTCHours()).slice(-2) + ':' + ('0' + d.getUTCMinutes()).slice(-2);
}
function date(value) {
  var d = new Date(value + 28800000);
  return (d.getUTCMonth() + 1) + '/' + d.getUTCDate();
}
function failOffline(run, reason) {
  var page = run.page;
  page.cancelCode(); page._failedGrant = run.grant; page._prepared = null;
  page._failureText = '离线码失败 · ' + reason;
  console.error('TechPie offline error=' + reason);
  page.applyState(application.watchState());
}
function offlineSlice(run) {
  var page = run.page;
  if (page._work !== run) return;
  if (!page._visible || page.view !== 'deck' || page.pageIndex !== 0 ||
      Date.now() - run.last > 2000 || application.watchCredential() !== run.grant) {
    page.cancelCode(); return;
  }
  try {
    if (!run.frame) {
      if (!run.signer) run.signer = startOfflineCode(run.grant, page._prepared, application.watchRandom, application.watchNow, run.points);
      run.frame = run.signer.step();
      if (run.frame) {
        page._prepared = run.signer.prepared; run.signer = null; run.signedAt = Date.now();
        console.info('TechPie offline prepareAndSignMs=' + (run.signedAt - run.start));
      }
    } else {
      if (!run.matrixStep) run.matrixStep = application.watchMatrix(run.frame.payload);
      var matrix = run.matrixStep();
      if (matrix) {
        if (run.frame.until <= application.watchNow()) throw Error('OFFLINE_CODE_EXPIRED');
        console.info('TechPie offline encodeMs=' + (Date.now() - run.signedAt));
        matrix.id = 'local-' + run.start; matrix.until = run.frame.until;
        page._localCode = matrix; page._shownGrant = run.grant; page._codeStarted = run.start;
        page.cancelCode(); page.applyState(application.watchState()); return;
      }
    }
    run.last = Date.now(); page._codeTimer = setTimeout(run.tick, 16);
  } catch (error) { failOffline(run, error.message); }
}
export default {
  data: {
    view: 'deck', crownError: '', pageIndex: 0, connected: false, status: '等待首次同步',
    name: '', studentId: '', error: '', detailTitle: '', rows: [], dayOffset: 0,
    dayLabel: '', courseCount: 0, ddlCount: 0, coursePreview: [], ddlPreview: [],
    emptyCourse: '今天没有课', codeVisible: false, codeHint: '',
    codeMessage: '打开手机完成首次同步', lastSync: '', alertTitle: ''
  },
  onInit() {
    console.info('TechPie page created');
    try { application = getApp().data.api; }
    catch (error) { this.codeMessage = '应用状态读取失败'; console.error('TechPie app state: ' + String(error)); }
  },
  onReady() { this.enterPage(); },
  onShow() { this.enterPage(); },
  enterPage() {
    if (this._visible || !application) return;
    this._visible = true; this._visit = (this._visit || 0) + 1;
    this.view = 'deck'; this.pageIndex = 0;
    this._needCode = true; this._requestedOnline = false;
    this._unpaintable = null; this._shownGrant = null;
    var page = this, visit = this._visit;
    application.watchResume();
    application.watchObserve(function(state) {
      if (page._visible && visit === page._visit) page.applyState(state);
    }, function() { page.leavePage(); });
    this.focusCrown();
    console.info('TechPie page ready');
  },
  onHide() { this.leavePage(); },
  onDestroy() { this.leavePage(); },
  leavePage() {
    if (!this._visible) return;
    this._visible = false;
    application.watchPause();
    this.cancelCode();
    clearTimeout(focusTimer); clearTimeout(paintTimer);
    focusTimer = null; paintTimer = null;
    this._prepared = null; this._localCode = null; this._failedGrant = null; this._shownGrant = null;
    this._listState = null;
    this._codeId = null; this._codeStarted = null;
    // Do not change the swiper or canvas while the native view is being hidden.
  },
  onBackPress() { if (this.view !== 'deck') { this.goBack(); return true; } return false; },
  onSwipe(event) { if (event.direction === 'right') this.goBack(); },
  goBack() {
    if (this.view === 'deck') { app.terminate(); return; }
    this.view = 'deck'; this.focusCrown();
    if (this.pageIndex === 0) { this._needCode = true; this._requestedOnline = false; this.applyState(application.watchState()); }
  },
  onPageChange(event) {
    if (!this._visible || event.index === this.pageIndex) return;
    this._needCode = true; this._requestedOnline = false;
    this.pageIndex = event.index;
    if (event.index === 0) this.applyState(application.watchState());
    else { this.cancelCode(); application.watchHideCode(); }
  },
  focusCrown() {
    var page = this, visit = this._visit;
    if (focusTimer) clearTimeout(focusTimer);
    focusTimer = setTimeout(function() {
      if (!page._visible || page._visit !== visit) return;
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
  showAccount() { this.cancelCode(); this._codeId = null; this.view = 'account'; this.detailTitle = '我的信息'; this.focusCrown(); },
  previousDay() { if (this.dayOffset > 0) { this.dayOffset--; this.applyState(application.watchState()); } },
  nextDay() { if (this.dayOffset < 6) { this.dayOffset++; this.applyState(application.watchState()); } },
  synchronize() { application.watchSync(); },
  applyState(state) {
    if (!this._visible || !state) return;
    var now = application.watchNow();
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
    this.updateLists(state, now);
    var credential = application.watchCredential();
    if (this._work && this._work.grant !== credential) this.cancelCode();
    if (this._failedGrant !== credential) this._failedGrant = null;
    if (!credential || (this._prepared && this._prepared.grant !== credential)) {
      this._localCode = null; this._prepared = null;
    }
    if (this._localCode && this._localCode.until <= now) this._localCode = null;
    var code = this._localCode || (state.code && state.code.until > now ? state.code : null);
    if (code && code.id === this._unpaintable) code = null;
    if (!state.connected) this._requestedOnline = false;
    var seconds = code ? Math.max(0, Math.ceil((code.until - now) / 1000)) : 0;
    this.codeVisible = !!code && this.pageIndex === 0 && this.view === 'deck';
    this.codeMessage = code ? (this._localCode ? '离线码 · ' : '在线码 · ') + seconds + ' 秒' :
      (this._failedGrant || this._unpaintable ? this._failureText : this._work ? '正在生成离线码' :
        state.codeLoading ? '正在获取在线码' : credential || state.connected ? '轻触刷新校园码' : '请打开手机 TechPie');
    this.codeHint = code ? '' : this._failedGrant || this._unpaintable ? '轻触重试' :
      this._work ? '约 10 秒' : state.codeLoading ? '等待手机响应' :
      credential || state.connected ? '' : '连接后同步校园码';
    if (this.codeVisible) {
      this._needCode = false;
      if (this._codeId !== code.id) this.drawCode(code);
    } else if (this._needCode && this.pageIndex === 0 && this.view === 'deck' && !this._work && !this._unpaintable) {
      if (state.connected && !this._requestedOnline) {
        this._requestedOnline = true;
        if (!state.codeLoading) application.watchCode();
      } else if (credential && credential !== this._shownGrant && !state.codeLoading && !this._failedGrant) {
        this.refreshCode();
      }
    }
    if (!code) this._codeId = null;
  },
  updateLists(state, now) {
    var cached = this._listState;
    if (cached && cached.courses === state.schedule && cached.tasks === state.ddl &&
        cached.view === this.view && cached.dayOffset === this.dayOffset &&
        now >= cached.at && now < cached.until) return;
    var day = 86400000, start = Math.floor((now + 28800000) / day) * day - 28800000;
    cached = this._listState = {courses: state.schedule, tasks: state.ddl, view: this.view,
      dayOffset: this.dayOffset, at: now, until: start + day};
    var courses = state.schedule || [], all = (state.ddl || []).filter(function(item) { return item.status === 'open'; });
    var today = courses.filter(function(item) { return item.startAtMs >= start && item.startAtMs < start + 86400000; });
    for (var j = 0; j < today.length; j++) {
      var end = today[j].endAtMs;
      if (end > now && end < cached.until) cached.until = end;
    }
    this.courseCount = today.length; this.ddlCount = all.length;
    this.emptyCourse = today.length ? '今天的课程已结束' : '今天没有课';
    this.coursePreview = today.filter(function(item) { return item.endAtMs > now; }).slice(0, 3)
      .map(function(item) { return {title: item.name, caption: time(item.startAtMs) + '–' + time(item.endAtMs) + (item.location ? ' · ' + item.location : '')}; });
    this.ddlPreview = all.slice(0, 3).map(function(item) {
      var urgentAt = item.dueAtMs - day;
      if (urgentAt > now && urgentAt < cached.until) cached.until = urgentAt;
      return {title: item.title, caption: date(item.dueAtMs) + ' ' + time(item.dueAtMs) + (item.courseName ? ' · ' + item.courseName : ''),
        urgent: item.dueAtMs <= now + 86400000};
    });
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
  },
  cancelCode() {
    if (this._codeTimer) clearTimeout(this._codeTimer);
    this._codeTimer = null; this._work = null;
  },
  refreshCode() {
    if (!this._visible || this.pageIndex !== 0 || this.view !== 'deck') return;
    this._needCode = false; this._unpaintable = null;
    var page = this, grant = application.watchCredential();
    if (!grant) { if (this.connected) application.watchCode(); else application.watchSync(); return; }
    if (this._work) return;
    var run = {page: this, grant: grant, start: Date.now()};
    this._work = run; this._failedGrant = null;
    this.codeMessage = '正在生成离线码'; this.codeHint = '约 10 秒';
    run.tick = offlineSlice.bind(null, run);
    run.points = function(index) { return page.$t('sm2.p' + index); };
    run.last = Date.now();
    this._codeTimer = setTimeout(run.tick, 150);
  },
  drawCode(code) {
    var page = this, visit = this._visit;
    if (paintTimer) clearTimeout(paintTimer);
    paintTimer = setTimeout(function() {
      if (!page._visible || page._visit !== visit || !page.codeVisible || code.until <= application.watchNow()) return;
      var canvas = page.$refs.qr || (page.$element && page.$element('campusQr'));
      if (!canvas) {
        page._unpaintable = code.id; page.codeVisible = false;
        page._failedGrant = application.watchCredential();
        page._failureText = '画布未就绪，轻触重试'; page.codeMessage = page._failureText;
        console.error('TechPie canvas unavailable'); return;
      }
      var paintStart = Date.now(), ctx = canvas.getContext('2d'), size = code.size;
      var cell = Math.floor(QR_SIDE / (size + 8)), offset = Math.floor((QR_SIDE - size * cell) / 2);
      ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, QR_SIDE, QR_SIDE); ctx.fillStyle = '#000000';
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
      page._codeId = code.id;
      console.info('TechPie campus paintMs=' + (Date.now() - paintStart));
      if (page._codeStarted && code.id.indexOf('local-') === 0) {
        console.info('TechPie offline code totalMs=' + (Date.now() - page._codeStarted)); page._codeStarted = null;
      }
    }, 50);
  }
};
