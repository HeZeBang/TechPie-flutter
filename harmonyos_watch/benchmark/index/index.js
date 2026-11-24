import router from '@system.router';
import app from '@system.app';

// Pass the run to each native timer as a bound argument. All slices use the
// same job, page and callback until this visit ends.
function signSlice(run) {
  var page = run.page;
  if (!page._visible || page._run !== run) return;
  var now = Date.now(), stage = '初始化';
  try {
    if (run.last && now - run.last > 2000) {
      page.status = '测试已暂停，请重试';
    } else {
      if (!run.job) {
        run.start = now;
        console.info('TechPie bench sign start');
        var fixture = require('./signature-fixture.js');
        run.expected = fixture.expected;
        run.job = require('../../common/sm2.js').makeSigner(require('../../common/sm2-points.json')).makeSignJob(fixture.opts);
        console.info('TechPie bench job ready');
      }
      stage = '计算';
      var count = 0, finished;
      do { finished = run.job.step(); count++; }
      while (!finished && count < 8 && Date.now() - now < 8);
      var end = Date.now();
      run.activeMs += end - now;
      run.slices++;
      if (!finished) {
        stage = '调度';
        run.last = end; page._timer = setTimeout(run.tick, 1); return;
      }
      stage = '校验';
      var elapsed = end - run.start, ok = run.job.result() === run.expected;
      page.status = ok ? '签名正确 ' + elapsed + ' ms' : '签名校验失败';
      page.timing = '执行 ' + run.activeMs + ' / 等待 ' + (elapsed - run.activeMs) + ' ms';
      console.info('TechPie bench sign ok=' + (ok ? 1 : 0) + ' ms=' + elapsed + ' active=' + run.activeMs + ' wait=' + (elapsed - run.activeMs) + ' slices=' + run.slices);
    }
  } catch (error) {
    page.status = stage + '失败 · 第 ' + (run.slices + 1) + ' 段';
    page.timing = String(error).slice(0, 64);
    console.error('TechPie bench sign failed ' + page.status + ' ' + page.timing);
  }
  page.busy = false; page._run = null; page._timer = null;
}

export default {
  data: {status: '使用固定测试数据', picture: false, busy: false, timing: ''},
  onReady() { this._visible = true; },
  onShow() { this._visible = true; },
  onHide() { this.stop(); },
  onDestroy() { this.stop(); },
  stop() {
    this._visible = false;
    this._run = null;
    clearTimeout(this._timer);
    this._timer = null;
    this.busy = false; this.picture = false;
  },
  back() {
    if (this.picture) {
      clearTimeout(this._timer); this._run = null; this.busy = false; this.picture = false; return;
    }
    this.stop();
    app.terminate();
  },
  openCompanion() {
    if (this.busy) return;
    router.replace({uri: 'pages/companion/companion'});
  },
  onBackPress() { this.back(); return true; },
  onSwipe(event) { if (event.direction === 'right') this.back(); },
  sign() {
    if (!this._visible || this.busy) return;
    var run = {page: this, job: null, activeMs: 0, slices: 0, last: 0};
    run.tick = signSlice.bind(null, run);
    this._run = run; this.busy = true;
    this.status = '签名测试中'; this.timing = '';
    this._timer = setTimeout(run.tick, 50);
  },
  draw() {
    if (!this._visible || this.busy || this.picture) return;
    this.busy = true; this.picture = true; this.timing = ''; this.status = '正在绘制';
    var page = this, run = {};
    this._run = run;
    this._timer = setTimeout(function() {
      if (page._run !== run || !page._visible || !page.picture) return;
      try {
        var matrix = require('./matrix-fixture.js');
        var paint = require('./paint-matrix.js');
        var start = Date.now();
        paint(page.$refs.qr.getContext('2d'), matrix);
        var ms = Date.now() - start;
        page.status = '绘制提交 ' + ms + ' ms';
        console.info('TechPie bench draw ms=' + ms);
      } catch (err) { page.picture = false; page.status = '绘制失败'; }
      page.busy = false; page._run = null;
    }, 50);
  }
};
