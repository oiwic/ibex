# AGENTS.md — tide_cd（CD 经典域 RTL 实现仓）协作约定

> 本文件是 AI agent 与协作者修改本仓（CD RTL 实现仓）时必须遵循的约定。
> 本仓是 **TIDE-MCU 五仓结构中的 CD 实现仓**（兄弟仓：`../tide_isa`、`../tide_doc`、`../tide_dd`，工程管理仓 `../tide_prj` 见其 `AGENTS.md`）。ISA **不在本仓定义**，本仓只负责把 CD 侧微架构落地成 RTL 并通过验证。

## 0 动手之前：必读清单（按顺序）

| 顺序 | 文件 | 作用 |
|---:|---|---|
| 1 | 本文件 `AGENTS.md` | 操作约定、硬约束、提交自检 |
| 2 | [`docs/README.md`](./docs/README.md) | 工程地图 + 决策台账 D1–D15 |
| 3 | [`docs/FOCUS.md`](./docs/FOCUS.md) | 14 条陷阱（带 `文件:行号` 证据） |
| 4 | [`docs/ENGINEERING.md`](./docs/ENGINEERING.md) | 9 条硬纪律 + 验证分层 + 自检清单 |
| 5 | `../tide_doc/chapters/09-interface-freeze.md` | **接口冻结**：参数 / 类型 / 跨域信号 / Ibex 内部落点 |
| 6 | `../tide_isa/TIDE-ISA规范.md` | **ISA 权威来源**（v0.10-rc） |

## 1 仓关系与权威顺序

本仓与 4 个兄弟仓平铺在同一父目录下（全量五仓关系与边界见工程管理仓 `../tide_prj/AGENTS.md` §1；下表只列与本仓直接相关的仓，路径相对本仓）：

| 仓 | 路径 | 内容 | 与本仓的边界 |
|---|---|---|---|
| `tide_isa` | `../tide_isa` | **ISA 规范**（TIDE-ISA v0.10-rc）+ 表达力检验 + 评审报告 | 纯文档仓；指令语义/CSR/`TQ_*` 一律以它为准，本仓不定义 |
| `tide_doc` | `../tide_doc` | **微架构设计文档**（docs-as-code）+ 冻结接口数据 `data/tide_*.csv` | 文档仓；模块划分/接口信号/参数冻结表以它为准，本仓只落地 |
| `tide_dd` | `../tide_dd` | **DD 实现**：定时队列 / 读出队列 / 同步 / fail-stop / MMIO（Phase 2） | 实现仓；本仓的 DD stub（`dv/uvm/core_ibex/tide/tide_dd_stub.sv`）只替它模拟接口，**不**在本仓实现 DD 内部逻辑 |
| `tide_cd` | **本仓** | **CD 实现**：Ibex RTL + TIDE CD 逻辑 + 验证 + 构建（FuseSoC）（Phase 1 主仓） | ✅ 主工作区 |

**权威顺序**：以 `../tide_prj/AGENTS.md` §2 为准，本仓不再重述。

**上游关系**（2026-10-15 实测核对，证据见下）：

| 项 | 值 |
|---|---|
| 官方上游 | `https://github.com/lowrisc/ibex` —— 已加为 remote **`upstream`** |
| 本仓 `origin` | `https://github.com/oiwic/ibex.git` —— **只读来源，无推送权限** |
| 两者关系 | **同一条线性历史，无分叉**。`oiwic/ibex` 的 master（`af456e25`）是官方 master 的**祖先** |
| 当前 HEAD | `96a34a56 [doc] Fix the icache data ECC layout`（= `upstream/master`） |
| **CHERIoT 的归属** | ⚠️ **上游自带，不是 fork 特性**。`f1cea015 2026-08-17 [rtl] Implement CHERIoT ISA`（Samuel Riedel）在官方历史里 |

同步命令（`git fetch upstream master --no-tags` 后 `git merge --ff-only upstream/master`）；核对关系用
`git merge-base --is-ancestor HEAD upstream/master` + `git rev-list --left-right --count HEAD...upstream/master`。

**硬规则**（跨仓总纲以 `../tide_prj/AGENTS.md` §6/§8 为准，本仓不再重述）：

1. **实现层改动须对照微架构**：本仓任何实质改动（`../tide_prj/AGENTS.md` §7.2 判定）必须先核对 `../tide_doc/chapters/*.md` 与 `data/*.csv` 仍在约束内；需要契约外行为时停手，回 `../tide_doc` 提微架构变更。上层（ISA/微架构）实质改动落到本仓时，执行 `../tide_prj/AGENTS.md` §7.3 穿透审阅并在提交信息中互相引用。
2. **通用工程纪律**（证据优先、决策留痕、不抄上游规格、行号漂移）以 `../tide_prj/AGENTS.md` §7.4 为准，本仓不再重复。

## 2 项目一句话

在 **Ibex**（lowRISC 官方 RISC-V 核；remote `origin` = `oiwic/ibex`，与官方 `lowrisc/ibex` 同一条线性历史，当前 HEAD `96a34a56`）上实现 **TIDE-ISA**：面向超导量子计算的**双时序域**扩展，把经典处理器定位为**非确定事件生产者**（CD），把定时队列 + 出队逻辑 + 采集后端定位为**确定时间事件执行器**（DD）。

| 项 | 取值 | 依据 |
|---|---|---|
| 基线命名配置 | Ibex `small`（RV32IMC，2 级流水，3 拍乘法器） | `../tide_doc/chapters/02-overview.md` §3 |
| 基线 ISA | `BaseIsaRV32I`（**不是** `BaseIsaRV32IorCHERIoT`） | ADR C4；`ibex_configs.yaml:20` |
| 流水线 | `WritebackStage=0`、`BranchTargetALU=0`、`BranchPredictor=0` | 不变量 I3 |
| 关闭项 | `PMPEnable=0`、`SecureIbex=0`、`ICache=0`、`RV32B=RV32BNone` | 不变量 I2 |
| 新增指令 | **4 条**：`QWAIT` / `QTRIG` / `QLOAD` / `QSYNC` | ISA §4 |
| 新增 CSR | RW `0x7C0–0x7C6`，RO `0xFC0–0xFCB` | ISA §5 |
| 新增 mcause | `24–32`（`TQ_*` 家族） | ISA §6.6 |

**双域铁律**（ISA §1.1，规范性）：CD 与 DD 之间**只允许存在三条通道**——事件通道（CD→DD）、结果通道（DD→CD）、异常通道（DD→CD）。除此之外**禁止**任何体系结构可见的耦合。

## 3 硬约束（违反即返工）

### C1 D9 已被 D14 取代：允许新增/修改 `rtl/ibex_*.sv`

- **旧约束（已失效）**：`docs/README.md` **D9**「不修改任一 `rtl/ibex_*.sv`，只新增系统顶层与外设」。
- **新约束（D14）**：为承载 TIDE-ISA 的 4 条新指令，**允许**新增与修改 `rtl/ibex_*.sv`。
- **附加条款（不可协商，违反即返工）**：
  1. **既有指令不得改动**：RV32IMC、CHERIoT（`OPCODE_CHERI=0x5b`、`OPCODE_AUICGP=0x7b`）、Zca/Zcb/Zcmp 的**译码结果、异常语义、时序**必须逐拍保持。
  2. **`TIDE_EN` 门控**：所有 TIDE 新增逻辑必须被 `TIDE_EN` 参数门控。`TIDE_EN = 0` 时，综合结果与仿真行为必须**逐拍回归上游 Ibex**（不变量 **I1**）。
  3. **不新增顶层端口**：TIDE 阻塞复用既有 `stall_id_i` / `flush_id_o` 机制（ADR C6）。
- **理由**：ISA 指令只能由译码器 + 执行单元承载，不存在"加外设"的替代路径。

### C2 只加不改：新指令走"新操作码 + 新译码分支"

- TIDE 指令使用 **custom-0（`0b0001011`）/ custom-1（`0b0101011`）** 主操作码，与既有操作码**零重叠**。
- **禁止**复用 `OPCODE_OP` 的 funct3/funct7 空洞承载 TIDE 指令——那会改动既有译码矩阵。
- 保留字段非 0 必须报 `illegal instruction`（ISA §3.3），便于未来扩展检测。

### C3 不可推测副作用

TIDE 指令的副作用必须在指令**不可撤销之后**发生（ISA §3.3 / 不变量 I7）。本核**顺序发射、无推测**，但要确认：译码级不得提前改变体系结构状态。

### C4 文件清单纪律（`docs/ENGINEERING.md` E1）

- 仓库**没有**"扫描目录自动收集文件"机制，文件清单**手写**。
- **唯一权威**：FuseSoC `.core` 文件（根目录 `*.core`、`examples/**/*.core`、`shared/*.core`、`dv/**/*.core`）。
- ⚠️ `src_files.yml` **已过期，不要拿它对账**（含 3 个死条目，且遗漏多个真实文件）。
- **新增 / 删除 / 重命名任一 `.sv`，必须同步更新所有相关 `.core`。**

### C5 参数开关与配置矩阵纪律（`docs/ENGINEERING.md` E2 / `docs/README.md` D10 / **`docs/FOCUS.md` F14**）

> ⚠️ **本条原始表述**是"把 `TIDE_EN` 放进新增的 `tide` 命名配置"。
> 按 `docs/FOCUS.md` **F14** 实测，那样做**会连带炸掉全部 8 个配置**（`util/ibex_config.py:23-60` 是**全键强制**的），
> 故更正为下面这条分离路径，**原始意图（不动既有配置、照样能开 TIDE）不变**。

- **参数开关（`TIDE_EN` 等）走 `.core` 参数，不走 `ibex_configs.yaml`**：在 `.core` 的 `parameters:` 里声明并给 `default`
  （照抄模板 `ibex_top.core:56-60` 的 `FPGA_XILINX`：`default: false` + `paramtype: vlogdefine`），需要打开时命令行覆盖 `--TIDE_EN=1`。
  **禁止**把 `TIDE_EN` 写进 `ibex_configs.yaml`，也**禁止**改 `util/ibex_config.py` —— 加一个键会强制**全部配置**都补上它，
  且会让 `Makefile:7` 的 `$(shell ...)` 失败，**所有 make 目标连带崩**（含 CI 的 6 个）。
- **命名配置（`tide`）只在需要固定一整套参数组合时才新增**，且同样必须给全那 **19 个**既有键。**不改动既有配置**（yaml 共 8 个：
  `small` / `opentitan` / `maxperf` / `maxperf-pmp-bmbalanced` / `maxperf-pmp` / `maxperf-pmp-bmfull` / `maxperf-pmp-bmfull-icache` /
  `experimental-branch-predictor`；其中 **6 个进入 per-config CI**：`.github/workflows/ci.yml:114/118/122/126/130/134`）。
  若确实要加 `tide`，其基线取 `small` 并显式写 `BaseIsa=ibex_pkg::BaseIsaRV32I`、`WritebackStage=0`。
- 改动后至少验证 `small` 仍能构建。

### C6 上游资产只读（`docs/ENGINEERING.md` E7）

- `vendor/`（3148 个文件，OpenTitan primitives）**只读**，不手改，跟随上游。
- `lowrisc:prim:*` 是**工艺无关的抽象名**，不要按名字猜文件路径。
- `doc/`（上游 rst 文档）**尽量不改**；我们的文档一律放 `docs/`。

---

## 4 TIDE-ISA 契约摘要（**引用性重述**）

> ⚠️ 本节是 `../tide_isa/TIDE-ISA规范.md`（v0.9 冻结）的**实现视图摘录**，仅为方便 agent 就地查阅。
> **与规范冲突时一律以规范为准**；结构化数据源见 `../tide_doc/data/tide_*.csv`。
> 本仓**不得**依据本节推导规范中不存在的语义。

### 4.1 指令编码（ISA §3.2、§4）

| 指令 | 格式 | opcode[6:0] | funct3 | funct7[6:0] | rs1 | rs2 | rd |
|---|---|---|---|---|---|---|---|
| `QWAIT` | I 型变体 | custom-0 `0b0001011` | `0b000` | — | 大步进（**须为编译期常量**） | — | **必须 x0** |
| `QSYNC` | I 型变体 | custom-0 `0b0001011` | `0b011` | — | **必须 x0** | — | **必须 x0** |
| `QTRIG` | R 型变体 | custom-1 `0b0101011` | `0b000` | 高 2 位 `0` + 低 5 位 `PI[4:0]` | 通道掩码 `[31:0]` | 码字 `[31:0]`（opaque） | **必须 x0** |
| `QLOAD` | R 型变体 | custom-1 `0b0101011` | `0b001` | **必须 `0`** | 5 位立即数 = **读出队列号**（不读寄存器堆） | **必须 0** | 目标寄存器 |

**语义要点**

| 指令 | 语义 | 阻塞性 | 非法判定 |
|---|---|---|---|
| `QWAIT` | `TLR ← TLR + rs1 + imm[11:0]`；纯寄存器操作，**无副作用** | 不阻塞 | `rd ≠ x0`；`TLR + incr ≥ 2⁴⁸`（TLR 溢出）→ `illegal instruction` |
| `QSYNC` | 栅组汇合 + **释放拍锚定**：`TLR ← 0`、`elapsed ← 0`、`anchored ← 1` | 阻塞（栅组汇合 **且** 本 hart 全部定时队列播空） | `rs1 ≠ x0`；`rd ≠ x0`；`imm[11:4] ≠ 0`；超 `tqsyt` → `TQ_SYNC_TIMEOUT` |
| `QTRIG` | 合成 `ts′ = TLR + PI`；对掩码中**全部**目标统一检查（C0–C4）后**同拍原子入队**（all-or-none） | 阻塞（任一目标队列满 → C4 背压） | `funct7[6:5] ≠ 0`；`rd ≠ x0`；C0 未锚定 / C1 掩码越界 → `illegal`；C2/C3 → `TQ_LATE`；非阻塞模式满 → `TQ_FULL` |
| `QLOAD` | `rd ← 队头完成记录的 result[31:0]`；**队头弹出与指令退休原子** | 阻塞（等数据，**非**等时间） | `funct7 ≠ 0`；`rs2 ≠ 0`；超 `tqrty` → `TQ_RDY_TIMEOUT`；对 `tqsink=1` 队列执行 → 阻塞至超时 |

**入队检查 C0–C4**（ISA §2.2）：C0 已锚定；C1 掩码在范围内；C2 同通道 `ts′` **严格单调**；C3 `ts′ ≥ elapsed + TQ_GUARD`；C4 目标队列有空位。

**QWAIT 的三种用法**（ISA §4.1）：`qwait(x0, imm)` 纯立即数小步进 ≤4095；`qwait(rs1, 0)` 纯寄存器大步进（32 位）；`qwait(rs1, imm)` 混合。

**编译期义务（ISA §4.1、§6.4，硬件不校验）**：

- `QWAIT` 的 `rs1` 必须是**编译期可知常量**。若为运行时变量，二进制即**格式错误**（工具链不得产出）——硬件无法区分。
- 分支合流点由编译器用 `qwait(x0, 目标 − 当前TLR)` 对齐（差值为编译期常量）。
- 提前量证明：`TLR − WCET ≥ TQ_GUARD`。

### 4.2 CSR（ISA §5.1、§5.2）

**RO 诊断区 `0xFC0` 起**

| 地址 | 名称 | 内容 |
|---|---|---|
| `0xFC0` | `tqgc` | GC 低 32 位（读时自动锁存高 32 位快照） |
| `0xFC1` | `tqgch` | GC 高 32 位快照 |
| `0xFC2` | `tqtlr` | 本 hart `TLR[31:0]`（调试观察） |
| `0xFC3` | `tqtlrh` | 本 hart `TLR[47:32]`（低 16 位有效） |
| `0xFC4` | `tqstate` | `[0]` RUN latch；`[1]` anchored；`[2]` 本栅组 halted |
| `0xFC5` | `tqgrid` | `[3:0]` 本 hart 栅组号；`[12:8]` 组内规模 |
| `0xFC6` | `tqrdata` | 间接只读 `LATEST[tqridx]`（最近完成值，非破坏，不动 FIFO） |
| `0xFC7` | `tqres` | 派发时钟频率（kHz） |
| `0xFC8` | `tqschema` | `[15:0]` codeword schema 版本；`[31:16]` DD 实现/厂商标识 |
| `0xFC9` | `tqwm` | 定时队列水位（每通道历史最小剩余深度的最小值，压缩编码） |
| `0xFCA` | `tqerr` | 错误计数（各 cause 发生次数，饱和计数） |
| `0xFCB` | `tqsusp` | 各读出队列 FIFO 占用计数快照（压缩编码） |

**RW 配置区 `0x7C0` 起**

| 地址 | 名称 | 复位值 | 字段 |
|---|---|---|---|
| `0x7C0` | `tqcfg` | 参数锁存 | `[7:0]` `TQ_GUARD`；`[12:8]` `lg2(TQ_DEPTH)`；`[16:13]` `lg2(RQ_DEPTH)`；`[22:17]` `NCH`；`[28:23]` `NRQ`；`[29]` 非阻塞入队模式；`[31:30]` 保留 |
| `0x7C1` | `tqrty` | `0` | QLOAD 超时阈值（tick；`0` = 禁用，仅调试） |
| `0x7C2` | `tqsyt` | `0` | QSYNC 超时阈值（tick；`0` = 禁用，仅调试） |
| `0x7C3` | `tqhalt_req` | `0` | `[0]` W1S：写 1 请求本栅组 fail-stop 停机 |
| `0x7C4` | `tqerr_policy` | `0b1101_1100` | 按 cause 配置"检出即自动停机"位图：bit0→`TQ_LATE`、bit1→`TQ_FULL`、bit2→`TQ_UNDERRUN`、bit3→`TQ_SUSP_OVF`、bit4→`TQ_RDY_TIMEOUT`、bit5→`TQ_SYNC_TIMEOUT`、bit6→`TQ_FB_STALE`、bit7→`TQ_CODE_INVALID`（**复位仅 bit2/3/6/7 置位**） |
| `0x7C5` | `tqridx` | `0` | `[4:0]` 读出队列间接索引（配合 `tqrdata`） |
| `0x7C6` | `tqsink` | `0` | 读出队列无人值守位图（bit j = 1 → 队列 j 完成记录不入 FIFO；复位全 0 = 全记账） |

**关键实现约束**（`../tide_doc/data/tide_csr_map.csv`）

- `tqcfg` 中的 `NCH` / `NRQ` / `lg2(TQ_DEPTH)` / `lg2(RQ_DEPTH)` 是**综合常量**，**硬连线读回**，不可写；只有 `TQ_GUARD` 与非阻塞位可写。
- `tqgc` / `tqgch` / `tqtlr` / `tqtlrh` **仅供调试诊断**。**禁止**软件依据 GC 绝对值计算任何事件时间或循环计数（ISA §5.1 规范性注意）——编程模型中的一切时间均为**阶段局部**。
- `0x7C0` / `0x7C1` 与 Ibex 既有 `CSR_CPUCTRLSTS` / `CSR_SECURESEED` **冲突**（开放项 **O1**）——须回 `../tide_isa` 确认"Ibex 侧安全 CSR 让位"或改配地址，**本仓不得自行改地址**。
- MMIO 配置（每通道参数表、读出通道配置、DD 模块配置、波形/描述符表、流式采集 DMA）**不占 CSR 编码空间**；地址图见 `../tide_doc/data/tide_addr_map.csv`：TIDE-MMIO 窗口 `0x4001_0000`（64KB）、诊断/冻结读回窗口 `0x4002_0000`（64KB）。

### 4.3 错误模型（ISA §6.6）

| mcause | 名称 | 类型 | 检出点 | L1 硬件行为 | L2 默认 |
|---|---|---|---|---|---|
| `2` | illegal instruction | 同步精确异常 | 译码 / 入队 | TLR 溢出、C0 未锚定、C1 掩码越界、保留字段非 0、`rd ≠ x0` | 异常 |
| `24` | `TQ_LATE` | 同步精确异常 | 入队（C2/C3） | **拦截整条 QTRIG**（原子扇出，不压入任何队列）；DD 其余部分继续运行 | 异常，处理程序决策 |
| `25` | `TQ_FULL` | 同步精确异常（**仅非阻塞模式**） | 入队（C4） | 默认阻塞模式下为**背压 stall（非错误）** | — |
| `26` | `TQ_UNDERRUN` | **fail-stop** | 提交 | 本栅组全通道当前 tick 边界同步停发、队列冻结；杀掉本栅组全部阻塞中 TIDE 指令 | 自动停机 |
| `27` | `TQ_SUSP_OVF` | fail-stop（可配异步陷入） | 测量完成 | **丢弃新记录**（FIFO 内容不变） | 按 `tqerr_policy[3]`，默认 1 → 停机 |
| `28` | `TQ_RDY_TIMEOUT` | 同步精确异常 | QLOAD 阻塞 | 杀掉该 QLOAD；**不触发** fail-stop | 异常，处理程序决策 |
| `29` | `TQ_DIRTY` | 同步精确异常 | 全局对齐序列（P2） | 拒绝对齐并报异常 | 异常 |
| `30` | `TQ_SYNC_TIMEOUT` | 同步精确异常 | QSYNC 阻塞 | 杀掉该 QSYNC；**不触发** fail-stop | 异常，处理程序决策 |
| `31` | `TQ_FB_STALE` | fail-stop（可配异步陷入） | 提交 | 事件不提交 | 按 `tqerr_policy[6]`，默认 1 → 停机 |
| `32` | `TQ_CODE_INVALID` | fail-stop（可配异步陷入） | 提交 | 事件不提交 | 按 `tqerr_policy[7]`，默认 1 → 停机 |

**三个必须在 RTL 里小心的点**（`../tide_doc/data/tide_cause_map.csv`、ADR C3/C8）

1. **`mcause = 32` 超出 Ibex 现有 5 位 `lower_cause` 编码** → 实现侧须保留 `lower_cause` 加宽余量（开放项 **O2**）。
2. **cause `31` 双重身份**：Ibex 既有 **NMI 中断** cause 也是 31（`irq_int = 1`），而 `TQ_FB_STALE` = 31 是**异常**（`irq_int = 0`）→ 靠 `irq_int` 位区分，**验证必须覆盖两者共存**（ADR C8）。
3. **陷阱指向**（ISA §5.4）：同步精确异常 `mepc` = **出错指令 PC**（可重启重试）；提交时检出（`TQ_UNDERRUN` / `TQ_FB_STALE` / `TQ_CODE_INVALID` / `TQ_SUSP_OVF`）为 fail-stop 广播 + 杀掉阻塞中指令，否则为**当前执行点**（异步陷入）。

**同拍多错误报告优先级**（ISA §6.5，规范性）：fail-stop 广播 > 本地异步陷入 > 本地同步精确异常；同级取**通道/队列号最小者**。

**fail-stop 语义**（ISA §6.3）：停机是**全局一致**的——不存在"一半通道停了另一半还在发"的中间态。停机后队列内容冻结，`elapsed` 继续计数但出队禁用；恢复只能经**全局对齐序列**（ISA §4.4）。

### 4.4 实现参数（ISA §8 + 版本 A 定值）

| RTL 参数 | 含义 | 默认值 | 约束 / 暴露途径 |
|---|---|---|---|
| `TIDE_EN` | 综合期总开关 | `1` | 置 0 须**逐拍回归上游 Ibex**（不变量 I1） |
| `NHART` | hart 数 | `1`（版本 A） | 所有按 hart 复制的结构一律**按 N 参数化** |
| `NGRID` | 栅组数 | `1` | ≤ 16（受 QSYNC `imm[3:0]` 所限）；`tqgrid` |
| `NCH` | 通道数 | `16` | ≤ 32（受 QTRIG 32 位掩码所限）；`tqcfg[22:17]` |
| `NRQ` | 读出队列数 | `16` | ≤ 32（受 QLOAD 5 位队列号所限）；`tqcfg[28:23]` |
| `TQ_DEPTH` | 每通道定时队列深度 | `32` | ≥ 2；`lg2` 编码入 `tqcfg[12:8]` |
| `RQ_DEPTH` | 读出队列 FIFO 深度 | `4` | **≥ 2**；`lg2` 编码入 `tqcfg[16:13]` |
| `TQ_GUARD` | 入队保护带 | `8` | 4–16 tick；`tqcfg[7:0]` |
| `XBOARD_K` | 跨板固定传输拍数（含走线差） | `2` | ≥ 2（版本 A 单板自环） |
| `TLR_W` | TLR 位宽 | `48` | **规范固定**，只可用 localparam 表达 |
| `ELAPSED_W` | elapsed 位宽 | `48` | **规范固定** |
| `PI_W` | pre-interval 位宽 | `5` | **规范固定**（= 5，占 QTRIG funct7 低 5 位） |
| `TS_W` | 事件 ts′ 字段 | `48` | **规范固定** |
| `CODE_W` | 码字段宽 | `32` | **规范固定**（对 ISA opaque） |
| `EVENT_W` | 事件记录 | `80` | **规范固定** = 48 位 ts′ + 32 位 code |
| `DONE_W` | 完成记录 | `80` | **规范固定** = 32 位 result + 48 位 `T_done` |
| `TQ_RTY_TIMEOUT` | QLOAD 超时阈值 | `0`（禁用） | `tqrty` |
| `TQ_SYT_TIMEOUT` | QSYNC 超时阈值 | `0`（禁用） | `tqsyt` |
| `TQ_RES` | 派发时钟频率 | `250000` kHz | 对应 tick = 4 ns；`tqres` |

**参数落地约定**（`../tide_doc/chapters/09-interface-freeze.md` §3）

- **参数名即 RTL 参数名**：落地为 `rtl/ibex_tide_pkg.sv` 中的 `parameter` 或模块参数，命名不做二次转换。
- **规范固定的位宽不接受参数覆盖**（`TLR_W`、`ELAPSED_W`、`PI_W`、`TS_W`、`CODE_W`、`EVENT_W`、`DONE_W`）——以 localparam 常量形式出现，仅用于可读性。
- **综合期静态检查**：`NCH ≤ 32`、`NRQ ≤ 32`、`TQ_DEPTH ≥ 2`、`RQ_DEPTH ≥ 2`、`NGRID ≤ 16`、`XBOARD_K ≥ 2`、`PI_W = 5`。

### 4.5 不变量（`../tide_doc/chapters/09-interface-freeze.md` §2）

| 编号 | 不变量 |
|---|---|
| I1 | `TIDE_EN = 0` 时综合结果与仿真行为**逐拍回归上游 Ibex**；所有 TIDE 逻辑必须被参数门控 |
| I2 | 仅 M 模式；`PMP`、`SecureIbex`、`ICache`、`RV32B` 关闭 |
| I3 | 2 级流水：`WritebackStage = 0`、`BranchTargetALU = 0`、`BranchPredictor = 0` |
| I4 | 基线 ISA 为 `BaseIsaRV32I`（**非** `BaseIsaRV32IorCHERIoT`）；CHERIoT 逻辑不改动、不参与 TIDE 构建 |
| I5 | 版本 A：`NHART = 1`、`NGRID = 1`；但所有结构按 N 参数化，接口在版本 A 即就位 |
| I6 | **CD 永不阻塞于时间**：阻塞原因只能是**数据、空间、汇合**三者 |
| I7 | 不可推测副作用：TIDE 指令副作用必须在不可撤销之后发生（本核顺序发射、无推测） |
| I8 | 阻塞型指令遵循**可重启模型**：无状态谓词、原子退休、中断安全、fail-stop 杀伤 |

### 4.6 双域与生命周期要点

- **时间基准**（ISA §1.2）：`GC` = DD 的 64 位自由运行计数器（**仅硬件与诊断可见**，软件不得以其绝对值编程）；`TLR` = 48 位**阶段局部**时间线（自最近 `QSYNC` 锚点起算，锚定时归 0）；`elapsed` = 每栅组 48 位计数器，**仅 DD 内部提交比较与迟到检查基准，软件不可见**。
- **提交判据**：DD 在 `elapsed == ts′` **当拍**把码字交付通道硬件（ISA §2.4）。
- **阻塞可重启模型**（ISA §2.5）：无状态谓词、原子退休、中断安全；阻塞中指令可被 fail-stop **杀伤**。
- **生命周期 P0–P6**（ISA §1.4）：上电复位时 `GC` 冻结于 0、队列清空、`RUN latch = 0`、`anchored = 0`。
- **事件记录** 80 位定长 = `{48-bit ts′, 32-bit opaque code}`；**完成记录** = `{result[31:0], T_done[47:0]}`。

---

## 5 RTL 落点（change points）

> 行号对应 HEAD `96a34a56`（2026-10-15 自 `lowrisc/ibex` 同步；勘察时锚点 `af456e25` 与它的 `rtl/` **逐字节一致** —— 那 7 个新提交只动了 `doc/`/`dv/`/`vendor/`，故**行号未漂移**）。**同步上游后若对不上，用给出的搜索模式重新定位并更新行号**（`docs/README.md` §8.5）。

### 5.1 参照实现：CHERIoT 是本仓"加 ISA 扩展"的完整样板

CHERIoT 在同一个核里加了一整套 ISA 扩展，是**格式与门控方式的照抄范本**：

| 位置 | 内容 |
|---|---|
| `rtl/ibex_pkg.sv:37-38` | `BaseIsa` 枚举：`BaseIsaRV32I = 0` / `BaseIsaRV32IorCHERIoT = 1`（运行时可切换） |
| `rtl/ibex_pkg.sv:83` | `OPCODE_CHERI = 7'h5b`（custom-2） |
| `rtl/ibex_pkg.sv:84` | `OPCODE_AUICGP = 7'h7b`（custom-3） |
| `rtl/ibex_cheriot_pkg.sv` | CHERIoT 专用类型/枚举（**独立 pkg**，由 `ibex_pkg.core` 在 `ibex_pkg.sv` 之后注册） |
| `rtl/ibex_cheriot_ex.sv` | CHERIoT 执行单元（`:5` module 声明，`:1022` endmodule，**独立模块**） |
| `rtl/ibex_core.sv:911-913` | `ibex_cheriot_ex #(...) u_ibex_cheriot_ex (...)` 例化 |
| `rtl/ibex_decoder.sv:728/729`、`:818/819` | `OPCODE_CHERI` / `OPCODE_AUICGP` 译码分支 |
| `rtl/ibex_decoder.sv:202`、`:277`、`:365`、`:410`、`:716` … | 门控模式：`if ((BaseIsa == BaseIsaRV32IorCHERIoT) & (cheriot_enable_i == IbexMuBiOn) && ...)` |
| `rtl/ibex_id_stage.sv:1288-1291` | 4 条隔离断言（`:1286-1287` 是其注释）：`ASSERT_IF(IbexCheriotLoadDisabled, !cheriot_load_o, ...)` 等；`IbexInstrNotCheriot` 那条在 **`:1290`** |

**照抄要点**：新指令 = 新 pkg 类型 + 新执行模块 + 在 `ibex_core.sv` 例化 + 在 decoder 加分支 + 在 `ibex_pkg.sv` 加操作码常量；门控用**参数化生成块**。**TIDE 把 CHERIoT 的运行时门 `cheriot_enable_i` 换成编译期门 `TIDE_EN`**，并**照抄 `:1288-1291` 那组"未使能时输出必须为 0"的断言**。

### 5.2 必须改的既有文件

| 文件 | 落点（HEAD `96a34a56`） | 要做什么 |
|---|---|---|
| `rtl/ibex_pkg.sv` | `:71-85` `opcode_e`（`:72-84` 常量，`:85` 收尾） | 加 `OPCODE_TIDE0 = 7'h0b`（custom-0）、`OPCODE_TIDE1 = 7'h2b`（custom-1）。★ **追加在 `:84 OPCODE_AUICGP` 之后即可** —— 该枚举**不是按值排序**的（实测顺序 `03/0f/13/17/23/33/37/63/67/6f/73/5b/7b`），所以这样加是**纯追加，不改动任何既有行**，正好满足 D14 的"只加不改" |
| `rtl/ibex_pkg.sv` | `:92` `alu_op_e`（`ALU_ADD` 起始） | **默认不动**。QWAIT 的加法放 TIDE 自己的 49 位加法器里，避免触碰 ALU 的 8 处 `unique case` |
| `rtl/ibex_decoder.sv` | `:270` `unique case (opcode)` | **新增** `OPCODE_TIDE0` / `OPCODE_TIDE1` 两个分支，产生 `tide_op_o` / `tide_mask_o` / `tide_code_o` / `tide_pi_o` / `tide_imm12_o` / `tide_grid_o` / `tide_rq_idx_o` |
| `rtl/ibex_decoder.sv` | `:534`（CHERIoT 16 寄存器路径）与 `:1090`（主路径）的 `OPCODE_OP` | ❌ **绝对不要动**。TIDE 不复用 `OPCODE_OP` 的 funct 空洞 |
| `rtl/ibex_id_stage.sv` | `:476` `ibex_decoder #(...)` | 传 `TIDE_EN`；接出 TIDE 译码产物；新增 `tide_tlr_q[47:0]` 旁路寄存器 + 49 位加法器；`stall_tide` 并入既有 `stall_id` 归约 |
| `rtl/ibex_core.sv` | `:528` `ibex_if_stage`、`:663` `ibex_id_stage`、`:863` `ibex_ex_block`、`:911` `ibex_cheriot_ex`、`:1063` `ibex_load_store_unit`、`:1122` `ibex_wb_stage`、`:1438` `ibex_cs_registers`、`:1613` `ibex_pmp` | 连接 `tide_*` 信号；例化 `tide_dd_top` |
| `rtl/ibex_cs_registers.sv` | `csr_addr_i` 译码 `case` + `illegal_csr_insn_o` | 放行 `0x7C0–0x7C6`（RW）、`0xFC0–0xFCB`（RO）；`0x7C7–0x7FF` / `0xFCC–0xFFF` **判非法** |
| `rtl/ibex_controller.sv` | trap 仲裁链（`exc_cause_o` / `stall_id_i` / `flush_id_o`） | 接入 `tide_trap_i`（`tide_trap_t`）与 `tide_halt_i`；**fail-stop 广播 > 本地异步陷入 > 本地同步精确异常**，插在既有异常判定**之前**，且**不与 NMI/调试相对顺序冲突**（调试优先级不变） |
| `rtl/ibex_top.sv` | 顶层端口 | 透传 `tide_*`；`TIDE_EN = 0` 时全部悬空/常量优化 |
| `rtl/ibex_tracer.sv` | 反汇编 | 新增指令不加则反汇编成 `.word`（**只影响可读性，不影响功能**） |

### 5.3 建议新增文件与 `.core` 注册

| 新文件 | 内容 | 注册位置 | 依据 |
|---|---|---|---|
| `rtl/ibex_tide_pkg.sv` | `tide_op_e` / `tide_cause_e` / 跨域结构 / 参数 localparam | `ibex_pkg.core` 的 `files_rtl`（与 `rtl/ibex_cheriot_pkg.sv` 并列） | 冻结 §3、§4 |
| `rtl/ibex_tide_dd_top.sv` + 子模块 | DD：入队检查器（C0–C4）+ 定时队列 ×`NCH` + 出队比较器 + `elapsed`/`GC` + 读出队列 ×`NRQ` + `LATEST[]` + fail-stop 网络 + QSYNC 汇合 | `ibex_core.core` 的 `files_rtl` | 冻结 §6、第 5 章 |
| `rtl/ibex_tide_mmio.sv` | MMIO 桥（每通道参数表、DD 模块配置） | 同上 | 冻结 §6 |
| CD 侧逻辑 | TLR / 入队握手 / 阻塞重试 | **优先并入** `ibex_id_stage.sv`（冻结 §4.3 明确"位于 `id_stage` 旁的旁路寄存器"） | 冻结 §6.2 |

**必须同步更新的 `.core`**（`docs/ENGINEERING.md` E1；**这些 `.core` 全在仓根目录**，不在 `rtl/` 下）

- `ibex_pkg.core` —— 新增 pkg 文件
- `ibex_core.core` —— 其 `files_rtl` 是**手写列表**（含 `rtl/ibex_cheriot_ex.sv`、`rtl/ibex_core.sv` 等 21 项）
- `ibex_top.core` —— 顶层
- 若新增仿真专用文件，另看 `examples/simple_system/ibex_simple_system.core`、`shared/sim_shared.core`

**参数（`TIDE_EN` 等）也在 `.core` 里声明**（`docs/FOCUS.md` **F14**，且 `docs/ENGINEERING.md:61-62` 提示 `parameters:` 与 `targets.<t>.parameters` 是**两处**）：

- 在 `ibex_top.core` / `ibex_core.core` 的 `parameters:` 里加 `TIDE_EN`，**带 `default`**，模板见 `ibex_top.core:56-60` 的 `FPGA_XILINX`；
- **不要**加进 `ibex_configs.yaml`，**不要**改 `util/ibex_config.py`（全键强制，会炸全部配置）；
- 打开：`fusesoc ... --TIDE_EN=1`。

### 5.4 跨域信号名（已冻结，**不要另起名字**）

来源：`../tide_doc/data/tide_iface_signals.csv` 与冻结 §4.2/§5

| 信号 | 方向 | 说明 |
|---|---|---|
| `tide_enq_req`（`tide_enq_req_t`） | CD → DD | `valid` / `mask` / `code` / `pi` / `ts_prime`（49 位 = TLR + PI）/ `pc` |
| `tide_enq_stall` / `tide_enq_err`、`tide_enq_rsp`（`tide_enq_rsp_t`） | DD → CD | `stall`（C4 背压）/ `err` / `cause` / `ch`（最小出错或满通道号，`mtval2` 候选） |
| `tide_rq_pop`（`tide_rq_req_t`） | CD → DD | `valid` / `rq_idx[4:0]` |
| `tide_rq_rsp`（`tide_rq_rsp_t`） | DD → CD | `valid = 0` → FIFO 空（QLOAD 继续阻塞）/ `result` |
| `tide_sync_req`（`tide_sync_req_t`） | CD → DD | `valid` / `grid[3:0]` |
| `tide_sync_anchor` | DD → CD | **单拍脉冲**：同拍清零 `TLR`/`elapsed`、置 `anchored`，且该拍退休 |
| `tide_trap`（`tide_trap_t`） | DD → CD | `valid` / `is_failstop`（仲裁最高优先）/ `cause` / `ch` / `ts`（`mtval2`） |
| `tide_halt_i` | DD → CD | fail-stop 杀伤：以 `TideCauseUnderrun` 精确异常终止阻塞中指令，`mepc` = 该指令 PC |
| `tide_xboard` | 板间（版本 C） | 版本 A 仅端口 + 协议状态机 + 单板自环；**不在 CD↔DD 接口内** |
| `tide_tlr_q[47:0]` | 内部（`id_stage` 旁） | **不进通用寄存器堆**，不参与 forwarding/stall；只经 `tqtlr`/`tqtlrh` 诊断读出 |

**握手与原子性铁律**（冻结 §5.1）

| 交互 | 规则 |
|---|---|
| QTRIG 入队 | `tide_enq_req.valid` 保持至 `stall` 或 `err` 明确回送；回送 `stall` 时 CD 保持指令不变（可重启）。**all-or-none**：先对全部目标统一检查，`check_pass` **全 AND 归约后**才统一发写使能——**严禁部分入队** |
| QTRIG 退休 | 入队成功（无 err 且无 stall）的**同一拍**退休；不存在"改了状态但未退休"的窗口 |
| QLOAD 弹出 | **取队头与指令退休同拍原子** |
| QSYNC 汇合 | 释放以 `tide_sync_anchor` 单拍脉冲回送，**释放拍同拍**清零 TLR/elapsed、置 anchored，且该拍退休 |
| 异常与停机 | `tide_trap` 异步到达；`is_failstop = 1` 时仲裁最高优先；fail-stop 必须**杀伤本栅组全部阻塞中 TIDE 指令**并以 `TQ_UNDERRUN` 送达 |

**时钟域**：默认**同钟域**（`clk_i` 与 DD 派发时钟同源），上述单拍语义成立。MMIO 配置口**允许异步**（配置写不要求逐拍确定性）。跨板信号按"打拍同步 + 拍数恒定 + 预约生效"（`XBOARD_K`）处理，**不向 CD 引入非确定延迟**。

---

## 6 构建与验证

### 6.1 环境铁律（⚠️ Windows 开发机）

官方流程是 **Linux + FuseSoC + Verilator + RISC-V GCC**。Windows 下只有两条可行路径：

1. **WSL2**（推荐）
2. **Nix**：仓库根有 `flake.nix` / `flake.lock`，`nix develop` 可拿到接近 CI 的环境

**不要在纯 PowerShell 里跑这套流程**。必挂的地方：`common.mk` 里的 `srec_cat -byte-swap`、`$(shell dirname $(realpath …))`，以及 fusesoc 生成的一堆 shell 脚本。

**改代码同理（`../tide_prj/AGENTS.md` §7.4-5）**：不要用 PowerShell（`Set-Content`、`-replace` 等）直接改写源码文件（BOM/CRLF/编码会污染文件、破坏 Linux 侧工具链）；进 Linux 环境（本开发环境为挂载了本仓库的容器 `synopsys`）用 `sed` / `awk` / `python` 修改。

**工具版本（CI 锁定，`ci/vars.env`）**

| 工具 | 版本 |
|---|---|
| Verilator | `v4.210` |
| RISC-V 工具链 | `20220210-1`，变体 `lowrisc-toolchain-gcc-rv32imcb` |
| Verible | `v0.0-3622-g07b310a3` |
| riscv-compliance | git `844c666` |
| Spike（Ibex 版） | `20220817-git-eccdcb1` |

### 6.2 命令速查

```bash
# 依赖
pip3 install -U -r python-requirements.txt

# 看命名配置会展开成什么参数
./util/ibex_config.py small fusesoc_opts
make test-cfg

# 构建 / 运行 Simple System
fusesoc --cores-root=. run --target=sim --setup --build \
        lowrisc:ibex:ibex_simple_system $(./util/ibex_config.py small fusesoc_opts)
make build-simple-system
make -C examples/sw/simple_system/hello_test
make run-simple-system

# 打开 TIDE（不要动 ibex_configs.yaml，见 F14 / D16）
fusesoc --cores-root=. run --target=sim --setup --build \
        lowrisc:ibex:ibex_simple_system $(./util/ibex_config.py small fusesoc_opts) --TIDE_EN=1

# Lint（改完 RTL 必跑，两个都要）
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# CSR testbench
make build-csr-test && make run-csr-test

# 主回归（UVM + riscv-dv）
cd dv/uvm/core_ibex
make TEST=riscv_machine_mode_rand_test ITERATIONS=1
make TEST=riscv_machine_mode_rand_test ITERATIONS=1 SEED=123 WAVES=1   # 复盘波形
make COV=1                                                             # 覆盖率
```

> ⚠️ **不要用 `make lint-core-tracing`** —— `Makefile:62` 引用的是**过期 core 名** `lowrisc:ibex:ibex_core_tracing`（仓库里不存在，真实名是 `lowrisc:ibex:ibex_top_tracing`，见 `ibex_top_tracing.core:5`）。详见 `docs/FOCUS.md` F13。

运行产物（已在 `.gitignore`）：`ibex_simple_system.log`、`ibex_simple_system_pcount.csv`、`trace_core_*.log`。

### 6.3 分层验证链（按序，从便宜到贵）

| 层 | 目标 | 命令 / 位置 | 何时必须跑 |
|---:|---|---|---|
| 0 | Verilator lint | `fusesoc ... --target=lint --tool=verilator` | **每次改 RTL** |
| 1 | Verible lint | `fusesoc ... --target=lint --tool=veriblelint` | **每次改 RTL** |
| 2 | CSR testbench | `make run-csr-test`（`dv/cs_registers/`） | 改 CSR 后 |
| 3 | Simple System + `hello_test` | `make run-simple-system` | **每次改 RTL** |
| 4 | RISC-V compliance | `dv/riscv_compliance/` | 改译码 / 执行后 |
| 5 | Spike 协同仿真 | `dv/cosim/` | 改译码 / 执行后 |
| 6 | UVM + riscv-dv 主回归 | `dv/uvm/core_ibex/` | **提交前** |

### 6.4 TIDE 专属测试（**本仓尚不存在，需自建**）

| 测试 | 要验证的语义 | 依据 |
|---|---|---|
| C0–C4 入队检查 | 未锚定 / 掩码越界 → `illegal`；`ts′` 非严格单调或早于 `elapsed + TQ_GUARD` → `TQ_LATE`；队列满 → 背压 stall | ISA §2.2 |
| **原子扇出** | 掩码 `{ch0, ch2}` 且 `ch2` 满 → **禁止**先把事件压入 `ch0`；两队列都空后**同拍**压入 | ISA §4.2 |
| **QLOAD 真 FIFO** | 连续两次完成 → 两次 `QLOAD` 读到**不同**值（**不得静默合并**）；队列满再完成 → 丢**新**留旧 + `TQ_SUSP_OVF` | ISA §4.3 |
| QSYNC 锚定 | 释放拍同拍 `TLR ← 0`、`elapsed ← 0`、`anchored ← 1`，且该拍退休 | ISA §4.4 |
| fail-stop 全局一致 | 停机后**不存在**"一半通道停一半还在发"的中间态；阻塞中指令被杀伤并以精确异常送达 | ISA §6.3 §6.5 |
| `mcause` 边界 | **cause 31 与 NMI 共存**（靠 `irq_int` 位区分）；**cause 32 需要 `lower_cause` 加宽** | ADR C3 / C8 |
| 可重启模型 | 阻塞中被中断 → `mret` 重执行 ≡ 继续等待；无部分状态 | ISA §2.5 / I8 |

### 6.5 `TIDE_EN = 0` 回归（不变量 I1 的可执行检验）

`TIDE_EN = 0` 时综合结果与仿真行为必须**逐拍回归上游 Ibex**。这是"只加不改"的机器化证明：用 `small` 配置跑 Simple System + `hello_test`，把日志与**未改动前的基线**逐字节比对。

---

## 7 提交前自检清单

> 在 `docs/ENGINEERING.md` E9 的基础上，补上 TIDE 专属项。**逐条打勾**。

**改之前**

- [ ] 读了一遍 `docs/FOCUS.md`，确认没踩已记录的 14 条陷阱
- [ ] 确认这次改动**是否触碰既有指令**——若触碰，**停手**（违反 C1 附加条款 1）
- [ ] 确认所有新增逻辑都在 `TIDE_EN` 门控之内（C1 附加条款 2）
- [ ] 若新增参数 → **已按 F14 走 `.core` `parameters:` + `default`**，**没有**加进 `ibex_configs.yaml`、**没有**改 `util/ibex_config.py`；`./util/ibex_config.py small fusesoc_opts` 仍能正常输出（C5）
- [ ] 若涉及语义 / CSR / cause → 已回 `../tide_isa` 解决，**没有在本仓自行定义**（§1 硬规则）

**提交前**

- [ ] 新增 / 删除的 `.sv` **已加进所有相关 `.core`**（`ibex_pkg.core` / `ibex_core.core` / `ibex_top.core`）（C4）
- [ ] **Verilator lint 通过**（E3）
- [ ] **Verible lint 通过**（E3）
- [ ] 新模块有 `` `ASSERT_KNOWN `` 等断言，用 `prim_assert.sv` 的宏（E5）
- [ ] 照抄了 CHERIoT 的**隔离断言**风格（未使能时 TIDE 输出必须为 0）
- [ ] `small` 配置仍能构建（E2）
- [ ] Simple System + `hello_test` 能跑起来（E6 第 3 层）
- [ ] `TIDE_EN = 0` 回归比对通过（I1）
- [ ] C/C++ 已 `clang-format`；`.` 用 `--signoff`（E4）
- [ ] 提交信息符合 E4 格式
- [ ] **决策有变化 → 已更新 `docs/README.md` 决策台账（加行，不改旧行）**
- [ ] **新发现的陷阱 → 已加进 `docs/FOCUS.md`（带证据行号）**
- [ ] 若改了本文件 `AGENTS.md` 的事实性内容（行号、路径、参数）→ 已核对来源

**同步上游之后**

- [ ] 先判定是不是**纯快进**：`git fetch upstream master --no-tags` 后跑
      `git merge-base --is-ancestor HEAD upstream/master`（0 = 是祖先，可快进）+
      `git rev-list --left-right --count HEAD...upstream/master`（左=本地独有，右=上游独有）
- [ ] 若不是纯快进（左侧计数 > 0，即已分叉）→ **停下来报告，不要贸然 merge**
- [ ] `docs/FOCUS.md` 与**本文件 §5** 里的行号是否还对得上？对不上就按搜索模式重新定位并更新
- [ ] 上游是否引入新顶层参数 / 新命名配置，需要 `tide` 配置同步？
- [ ] `vendor/` 是否被上游更新（**不要手改**，跟着上游走）
- [ ] CHERIoT 相关代码是否被上游改动（若动了 `opcode_e` / decoder 结构，**必须复核 §5.2 的行号与"只加不改"前提**）
- [ ] 同步后复核 `docs/FOCUS.md` F13 是否已被上游修好（2026-10-15 同步到 `96a34a56` 时**仍未修**）

---

## 8 禁止事项

1. **禁止改动既有指令**（RV32IMC / CHERIoT / Zca-Zcb-Zcmp）的译码结果、异常语义与时序。
2. **禁止**让 TIDE 新增逻辑逃出 `TIDE_EN` 门控。
3. **禁止在本仓定义、解释或扩展 ISA 语义**（`../tide_prj/AGENTS.md` §6-1）。
4. **禁止自行分配 CSR 地址**以绕过 O1 冲突（`0x7C0`/`0x7C1` 撞 `CSR_CPUCTRLSTS`/`CSR_SECURESEED`）。
5. **禁止修改 `vendor/`**（3148 个文件，只读）。
6. **禁止往 `doc/`（上游 rst）里加我们的内容**——我们的文档一律放 `docs/`，否则同步上游时是纯粹的成本。
7. **禁止把 `src_files.yml` 当对账依据**（已过期，含 3 个死条目）。
8. **禁止改动 `ibex_configs.yaml` 已有的 CI 配置**（6 个进入 per-config CI：`small`/`opentitan`/`maxperf`/`maxperf-pmp-bmbalanced`/`maxperf-pmp-bmfull`/`experimental-branch-predictor`）——只能**新增** `tide`。
9. **禁止复用 `OPCODE_OP` 的 funct 空洞**承载 TIDE 指令。
10. **禁止删除或重排**决策台账既有行、`FOCUS.md` 既有条目。
11. **禁止在没有行号证据的情况下**写"这个工程怎么工作"的论断（`docs/README.md` §8.1）。

---

## 9 术语与命名

**双域**：**CD**（经典域，执行时序非确定，可被中断/阻塞）/ **DD**（确定域，所有对外可见事件的提交时刻逐拍确定）。

| 术语 | 含义（以 ISA §0 术语表为准） |
|---|---|
| GC | DD 的 64 位单调递增自由运行计数器，单位 1 tick。**仅硬件与诊断可见**，软件不得以其绝对值编程 |
| 锚点 anchor | 本栅组最近一次 QSYNC 释放拍（对应 GC 值记 A，仅硬件可见） |
| 阶段 phase | 相邻两次 QSYNC 之间的程序区间；**软件时间的度量单位**，时长上限 2⁴⁸ tick |
| TLR | 48 位**阶段局部**时间线：相对锚点的 tick 数，每 hart 一个，锚定时归 0 |
| elapsed | 每栅组一个的 48 位计数器；仅 DD 内部提交比较与迟到检查基准，**软件不可见** |
| tick | 时间基本单位 = 派发时钟周期（250 MHz → 4 ns，1 GHz → 1 ns） |
| 通道 channel | DD 中一条独立的事件提交路径（定时队列 + 出队逻辑 + 后端），编号 `0…NCH−1`（≤ 32）；**每通道固定归属一个栅组** |
| 读出队列 | 读出通道固定的结果信箱，编号 `0…NRQ−1`（≤ 32），与读出通道**硬件一一对应**；每队列是深度 `RQ_DEPTH` 的 **FIFO** |
| 完成记录 | `{result[31:0], T_done[47:0]}`；每个成功提交的测量事件产生恰好一个 |
| 事件 | `{ts′, code}`，跨域提交的最小单位，**80 位定长**；`code` 的 32 位是运输宽度，内部语义**对 ISA 不可见** |
| 条件执行 | 后端执行器的扩展能力；ISA 不定义其机制，仅提供错误槽 `TQ_FB_STALE` |
| 栅组 grid group | QSYNC 的参与者集合（多 hart / 多板），共享同一锚点与同一 `elapsed` |
| fail-stop | 检测到特定时序/反馈错误后 DD 停止提交新事件并广播停机，**绝不晚发或乱序补发** |

**命名规则（落地 RTL 时遵守）**

- 跨域信号前缀统一 `tide_`；类型前缀 `tide_`，枚举后缀 `_e`，结构后缀 `_t`（**沿用 Ibex 风格**）。
- 指令助记符保持 ISA 写法：`QWAIT` / `QTRIG` / `QLOAD` / `QSYNC`。
- 错误码命名 `TQ_*`（如 `TQ_LATE`、`TQ_RDY_TIMEOUT`）；CSR 名用小写下划线（`tqschema`、`tqerr_policy`）。
- `../tide_doc/chapters/09-interface-freeze.md` 已冻结的类型 —— `tide_op_e`、`tide_cause_e`、`tide_mask_t`、`tide_pi_t`、`tide_code_t`、`tide_ts_t`、`tide_tsx_t`、`tide_result_t`、`tide_enq_req_t`、`tide_enq_rsp_t`、`tide_rq_req_t`、`tide_rq_rsp_t`、`tide_sync_req_t`、`tide_trap_t` —— **直接照用，不要另起名字**。
- **旧名已废弃**：`QCU` / `QCU-ISA`（Quantum Control Unit）不得再出现在任何新增文本、RTL 标识符或注释中。

---

## 10 文档维护约定（沿用 `docs/README.md` §8）

1. **证据优先**：任何"这个工程怎么工作"的论断都要写 `文件:行号`。**没有行号的结论视为未验证。**
2. **决策要留痕**：设计改了 → 决策台账**加一行**并注明取代了哪条，不要抹掉历史。
3. **陷阱要写"怎么验证"**：`FOCUS.md` 每条都应能从 RTL 或仿真复现，否则标"待确认"。
4. **本目录不描述上游行为**：上游规格直接引用 `doc/`，避免抄一份然后抄错。
5. **行号会漂移**：`FOCUS.md` 与**本文件 §5** 的行号对应 HEAD `96a34a56`；同步上游后按给出的搜索模式重新定位并更新。
6. **本文件的事实性内容**在改动前必须回来源核对：ISA → `../tide_isa`，接口 → `../tide_doc/chapters/09-interface-freeze.md` 与 `../tide_doc/data/*.csv`，上游行为 → `doc/`。

---

*本文件是**操作约定**，不定义设计。上层权威：[`../tide_isa/TIDE-ISA规范.md`](../tide_isa/TIDE-ISA规范.md) > [`../tide_doc/chapters/`](../tide_doc/chapters/) > [`docs/`](./docs/)。*
