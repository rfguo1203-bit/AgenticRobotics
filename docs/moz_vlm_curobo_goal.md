# MOZ + VLM + cuRobo 闭环任务可行性分析

**结论：这套任务链路可以实现，cuRobo 能承担其中的环境建图、碰撞检测、路径规划和轨迹生成，但它不能单独完成整个闭环。**

完整系统需要：

- **VLM**：理解任务、给出目标、判断阶段是否完成；
- **RealSense + cuRobo Mapper**：在线建立环境 TSDF／ESDF，不需要预先场景模型；
- **cuRobo MotionPlanner / MPC**：生成避障轨迹并处理环境变化；
- **任务状态机**：组织“观察—移动—接近—抓取—抬升—检查—重试”；
- **MOZ 真机接口**：提供关节状态、执行动作、控制夹爪并保障安全。

## 一、逐项判断

| 任务环节 | 能否实现 | cuRobo 的职责 | 需要额外实现 |
|---|---|---|---|
| 1. VLM 给出移动或抓取目标 | 可以 | 接收目标位姿，不理解语义 | 目标坐标转换、抓取姿态生成 |
| 2. RealSense 在线避障和轨迹生成 | 可以 | TSDF／ESDF 建图、IK、RRT、TrajOpt、MPC | 手眼标定、时间同步、自身点云剔除 |
| 3. 重复执行直到任务完成 | 可以 | 每次根据新状态重新规划 | 任务状态机、成功检测、失败恢复 |
| 4. 无场景模型，只有 MOZ 本体模型 | 可以，但有条件 | 从深度图在线构建碰撞环境 | 多视角扫描、遮挡处理和安全余量 |

官方已经提供了 **RealSense 实时 RGB-D → TSDF → ESDF → MPC 避障**的参考实现，因此第二条不是概念设想，而是有对应代码链路的。[实时建图与 MPC](https://nvlabs.github.io/curobo/latest/reference/live_volumetric_mapping_mpc.html)

## 二、推荐的完整系统架构

```text
                    ┌──────────────────────┐
                    │  用户任务 / VLM      │
                    │  移动到哪里？抓什么？ │
                    └──────────┬───────────┘
                               │
                     目标位置、抓取方向、动作类型
                               │
                               ▼
┌────────────────────────────────────────────────┐
│                任务状态机                       │
│ SCAN → MOVE → PRE_GRASP → GRASP → LIFT → CHECK │
└───────────────┬───────────────────────┬────────┘
                │                       │
                ▼                       ▼
┌───────────────────────┐   ┌────────────────────┐
│ RealSense 感知管线     │   │ cuRobo 运动规划    │
│ 深度过滤               │   │ IK                 │
│ 剔除机器人自身         │──▶│ RRT 全局路径       │
│ 相机位姿计算           │   │ TrajOpt 轨迹优化   │
│ TSDF / ESDF 更新       │   │ MPC / 动态重规划   │
└───────────────────────┘   └─────────┬──────────┘
                                      │
                                      ▼
                             MOZ 关节轨迹与夹爪命令
                                      │
                                      ▼
                            新图像、新关节状态、任务反馈
```

关键是：**VLM 不需要在每一个控制周期运行。**  
比较合理的频率分工是：

- VLM：低频，负责阶段决策和目标更新；
- MotionPlanner：目标变化或全局路径失效时运行；
- ESDF 与 MPC：较高频，负责局部避障；
- MOZ 底层控制器：更高频，跟踪关节轨迹并执行安全保护。

## 三、第 1 步：VLM 输出什么才够

### 普通移动

不能只输出：

```json
{"target": [0.42, -0.15, 0.31]}
```

cuRobo 的末端目标通常是完整位姿：

```text
位置：x, y, z
姿态：qw, qx, qy, qz
坐标系：MOZ base / world
工具坐标系：gripper_tcp
```

所以系统需要将 VLM 输出转换为：

\[
T_{\text{base,tool}}^{goal}
\]

如果 VLM 的坐标来自相机图像，则：

\[
p^{B}=T_{BC}\,p^{C}
\]

其中 \(T_{BC}\) 来自手眼标定。不能直接混用相机坐标和机器人基座坐标。

### 靠近抓取

杯子中心点并不直接等于夹爪目标点。还需要：

- 抓取位置相对物体表面的偏移；
- 夹爪接近方向；
- 夹爪开口方向；
- 预抓取距离；
- 抓取后抬升方向和距离。

比较稳妥的是让 VLM／抓取模块输出**多个候选抓取位姿**，由 cuRobo 从中选择可达且无碰撞的候选，而不是只给一个姿态。

cuRobo 原生支持 `plan_grasp`，将动作拆成：

```text
当前状态
   ↓
Pre-grasp：保持正常碰撞约束
   ↓
Grasp：沿直线接近，允许指定接触连杆接近目标
   ↓
Lift：直线抬升
```

[抓取规划文档](https://nvlabs.github.io/curobo/latest/getting-started/motion_planning.html)

## 四、第 2 步：无场景模型时如何避障

每一次感知更新的流程应该是：

```text
RealSense 深度图 + 对应时刻的 MOZ 关节角
                  ↓
          深度无效值和飞点过滤
                  ↓
          剔除 MOZ 自身和夹爪点云
                  ↓
   根据 FK + 手眼外参计算拍摄时相机位姿
                  ↓
           Mapper.integrate()
                  ↓
             更新 TSDF
                  ↓
          Mapper.compute_esdf()
                  ↓
      将 VoxelGrid 作为碰撞场景输入规划器
```

相机固定在 MOZ 本体上时，其世界位姿为：

\[
T_{WC}(t)=T_{WB}\,T_{BL}(q_t)\,T_{LC}
\]

- \(T_{WB}\)：MOZ 基座到世界；
- \(T_{BL}(q_t)\)：相机安装连杆的正运动学；
- \(T_{LC}\)：手眼外参。

**如果缺了精确手眼外参或图像—关节状态同步，地图会错位，后续再强的规划器也无法可靠避障。**

## 五、第 3 步：如何重复直到任务完成

建议把闭环实现为明确的状态机，而不是让 VLM 无约束地反复输出目标：

```python
while not task_done:
    joint_state = read_moz_joint_state()
    observation = read_realsense()

    observation = filter_depth(observation)
    observation = remove_moz_itself(observation, joint_state)
    observation.pose = compute_camera_pose(joint_state)

    mapper.integrate(observation)
    esdf = mapper.compute_esdf()

    if stage in {"MOVE", "PRE_GRASP"}:
        if need_global_replan():
            trajectory = plan_with_rrt_and_trajopt(goal, joint_state, esdf)
        else:
            action = update_mpc(goal, joint_state, esdf)

        execute_safely(action)

    elif stage == "GRASP":
        execute_linear_approach()
        close_gripper()
        attach_object_collision_model()

    elif stage == "LIFT":
        execute_lift()

    elif stage == "CHECK":
        stage_result = check_with_vlm_and_robot_state()

        if stage_result == "success":
            stage = next_stage()
        elif stage_result == "retry":
            stage = "PRE_GRASP"
        else:
            stop_and_replan()
```

任务完成最好由多种信号共同判断：

| 阶段 | 可用的成功判据 |
|---|---|
| 移动 | 末端位姿误差小于阈值、轨迹执行完成 |
| 抓取 | 夹爪开度、电流／力、物体是否随夹爪运动 |
| 抬升 | 目标物体高度变化、VLM 图像检查 |
| 放置 | 物体位置、夹爪释放、VLM 场景检查 |
| 整体任务 | VLM 判断 + 几何条件，而不是只靠语言描述 |

**cuRobo 的 `result.success` 只代表规划或约束验证成功，不代表物体已经成功抓住，也不代表整体任务完成。**

## 六、只有 MOZ 本体模型需要做什么

需要把 MOZ 的 URDF、Mesh 和关节信息转换成 cuRobo 配置，包括：

- 正确的运动学树；
- 活动关节名称、顺序和限位；
- `base_link`；
- 夹爪 TCP／`tool_frames`；
- 最大速度、加速度和 jerk；
- 连杆碰撞球；
- 自碰撞忽略矩阵；
- 夹爪接触连杆；
- RealSense 安装连杆及外参；
- 被抓物体的临时附着连杆。

碰撞球和自碰撞矩阵可以通过 `RobotBuilder` 从 URDF 生成，但生成后仍需要人工检查夹爪、相机支架和底座等关键部位。[机器人模型构建文档](https://nvlabs.github.io/curobo/latest/getting-started/build_robot_model.html)

## 七、这个方案最难的四个问题

### 1. 单视角遮挡

如果目标后方、机械臂后方或路径中间没有被相机看到，地图里就没有可靠障碍物。

**建议**：首次规划前增加 `SCAN` 阶段，从多个安全视角观察工作区；执行中继续更新，而不是只拍一帧就规划。

### 2. 目标物体既是障碍物，又必须接触

如果把杯子完整作为不可接近障碍，夹爪可能永远无法达到抓取位姿。

**建议**：

- 预抓取阶段正常避障；
- 最后接近阶段使用受控笛卡尔直线；
- 只放宽指定手指／接触连杆与目标的碰撞；
- 不要全局关闭碰撞检测；
- 抓取成功后把杯子附着到机器人碰撞模型。

### 3. 相机会被机械臂和目标遮挡

越接近杯子，相机视角可能越差。

**建议**：远距离用全局地图规划，近距离使用固定小范围直线接近，不要期望在最后几厘米仍依靠当前图像完整重建环境。

### 4. 全局规划与实时避障的职责不同

- **RRT + TrajOpt**：适合寻找完整绕行路径；
- **MPC**：适合局部跟踪和动态障碍反应；
- 只使用 MPC，复杂障碍下可能陷入局部极小值；
- 只执行一次开环轨迹，则无法应对新障碍物。

**推荐组合：先扫描 → RRT/TrajOpt 全局规划 → 执行中持续更新 ESDF → 必要时 MPC 调整或重新全局规划。**

## 最终评价

这套方案的可行性可以评为：

- **算法组件完整：可行；**
- **不需要场景预建模：可行；**
- **直接拼接 VLM 和 cuRobo 就能稳定完成：不可行；**
- **需要重点开发的工程部分：手眼标定、主动扫描、自身点云剔除、抓取状态机、目标接触处理和真机安全闭环。**
