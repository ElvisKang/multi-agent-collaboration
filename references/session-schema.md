# 当前会话快照（schema 2.0，分层字段为兼容扩展）

位置由项目规范决定。文件可沿用 sessions.md 名称，内容为纯 YAML，不加 Markdown 围栏或历史章节；模板见 [sessions](../assets/sessions-template.md)。

agent 是实际 Agent 产品/执行环境标识，不限制为 Codex/MiMo，也不由 role 推导；模板中的 Agent 与程序由用户/项目配置后填写。个性化偏好读取项目 HANDOFF，模型和显示标题继续不作写入授权依据。

## 当前映射

- 顶层保留 schema_version="2.0"、project、main_worktree、project_relative_path、tasks_file、executables、sessions。tasks_file 相对快照文件目录；executables 按 agent 保存默认程序。
- core_manager 为可选的核心逻辑席位指针；启用分层协作后须指向 sessions 中唯一当前 core_manager。候选接力会话在切换前不成为第二个有效核心。
- sessions 是逻辑席位到当前会话记录的映射。逻辑席位稳定，session_id 可以更换；不以标题作为路由真源。
- 原必需字段保留：agent、session_id、task_id、role、status、development_worktree、cli_cwd、extra_args、required_env_names、route_status、confirmed_at。未知值为 null，无参数用 []。
- 新记录的 role 用 core_manager、task_manager、developer、supervisor。旧 coordinator/writer/planner/reviewer 记录仍可读，需核对职责后再映射，不自动把 coordinator 当核心。
- reports_to 为可选的直接管理席位：子管理者指向核心，开发者指向子管理者。核心和监督者为 null；核心下可有多个子管理者，同任务可有多个开发者。
- 核心/监督 task_id 可为 null，需求管理与开发者绑定具体任务/子任务；任务树关系和实际写入 Owner 只在 TASKS 维护。
- 继续支持可选 inspection_worktree、executable、previous_session_id、route_verified_at。无需记录完整历史或传递多个 previous ID。
- 可执行文件为 record.executable 或 executables[agent]。extra_args 为独立参数数组，required_env_names 只存变量名，不存密钥。客户端种类、创建模型和显示标题不作为授权真源。

会话所属项目固定 Git 主工作区；实际开发目录单独记录。cli_cwd 必须反映实例实际归属，不为表面统一而伪造路径。confirmed_at 是身份/绑定核对时间，不随普通消息刷新。

## 状态和投递

| 字段 | 值 | 含义 |
|---|---|---|
| status | ACTIVE | 身份/绑定明确，按授权可投递；不表示实时在线或空闲 |
| status | UNRESOLVED | 必要身份或绑定不明确，先核对再投；不等于会话结束 |
| status | ENDED | 不投递、不自动恢复 |
| route_status | UNVERIFIED | 尚无当前路由接收证据；ACTIVE 且参数完整时可正常首次投递 |
| route_status | VERIFIED | 当前 ID/路由已有接收证据，不保证每次成功或双向链路 |
| route_status | BLOCKED | 已知路由阻塞，解除后再投 |

不为创建会话专门发送验证消息，也不检查 App 可见性作为开工门禁；CLI 可用即可继续。真实工作产生接收证据时再更新 VERIFIED，queue 接受不能直接升级。ID、agent、cli_cwd、程序或连接参数变化时重置路由证据，不能沿用前任的验证。

## 修改与接力

只在身份、绑定、路由或核实状态改变时原位更新。普通派发、送审、ACK 不加 last_request/result/notice 等字段。未决操作属于任务交接，防重投递记录属于本地操作台账。

按 [任务与接力](coordination.md) 完成转移后替换席位 session_id 并保留直接 previous_session_id。前任 ID 用于定位和识别迟到消息，不作为当前投递目标或自动转发别名。

更新层级需核对管理席位存在且无循环；创建新角色记录不等于获得写入权。只有真实身份未知或必要路由缺失才设 UNRESOLVED，App 未显示本身不影响 ACTIVE。

## 消费者与生效

直接 safe_load 全文件，遍历 sessions.items()；未使用层级的现有消费者可忽略可选 core_manager/reports_to。严格字段/role 校验的消费者需先适配后迁移，不暗中更换其解释。

预览不修改现有路由、角色或用户配置；批准后按当前任务职责逐条迁移，禁止根据旧快照覆盖并发变化。不维护第二份生效登记。
