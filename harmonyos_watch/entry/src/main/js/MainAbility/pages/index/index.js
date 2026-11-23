import app from '@system.app';

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
  onReady() { this.enterPage(); },
  onShow() { this.enterPage(); },
  enterPage() {
    if (this._visible || !application) return;
    this._visible = true; this._visit = (this._visit || 0) + 1;
    this._needCode = true;
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
    clearTimeout(focusTimer); clearTimeout(paintTimer);
    focusTimer = null; paintTimer = null;
    this._codeId = null;
    // Do not change the swiper or canvas while the native view is being hidden.
  },
  onBackPress() { if (this.view !== 'deck') { this.goBack(); return true; } return false; },
  onSwipe(event) { if (event.direction === 'right') this.goBack(); },
  goBack() {
    if (this.view === 'deck') { app.terminate(); return; }
    this.view = 'deck'; this.focusCrown();
    if (this.pageIndex === 0) this.refreshCode();
  },
  onPageChange(event) {
    if (!this._visible || event.index === this.pageIndex) return;
    this._needCode = true;
    this.pageIndex = event.index;
    if (event.index === 0) this.applyState(application.watchState());
    else application.watchHideCode();
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
  showAccount() { this.view = 'account'; application.watchHideCode(); this.detailTitle = '我的信息'; this.focusCrown(); },
  previousDay() { if (this.dayOffset > 0) { this.dayOffset--; this.applyState(application.watchState()); } },
  nextDay() { if (this.dayOffset < 6) { this.dayOffset++; this.applyState(application.watchState()); } },
  synchronize() { application.watchSync(); },
  applyState(state) {
    if (!this._visible || !state) return;
    var now = application.watchNow(), d = new Date(now + 28800000);
    var start = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - 28800000;
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
    var code = state.code && state.code.until > now ? state.code : null;
    var seconds = code ? Math.max(0, Math.ceil((code.until - now) / 1000)) : 0;
    this.codeVisible = !!code && this.pageIndex === 0 && this.view === 'deck';
    this.codeMessage = code ? '在线码 · ' + seconds + ' 秒' :
      (!state.connected ? '请打开手机 TechPie 连接手表' :
        state.codeLoading ? '正在获取在线码' : state.error || '轻触获取在线码');
    if (!state.connected) this._needCode = true;
    if (this.codeVisible && this._codeId !== code.id) this.drawCode(code);
    if (this._needCode && this.pageIndex === 0 && this.view === 'deck' && state.connected) {
      this._needCode = false;
      if (!code) this.refreshCode();
    }
    if (!this.codeVisible) this._codeId = null;
  },
  refreshCode() {
    if (!this._visible || this.pageIndex !== 0 || this.view !== 'deck') return;
    this._needCode = false;
    application.watchCode();
  },
  drawCode(code) {
    var page = this, visit = this._visit;
    if (paintTimer) clearTimeout(paintTimer);
    paintTimer = setTimeout(function() {
      if (!page._visible || page._visit !== visit || !page.codeVisible || code.until <= application.watchNow()) return;
      var ctx = page.$refs.qr.getContext('2d'), size = code.size;
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
      page._codeId = code.id;
    }, 50);
  }
};
