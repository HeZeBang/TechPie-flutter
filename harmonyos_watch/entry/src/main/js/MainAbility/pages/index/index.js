export default {
  data: {
    title: 'TechPie',
    clock: '--:--',
    date: '',
    message: '等待手机同步',
    detail: '校园卡与课表尚未接入',
    buttonLabel: '查看同步状态',
    showingStatus: false
  },
  onInit() {
    this.refreshClock();
  },
  onShow() {
    this.refreshClock();
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
    this.message = this.showingStatus ? '尚未绑定手机' : '等待手机同步';
    this.detail = this.showingStatus ? 'Wear Engine 通信尚未接入' : '校园卡与课表尚未接入';
    this.buttonLabel = this.showingStatus ? '返回首页' : '查看同步状态';
  }
};
