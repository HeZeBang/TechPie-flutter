enum WizardStep { welcome, permission, code, success, retry, account }

({String title, String description}) wizardHeading(
  WizardStep step, {
  required bool ios,
  required bool chinese,
}) =>
    switch ((step, ios, chinese)) {
      (WizardStep.welcome, true, false) => (
          title: 'Connect your eCard',
          description: 'Use your campus card in TechPie for payments and card activity.'
        ),
      (WizardStep.permission, true, false) => (
          title: 'Allow temporary VPN access',
          description: ''
        ),
      (WizardStep.code, true, false) => (title: 'Enter your binding code', description: ''),
      (WizardStep.success, true, false) => (
          title: 'eCard connected',
          description: 'Your campus card is ready to use in TechPie.'
        ),
      (WizardStep.retry, true, false) => (title: 'Try connecting again', description: ''),
      (WizardStep.account, true, false) => (title: 'Your eCard', description: ''),
      (WizardStep.welcome, true, true) => (
          title: '连接校园卡',
          description: '连接后，即可在 TechPie 中使用校园卡付款、查看交易记录。'
        ),
      (WizardStep.permission, true, true) => (title: '允许临时使用 VPN', description: ''),
      (WizardStep.code, true, true) => (title: '输入绑定码', description: ''),
      (WizardStep.success, true, true) => (title: '校园卡已连接', description: '现在可以在 TechPie 中使用校园卡了。'),
      (WizardStep.retry, true, true) => (title: '重新连接校园卡', description: ''),
      (WizardStep.account, true, true) => (title: '我的校园卡', description: ''),
      (WizardStep.welcome, false, false) => (
          title: 'Connect your eCard',
          description: 'Use your campus card for payments and recent activity in TechPie.'
        ),
      (WizardStep.permission, false, false) => (title: 'Allow a temporary VPN', description: ''),
      (WizardStep.code, false, false) => (title: 'Enter the binding code', description: ''),
      (WizardStep.success, false, false) => (
          title: 'Your eCard is ready',
          description: 'You can now use your campus card in TechPie.'
        ),
      (WizardStep.retry, false, false) => (title: 'Finish connecting', description: ''),
      (WizardStep.account, false, false) => (
          title: 'Connected eCard',
          description: 'Manage the campus card linked to TechPie.'
        ),
      (WizardStep.welcome, false, true) => (
          title: '连接校园卡',
          description: '在 TechPie 中使用校园卡付款、查看最近的交易记录。'
        ),
      (WizardStep.permission, false, true) => (title: '允许临时使用 VPN', description: ''),
      (WizardStep.code, false, true) => (title: '输入绑定码', description: ''),
      (WizardStep.success, false, true) => (title: '校园卡已就绪', description: '现在可以在 TechPie 中使用校园卡了。'),
      (WizardStep.retry, false, true) => (title: '完成校园卡连接', description: ''),
      (WizardStep.account, false, true) => (
          title: '已连接的校园卡',
          description: '管理已连接到 TechPie 的校园卡账号。'
        ),
    };
