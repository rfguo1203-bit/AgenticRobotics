# H100服务器Handoff

> 文件名：`h100_handoff_<base短commit>_<YYYYMMDD_HHMMSS>.md`
>
> 一个文件包含全部元数据、验证证据和完整 unified diff。不要附加第二个补丁文件。

## Base

- repository: AgenticRobotics
- branch: `<branch>`
- base_commit: `<full commit>`
- generated_at: `<ISO 8601 time>`
- status: `H100_PATCHED`

## Purpose

`<本次修改只解决的一个问题>`

## Scope

- source_files_changed: `<count>`
- source_lines_added: `<count>`
- source_lines_deleted: `<count>`
- scripts_h100_files_changed: `<count>`
- within_budget: `<yes/no；no 时说明原因>`

## Changed Files

- `<path 1>`
- `<path 2>`

## Root Cause and Evidence

`<已确认的根因、日志证据和定位过程；不要只写猜测>`

## Validation

### Command

```bash
<在 H100服务器实际执行的命令>
```

- exit_code: `<code>`
- result: `<实际结果>`
- verification_scope: `<smoke / unit / component / integration / repeated>`
- log_path: `<path>`
- artifact_path: `<path>`

## Remaining Issues

`<尚未验证或仍失败的内容；没有则写 none>`

## Sync Instructions

- 开发机必须基于上述 base commit 检查并**原样应用**下方 Patch。
- 镜像时不做风格优化、不夹带其他修改。
- 开发机推送后，H100服务器只有在用户明确允许时才撤销临时修改并 `git pull`。
- 正式版本重跑相同验证后才可标记 `VERIFIED`。

## Patch

```diff
<完整 unified diff；包含所有新增文件的 new-file diff 和完整内容>
```
