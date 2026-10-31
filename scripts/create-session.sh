#!/usr/bin/env bash
set -euo pipefail
exec python3 - "$0" "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

script_path = Path(sys.argv[1]).resolve()
parser = argparse.ArgumentParser()
parser.add_argument("--agent", choices=["codex", "mimo"], required=True)
parser.add_argument("--transport", choices=["desktop", "cli"])
parser.add_argument("--cwd", required=True)
parser.add_argument("--coordination-dir", required=True)
parser.add_argument("--request-id", required=True)
parser.add_argument("--message-id")
parser.add_argument("--sender-agent", required=True)
parser.add_argument("--sender-session-id", required=True)
parser.add_argument("--project")
parser.add_argument("--project-id")
parser.add_argument("--task")
parser.add_argument("--role", choices=["core_manager", "task_manager", "developer", "supervisor"], required=True)
parser.add_argument("--name", default="")
parser.add_argument("--number", type=int, default=1)
parser.add_argument("--worktree")
parser.add_argument("--prompt-file", required=True)
parser.add_argument("--executable")
parser.add_argument("--model")
parser.add_argument("--codex-config")
parser.add_argument("--attach")
parser.add_argument("--dry-run", action="store_true")
args = parser.parse_args(sys.argv[2:])
if args.role in ["task_manager", "developer"] and not args.task:
    parser.error("需求管理者和开发者必须提供 --task")
if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.request_id) or args.request_id in [".", ".."]:
    parser.error("--request-id 必须是安全的单个目录名")
message_id = args.message_id or "create-" + args.request_id
if not re.fullmatch(r"[A-Za-z0-9_.-]+", message_id):
    parser.error("--message-id 只能包含字母、数字、下划线、点和连字符")
for name, value in (("sender-agent", args.sender_agent), ("sender-session-id", args.sender_session_id),
                    ("task", args.task or "none")):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", value) or value == "UNRESOLVED":
        parser.error("--" + name + " 必须是已确认的单个标识，不能包含空白或使用 UNRESOLVED")
if args.number < 1:
    parser.error("--number 必须为正整数")
transport = args.transport or ("desktop" if args.agent == "codex" else "cli")
if args.agent == "mimo" and transport != "cli":
    parser.error("MiMo 使用 --transport cli")
if args.attach and args.agent != "mimo":
    parser.error("--attach 仅用于项目已确认的 MiMo 实例")
root_result = subprocess.run(["git", "-C", args.cwd, "worktree", "list", "--porcelain"], capture_output=True, text=True)
if root_result.returncode:
    parser.error("无法确定 Git 主工作区")
root_match = re.search(r"^worktree (.+)$", root_result.stdout, re.M)
if not root_match:
    parser.error("Git 未返回主工作区")
main_worktree = str(Path(root_match.group(1)).resolve())
coordination_dir = Path(args.coordination_dir).resolve()
if not coordination_dir.is_relative_to(Path(main_worktree)):
    parser.error("协作目录须位于 Git 主工作区内")
prompt = Path(args.prompt_file).read_text()
if prompt.lstrip().startswith("[AgentMsg]"):
    parser.error("--prompt-file 只放任务正文，消息头由脚本统一生成")
project = args.project or Path(main_worktree).name
role_names = {"core_manager": "核心管理", "task_manager": "管理", "developer": "开发-" + str(args.number), "supervisor": "监督"}
if args.role in ["core_manager", "supervisor"]:
    title = "[" + project + "] " + role_names[args.role]
else:
    title = "[" + args.task + "] " + (args.name.strip() + " / " if args.name.strip() else "") + role_names[args.role]
executable = args.executable or shutil.which(args.agent)
if not executable and args.agent == "codex":
    bundled = Path("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    if bundled.is_file():
        executable = str(bundled)
if not executable and args.agent == "mimo":
    bundled = Path.home() / ".mimocode/bin/mimo"
    if bundled.is_file():
        executable = str(bundled)
default_hint = {"codex": "gpt-6.1-sol", "mimo": "xiaomi-token-plan-cn/mimo-v2.6-pro"}[args.agent]
requested_model = args.model
model = None
provider = None
model_note = "未找到对应模型，省略模型覆盖参数"
try:
    if args.agent == "codex":
        config_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
        config_path = Path(args.codex_config) if args.codex_config else config_home / "config.toml"
        config = tomllib.loads(config_path.read_text())
        candidate = config.get("model")
        target_model = requested_model or (candidate if isinstance(candidate, str) else default_hint)
        if isinstance(candidate, str) and candidate.casefold() == target_model.casefold():
            model = candidate
            provider = config.get("model_provider")
    elif executable:
        resolved = subprocess.run([executable, "debug", "config"], cwd=main_worktree, capture_output=True, text=True, timeout=20)
        if resolved.returncode == 0:
            config = json.loads(resolved.stdout)
            if not isinstance(config, dict):
                raise ValueError("配置不是对象")
            candidates = []
            for provider_name, entry in config.get("provider", {}).items():
                if provider_name not in config.get("disabled_providers", []):
                    candidates.extend(provider_name + "/" + name for name in entry.get("models", {}))
            if isinstance(config.get("model"), str):
                candidates.append(config["model"])
            configured_model = config.get("model")
            target_model = requested_model or (configured_model if isinstance(configured_model, str) else default_hint)
            for candidate in candidates:
                if candidate.casefold() == target_model.casefold():
                    model = candidate
                    provider = candidate.split("/", 1)[0]
                    break
    if model:
        model_note = "模型从当前配置匹配"
except (OSError, ValueError, TypeError, AttributeError, subprocess.TimeoutExpired):
    model = None
    provider = None
    model_note = "配置不可用或无法解析，省略模型覆盖参数"
startup = (
    "[AgentMsg] task=" + (args.task or "none") + " message_id=" + message_id + "\n" +
    "[AgentSender] agent=" + args.sender_agent + " session_id=" + args.sender_session_id + "\n\n" +
    "先读取协作技能 " + str(script_path.parent.parent / "SKILL.md") +
    " 及自己的角色页，按项目 AGENTS/HANDOFF 的指针读取当前任务所需资料；其他参考发生对应操作再读。首次回复输出一行 [Session] 基础信息："
    "agent=" + args.agent + " role=" + args.role + " task=" + (args.task or "none") +
    " sessionId=从自身运行环境或客户端取得的真实ID project=" + main_worktree +
    " worktree=" + (args.worktree or "未分配") +
    "。ID 无法确认则输出 UNRESOLVED，不使用父会话或操作ID代填。"
    "遵循已确认权限；接力未完成前不争抢写入。\n\n" + prompt
)
summary = dict(agent=args.agent, role=args.role, task=args.task, project=main_worktree,
               worktree=args.worktree, suggested_title=title, model=model, provider=provider,
               model_note=model_note, request_id=args.request_id)
summary.update(message_id=message_id, sender_agent=args.sender_agent, sender_session_id=args.sender_session_id)
def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)
if args.agent == "codex" and transport == "desktop":
    if not args.project_id:
        parser.error("Desktop 参数需要 list_projects 返回的 --project-id")
    parameters = dict(title=title, target=dict(type="project", projectId=args.project_id, environment=dict(type="local")), prompt=startup)
    if model:
        parameters["model"] = model
    emit(dict(summary, action="create_thread_parameters", parameters=parameters, created=False))
    sys.exit(0)
if not executable:
    parser.error("未找到客户端程序，请指定 --executable")
if args.agent == "codex":
    command = [executable, "exec", "-C", main_worktree, "--json"]
    if model:
        command += ["--model", model]
        if isinstance(provider, str) and provider:
            command += ["-c", "model_provider=" + json.dumps(provider)]
    command += ["-"]
else:
    command = [executable, "run", "--dir", main_worktree, "--title", title, "--format", "json"]
    if args.attach:
        command += ["--attach", args.attach]
    if model:
        command += ["--model", model]
    command += ["--", startup]
if args.dry_run:
    emit(dict(summary, action="cli_plan", argv=command, created=False))
    sys.exit(0)
operation_dir = coordination_dir / "creations" / args.request_id
try:
    operation_dir.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    result_path = operation_dir / "result.json"
    try:
        existing = json.loads(result_path.read_text())
    except (OSError, ValueError):
        existing = dict(status="UNKNOWN", session_id=None)
    emit(dict(summary, action="existing_operation", existing=existing, created=False))
    sys.exit(0)
result_path = operation_dir / "result.json"
state = dict(summary, status="INTENT", session_id=None, title_applied=args.agent == "mimo")
def persist():
    temporary = operation_dir / "result.next"
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(result_path)
persist()
process = None
try:
    with (operation_dir / "events.jsonl").open("w") as events, (operation_dir / "stderr.log").open("w") as errors:
        process = subprocess.Popen(command, cwd=main_worktree, stdin=subprocess.PIPE if args.agent == "codex" else subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=errors, text=True, errors="replace")
        state.update(status="RUNNING", pid=process.pid)
        persist()
        if args.agent == "codex":
            process.stdin.write(startup)
            process.stdin.close()
        client_error = False
        for line in process.stdout:
            events.write(line)
            events.flush()
            try:
                event = json.loads(line)
            except ValueError:
                continue
            candidate = None
            if args.agent == "codex" and event.get("type") == "thread.started":
                candidate = event.get("thread_id")
            if args.agent == "mimo":
                candidate = event.get("sessionID")
                if not candidate and event.get("type") == "session.created":
                    candidate = event.get("properties", {}).get("info", {}).get("id")
            if event.get("type") in ["error", "turn.failed"]:
                client_error = True
            pattern = r"[0-9a-fA-F-]{36}" if args.agent == "codex" else r"ses_[A-Za-z0-9]+"
            if isinstance(candidate, str) and re.fullmatch(pattern, candidate):
                if state["session_id"] and state["session_id"] != candidate:
                    client_error = True
                elif not state["session_id"]:
                    state["session_id"] = candidate
                    persist()
                    emit(dict(summary, action="session_started", session_id=candidate))
        exit_code = process.wait()
        state.update(exit_code=exit_code, status="CREATED" if exit_code == 0 and state["session_id"] and not client_error else "NEEDS_ATTENTION")
        persist()
        emit(dict(state, action="creation_result", operation_dir=str(operation_dir)))
        sys.exit(0 if state["status"] == "CREATED" else 1)
except (OSError, KeyboardInterrupt):
    state.update(status="UNKNOWN", pid=process.pid if process else None)
    persist()
    emit(dict(state, action="creation_unknown", operation_dir=str(operation_dir)))
    sys.exit(1)
PY
