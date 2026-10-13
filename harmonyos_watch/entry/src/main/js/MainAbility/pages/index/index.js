import { WearLink } from '../../common/wear-link.js';

var link;
export default {
  data: {
    title: 'TechPie',
    clock: '--:--',
    date: '',
    message: '未连接',
    detail: '请在手机TechPie → Settings 中连接此 HUAWEI WATCH',
    user: '',
    buttonLabel: '连接说明',
    showingStatus: false
  },
  onInit() {
    this.refreshClock();
    var page = this;
    link = new WearLink(function(state) {
      page.message = state.connected ? '已连接' : '未连接';
      page.user = state.name ? state.name + ' · ' + state.studentId : '';
      page.detail = state.error || (state.connected ? '已连接手机 TechPie' : '请在手机 Settings 中连接 HUAWEI WATCH');
    });
    link.start();
  },
  onShow() {
    this.refreshClock();
    if (link) link.start();
  },
  onHide() {
    if (link) link.stop();
  },
  onDestroy() {
    if (link) link.stop();
    link = null;
  },
  refreshClock() {
    var now = new Date();
    var hours = now.getHours();
    var minutes = now.getMinutes();
    this.clock = (hours < 10 ? '0' : '') + hours + ':' +
      (minutes < 10 ? '0' : '') + minutes;
    this.date = (now.getMonth() + 1) + '月' + now.getDate() + '日';
  },
  toggleStatus() {
    this.refreshClock();
    this.showingStatus = !this.showingStatus;
    this.detail = this.showingStatus ? '确认华为运动健康已连接手表后，在TechPie手机端应用的Settings/HUAWEI WATCH中绑定手表' :
      (link && link.connection.ready ? '已连接手机 TechPie' : '请在手机 Settings 中连接 HUAWEI WATCH');
    this.buttonLabel = this.showingStatus ? '返回首页' : '连接说明';
    if (link && !link.client) link.start();
  }
};
