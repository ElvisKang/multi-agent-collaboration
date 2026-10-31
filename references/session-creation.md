# 会话创建、模型与启动信息

仅在需要创建或接力会话时读取。先按 [环境与回退](environment.md) 采用用户及项目约定；以下为当前默认适配，方法和模型可随客户端变化采用等效实现。

默认所有正式会话的 App 项目/所属目录使用 Git 主工作区根；实际开发 worktree 单独记录并显式指定工具 workdir。worktree 在哪里由项目和任务决定，不能因会话在主目录就写主目录源码。

首次启动 prompt/task 采用 [消息协议](cli-routing.md#短消息协议)，先写 `[AgentMsg] task=... message_id=...` 和 `[AgentSender] agent=... session_id=...`，再写接收方启动说明及任务正文。发送方 ID 取自发起会话自身或已核实的创建结果，不能填接收方、父会话或操作 ID；接收方首次回复的 `[Session]` 是另一份身份声明。

## 创建入口

| Agent | 默认入口 | 说明 |
|---|---|---|
| Codex | Desktop 原生 create_thread；CLI 亦可回退 | 原生方式便于 App 分组；CLI 创建后看不到 App 时直接用 CLI，不阻塞工作 |
| MiMo | 自身接力可用原生 create_session；其他创建按项目配置或 CLI | 接力联络用 talk_to_session；需要在创建时选模型可用 CLI run |

先读取项目 AGENTS/HANDOFF 定义的创建方式、角色配置与已获授权。核心可在持续授权内自主创建和替换子管理者；子管理者可按复杂度创建开发者；每个角色均可自主创建自己的接力，无需逐次申请；手动会话也能中途申请加入。没有必要条件时由管理者自行实现可做的部分，不擅自换模型或新建冲突实例。

创建不做 App 可见性、双端往返或探测消息验收。只处理创建命令/工具的明确错误、取得真实 ID 并登记；没有取得 ID 就记未决，不猜最新会话，也不因缺 App 显示自动重建。正常工作回包可更新路由证据。

## 确定性脚本与模型

入口 [create-session.sh](../scripts/create-session.sh) 用 Bash 启动本地 Python 进行参数、配置及 JSON 处理，不调用 LLM 决定创建逻辑，也不使用 eval。这是可选的 Codex/MiMo 适配脚本，其他 Agent 按其实际原生能力或项目脚本执行。需要 Python 3.11+；项目可显式传入可执行文件位置。脚本不修改用户配置、任务 Owner 或生效 sessions。

模型采用顺序为用户/项目明确配置、客户端当前模型配置、最后才是默认适配提示：
- 项目在 HANDOFF 指定的模型由调用者传 --model；脚本只匹配对应配置项，未找到就省略模型/provider 覆盖参数。
- Codex 从 CODEX_HOME/config.toml（未设时用户 .codex/config.toml，或显式 --codex-config）读取当前 model 和 provider。当前曾采用 gpt-6.1-sol，配置更新后沿用有效新配置，不把这个名称固定为角色条件。
- MiMo 在目标主目录执行 `mimo debug config` 命令，读取其输出的合并配置，优先采用其 model；未设 model 时才在已配置模型中匹配当前默认提示 xiaomi-token-plan-cn/mimo-v2.6-pro。将来模型或查询方式变更时按真实配置/帮助调整适配。
- 配置不可读取、无法解析或目标模型不存在时，输出 model=null 与原因，使用客户端默认，不静默改成另一款明确指定模型，也不改写用户配置。
- 工具提供什么参数就传什么；Codex 原生工具无 provider 参数时沿用 App 配置，不伪造字段。方法已失效则按当前环境选择等效入口，未知创建结果先查原操作，不直接换入口再建一次。

示例先检查生成参数，不创建会话：
```bash
bash <skill目录>/scripts/create-session.sh --agent mimo \
  --cwd <主工作区或其worktree> --coordination-dir <主工作区项目/.local/coordination> \
  --request-id task-manager-1 --project <项目名> --task <任务ID> \
  --sender-agent <发送方Agent> --sender-session-id <发送方真实ID> \
  --role task_manager --name <需求简称> --prompt-file <任务书> --dry-run
```

脚本是确定性 CLI 回退入口；原生工具可用时优先由所在 Agent 调用原生创建工具。去掉 --dry-run 后，MiMo CLI 回退和 --transport cli 的 Codex 执行一次创建。结果未知不自动重试；相同 request-id 的已有操作只回报当前状态，不再次启动。新一轮真正重建应先由管理者确认旧执行不存在或停止，再使用新的 request-id。

`--prompt-file` 只放任务正文，脚本统一添加消息头、发送方签名与接收方启动说明；文件不要再包一层消息头。`--sender-agent`、`--sender-session-id` 为必填，不从目标Agent或继承环境猜测发送方；`--message-id` 可显式指定，省略时使用 `create-<request-id>`，重试沿用。dry-run同时展示消息ID和发送方信息，不创建会话或发送消息。

Codex --transport desktop 只生成 create_thread 的参数，管理者调用真实工具；脚本不声称已创建。此路径需要 --project-id，由 list_projects 中主工作区项目取得。工具结果使用真实 threadId；只有 clientThreadId 时仍是创建中。

## 默认 Codex 原生路径（以当前工具定义为准）

create_thread 使用 target.type=project、主目录 projectId、environment.type=local，设置 title、启动 prompt，以及配置可匹配时的 model。不使用 worktree 环境创建此类会话，避免 App 项目分散；开发 checkout 的创建和绑定归任务规则管理。

普通 codex exec 支持 -C、--json、--model 和标准输入。CLI 回退不传 --ephemeral，确保会话持久化；不伪造 source/originator 来冒充 Desktop 会话。codex app <主目录> 只代表打开 App 工作区，不用于冒充取得新会话 ID。

当前 CLI 未提供本指导已确认的 exec 标题参数；CLI 回退打印规范 suggested_title，若有 App 标题工具可按实际 ID 更新，否则接受客户端标题，不让标题问题阻塞任务。原生 create_thread 支持 title。

## MiMo 自主接力的原生适配

当 MiMo 当前角色决定更换自己的会话时，可用 create_session 创建继任独立对话，再通过 talk_to_session 联络、交付当前任务。该用法主要服务自身接力，不要求所有管理者给 MiMo 派发工作都改走它，也不把其他 Agent 绑定到 MiMo 的工具。

准确参数映射、模型边界和投递语义见 [MiMo 接力适配](mimo-relay.md)，仅执行这类接力/联络时读取。创建出的正式会话可以继续参与协作，但上级日常派发仍选择当前可用原生工具或已登记 CLI 路由。

## 默认 MiMo CLI 回退

run 时从主目录执行并设置 --dir、--title、--format json；配置匹配时加 --model。新建不带 -s、--continue 或 --fork；接续按已登记真实 ID 使用 run -s。项目如要求 --attach，显式传入经确认地址，不自动新开第二个实例。

## 标题规范

- 核心管理：[项目名] 核心管理
- 子管理：[任务ID] 需求简称 / 管理
- 开发者：[任务ID] 需求简称 / 开发-序号
- 监督者：[项目名] 监督

同任务多个开发者用序号区分；接力保留逻辑标题，确有区分需要时追加接力序号。不把 UUID、完整时间戳、历史状态塞进标题。标题用于人找会话，路由仍用真实 ID。

## 首次启动输出

每个会话先输出一行基础信息，再开展任务：
```text
[Session] agent=... role=... task=... sessionId=真实ID project=主工作区 worktree=开发目录或未分配
```

ID 从本会话运行环境、工具创建结果或客户端元数据取得；Codex 自查 CODEX_THREAD_ID，MiMo 用真实 ses_...。不能读取则输出 UNRESOLVED，禁止把父会话 ID、操作 ID 或候选 clientThreadId 当自己身份。脚本在 CLI 创建事件给出 ID 后也打印同样信息，原生创建者取得 threadId 后向用户展示。

### fork 后的身份核对

fork 会继承来源会话的历史，其中旧 Session 输出、环境命令结果、任命或退任消息不代表新会话的当前身份与收件记录。首次启动时单独执行身份读取（Codex 为 `printenv CODEX_THREAD_ID`），采用本次调用的原始结果，核对创建工具返回的新 ID 和当前磁盘席位；发消息的 session_id、Session 输出及最终回复都使用这个已核对的新 ID。

怀疑新旧身份冲突时，按目标 threadId 和本次 turn/调用定位原始输出，并分别核对当前 `session_id` 与 `previous_session_id`，不要根据继承历史、先前自述或消息正文宣判冲突。若本次环境输出、创建结果和当前席位一致，仅自述仍为旧 ID，修正自述与交接，不重新 fork、不回退路由，也不把旧会话的退任通知当作新会话收到的指令。

实际证据仍不一致或无法取得时，按既有 UNRESOLVED 规则暂停冲突写入并交创建者核查；一次 fork 中的历史身份误用不能据此归因为客户端 fork 缺陷。正常创建不额外增加探测消息或双向验收。

启动消息统一引用本技能、对应角色指导、项目 AGENTS 和任务/当前交接；不复制全部历史或共通规章。创建完成不等于接管写入；权限、未决操作和 Owner 按接力规则转移。不要同时用 Desktop 和 CLI 争占同一交互 writer。
