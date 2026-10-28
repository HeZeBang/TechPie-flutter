# TechPie 反馈入口

本目录只包含反馈表单与工单查询界面。API、存储、后台管理、测试和部署配置独立放在 E:\Projects\techpie-feedback-api。

接口地址：https://techpie-feedback.dzhes.app/api/feedback。API 项目部署时同步这里的公开界面到 public/，因此该域名也提供反馈入口，后台地址为 /miku。

表单包含 GeekPie-UniAuth 用户名（非学号）、反馈类型、平台与版本、使用场景、标题、具体问题、复现步骤、期望结果与联系方式。用户名自行填写，未做 SSO 身份验证，不传递 SSO Token。提交后生成工单 ID，可下载凭证并查看公开回复与处理进度。

Flutter 设置页通过“用户反馈与工单”打开入口。API 的账户密码、存储凭据及运行数据均不在本目录。