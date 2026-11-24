# AgenticRobotics

基于 VLM 的机器人任务执行仿真项目。第一阶段以 PEAR 为基线，在 H100服务器上完成模型服务、仿真环境和机器人动作执行的闭环 Demo；当前阶段不连接或控制真实机器人。

## 仓库结构

```text
AgenticRobotics/
├── AGENTS.md                    # 项目约定与协作边界
├── docs/                        # 方案与调研文档
└── src/
    ├── pear/                    # PEAR 子模块
    └── curobo/                  # cuRobo 子模块（后续可选能力）
```

`src/pear` 和 `src/curobo` 是 Git 子模块，分别指向以下 fork：

- `git@github.com:rfguo1203-bit/pear.git`，上游为 `mit-han-lab/pear`
- `git@github.com:rfguo1203-bit/curobo.git`，上游为 `NVlabs/curobo`

## 克隆仓库

完整克隆根仓库及子模块：

```bash
git clone --recurse-submodules git@github.com:rfguo1203-bit/AgenticRobotics.git
```

如果已经克隆根仓库，但子模块目录为空：

```bash
cd AgenticRobotics
git submodule update --init --recursive
```

子模块使用 SSH 地址，执行上述命令前需要为开发机或 H100服务器配置可用的 GitHub SSH 密钥。

## 开发机开发与子模块提交

根仓库中的文档、配置和应用层代码按普通 Git 流程提交。修改 `src/pear` 或 `src/curobo` 时，需要先提交并推送子模块，再更新根仓库记录的子模块版本。

以 PEAR 为例：

```bash
cd src/pear
git add <修改文件>
git commit -m "修改说明"
git push origin main

cd ../..
git add src/pear
git commit -m "Update PEAR submodule"
git push
```

修改 cuRobo 时，将路径替换为 `src/curobo`。如果两个子模块都有修改，应分别完成子模块提交和推送，再在根仓库中一起或分别更新对应的子模块指针。

不要只在根仓库执行 `git add src/pear`：未在子模块中提交的改动不会进入根仓库，也不会同步到 H100。

## H100服务器同步

H100服务器只拉取开发机已经推送的提交，不直接修改源码。推荐使用同步脚本：

```bash
cd <AgenticRobotics目录>
./scripts/sync_h100.sh
```

脚本会检查根仓库及所有已初始化子模块，发现未提交修改时停止；根仓库使用 fast-forward 拉取，随后同步子模块地址并更新到根仓库记录的版本。可用以下参数预览或查看帮助：

```bash
./scripts/sync_h100.sh --dry-run
./scripts/sync_h100.sh --help
```

等价的手工命令为：

```bash
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive
```

单独执行 `git pull` 只会更新根仓库及其子模块指针；还需要 `git submodule update`，子模块工作目录才会切换到对应版本。脚本结束时会输出根仓库和所有子模块的实际版本。

## 同步上游更新

子模块的 `origin` 用于推送个人修改，`upstream` 用于获取官方更新。例如同步 PEAR 上游：

```bash
cd src/pear
git fetch upstream
git merge upstream/main
git push origin main

cd ../..
git add src/pear
git commit -m "Update PEAR from upstream"
git push
```

合并后应按项目验证策略在 H100服务器上分层验证，再更新 Demo 所使用的子模块版本。

## 运行边界

- 开发机只进行代码阅读、修改、静态检查和文档维护，不启动模型服务、仿真器、训练或项目集成测试。
- H100服务器负责环境安装、模型与仿真服务、测试和 Demo 执行，并保存日志和可视化产物。
- 所有机器相关地址、端口、模型路径和环境路径均通过配置或环境变量提供，不提交到仓库。
- 不提交模型权重、数据集、仿真缓存、日志、视频或密钥。
- 未完成 H100服务器验证的功能应标记为“代码已完成，待 H100服务器验证”。
