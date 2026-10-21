# Tide 工程文档

本目录存放**本项目自产的文档**，与上游 Ibex 官方文档（`doc/`，reStructuredText）**刻意分开**。

| 对比项 | `doc/`（上游） | `docs/`（本项目） |
|---|---|---|
| 内容 | Ibex 核本身的规格与设计 | 我们的系统设计、决策、纪律、陷阱 |
| 语言 | 英文 rst | 中文 + 英文标识符 |
| 维护 | 随上游更新 | 我们自己维护 |
| 能改吗 | **尽量不改**，改了同步上游会冲突 | 随便改 |

> **铁律**：不要往 `doc/` 里加我们的内容。上游同步（`git fetch upstream master --no-tags` + `git merge --ff-only upstream/master`）时那是纯粹的成本。

配套文档：
- [`ENGINEERING.md`](./ENGINEERING.md) —— **工程纪律**（硬规则 + 改动自检清单）
- [`FOCUS.md`](./FOCUS.md) —— **关注重点**（14 条陷阱，带证据行号）
- [`../AGENTS.md`](../AGENTS.md) —— **操作约定**（AI agent / 协作者入口：仓关系与权威顺序、TIDE-ISA 契约摘要、RTL 落点与行号、构建与验证链、提交自检清单）

---

## 1. 我接手的是什么

| 项 | 值 |
|---|---|
| 上游 | `https://github.com/lowrisc/ibex` |
| 本仓 remote `origin` | `https://github.com/oiwic/ibex.git`（**只读来源，无推送权限**） |
| 官方 remote `upstream` | `https://github.com/lowrisc/ibex.git`（**2026-10-15 添加**） |
| 分支 | `master` |
| 勘察时 HEAD | `af456e25 [dv] Add zcmp_reserved_test`（= `oiwic/ibex` master） |
| 当前 HEAD | `96a34a56 [doc] Fix the icache data ECC layout`（= `upstream/master`，2026-10-15 同步） |
| 工作树 | clean（勘察时无任何未提交改动） |
| 许可 | Apache-2.0（`vendor/` 内部分文件另有标注） |
| 已含特性 | CHERIoT 扩展、ratified Zba/Zbb/Zbc/Zbs + Zbkb/Zbkx、Zcmp |

**关键结论：这是一个（勘察时）尚未被改造过的 Ibex 工作树。**

> ⚠️ **2026-10-15 更正 —— 原表述"CHERIoT fork"是错的**：
> 本仓**不是** CHERIoT fork。**CHERIoT 是上游 lowRISC 自带的**特性
> （`f1cea015 2026-08-17 [rtl] Implement CHERIoT ISA`，Samuel Riedel，在官方历史里）。
> `oiwic/ibex` 的 master 与官方 `lowrisc/ibex` master **在同一条线性历史上**，只是落后若干提交
> （实测 `git merge-base --is-ancestor af456e25 upstream/master` 成立，`--left-right --count` = `0 7`）。
> 勘察时误判为"fork"，进而推导出"上游没有 CHERIoT"——这个推论**不成立**，`AGENTS.md` §1 已同步更正。

全仓库对 `tide` / `Tide` / `TIDE` 做全文检索（排除 `vendor/` 与 `.git/`）—— **零命中**。也就是说：

- 没有项目自有的 RTL
- 没有项目自有的地址映射
- 没有项目自有的构建目标
- 我们是从**成熟上游工程**上做增量，不是在空地上盖楼

### ★ 第一原则

> **能靠"加参数 / 加外设 / 加顶层"解决的问题，就不要改核心 RTL。**
>
> `rtl/ibex_*.sv` 是上游维护、且有验证背书（`opentitan` 配置达 V2S）的资产。
> 每改一行，你都要自己承担验证责任，并且每次同步上游都要重新处理冲突。
> 我们的加法应该集中在：**新的系统顶层、新的外设、`ibex_configs.yaml` 里新增一个命名配置**。

> ★ **2026-10-15 更新**：为承载 TIDE-ISA 的 4 条新指令（`QWAIT`/`QTRIG`/`QLOAD`/`QSYNC`），
> 本第一原则的**绝对形式**（"不改核心 RTL"）已被 **D14 取代**——现允许新增与修改 `rtl/ibex_*.sv`，
> 但附加三条不可协商条款：①既有指令逐拍不得改动；②全部 TIDE 逻辑必须 `TIDE_EN` 门控；
> ③不新增顶层端口。**"能加参数/外设/顶层解决的就别改核心 RTL"这一取向依然成立。**

---

## 2. 仓库地图

| 目录 | 文件数 | 作用 | 我们能改吗 |
|---|---:|---|---|
| `rtl/` | 34 | **Ibex 核心 RTL**（`ibex_top.sv` 等） | ⚠️ 尽量不改 |
| `shared/` | 8 | 简化的共享 IP（6 个 `.sv` + 2 个 `.core`），**我们的新 IP 就跟它做邻居** | ✅ 可加、可仿写 |
| `vendor/` | 3148 | vendored 的 OpenTitan primitives（`lowrisc:prim:*`、`lowrisc:dv:*`） | ❌ **只读** |
| `examples/` | 33 | Simple System（RTL + C/C++ + SW 框架 + 测试程序） | ✅ 主要工作区 |
| `dv/` | 314 | 验证：`uvm/`（riscv-dv + UVM）、`cosim/`、`formal/`、`cs_registers/`、`riscv_compliance/`、`verilator/` | ⚠️ 按需 |
| `formal/` | 25 | 形式化（ICache 等的 FPV） | ⚠️ 按需 |
| `lint/` | 2 | 全局 lint 豁免：`verible_waiver.vbw`、`verilator_waiver.vlt` | ✅ 会用到 |
| `syn/` | 25 | 综合/面积脚本（Yosys + sv2v、DC、Genus 配置） | ⚠️ 按需 |
| `doc/` | 51 | 上游官方文档（四大部分） | ❌ 不加内容 |
| `ci/` | 5 | CI 脚本、锁定版本 `vars.env` | 👀 只读参考 |
| `.github/` | 8 | GitHub Actions：`ci.yml`、`ci-formal.yml`、`pr_lint.yml`、`cla.yml` | ❌ 不改 |
| `util/` | 8 | `ibex_config.py`（**命名配置工具**）、`lint_commits.py` | 👀 只读参考 |
| `nix/` | 7 | Nix 环境（配根目录 `flake.nix` / `flake.lock`） | 👀 参考 |

### 顶层构建文件

| 文件 | 作用 |
|---|---|
| `ibex_configs.yaml` | **命名配置的唯一来源**（`small` / `opentitan` / `maxperf` / `maxperf-pmp-bmbalanced` / `maxperf-pmp-bmfull` / `experimental-branch-predictor`） |
| `*.core`（根目录 + `examples/`） | **FuseSoC 文件清单** —— 仿真/综合/lint 的唯一权威文件表 |
| `src_files.yml` | 给**不使用 FuseSoC** 的流程的文件清单 —— ⚠️ **实测已过期，不要当对账依据**（详见 `ENGINEERING.md` E1） |
| `Makefile`（根） | 常用命令速记（`build-simple-system`、`run-simple-system`、`lint-core-tracing`、`build-csr-test`…） |

---

### `shared/` 的真实内容（**已逐一核对**）

```
shared/
├── sim_shared.core            name: "lowrisc:ibex:sim_shared"（被 simple_system / compliance 依赖）
├── fpga_xilinx.core
└── rtl/
    ├── bus.sv                 1 主 3 从总线，含 decode error
    ├── ram_1p.sv              ★ 单端口 RAM（1 拍延迟）
    ├── ram_2p.sv              ★ 双端口 RAM（A=数据，B=取指）
    ├── timer.sv               提供 mtime/mtimecmp，用于生成定时器中断
    ├── sim/simulator_ctrl.sv  仿真控制：ASCII 输出 + 停机
    └── fpga/xilinx/clkgen_xil7series.sv
```

`shared/sim_shared.core:7-19` 的文件表列出的就是：`rtl/ram_1p.sv`、`rtl/ram_2p.sv`、`rtl/bus.sv`、
`rtl/sim/simulator_ctrl.sv`、`rtl/timer.sv`，依赖 `lowrisc:prim:assert`、`lowrisc:prim:ram_1p`、`lowrisc:prim:ram_2p`。

> ★ **注意**：`shared/` 里**没有** `prim_assert.sv`、`prim_clock_gating.sv`、`prim_ram_*.sv`。
> 这些 primitives 全在 `vendor/lowrisc_ip/ip/prim/`，通过 FuseSoC core（`lowrisc:prim:assert`、
> `lowrisc:prim:clock_gating`、`lowrisc:prim:ram_1p`、`lowrisc:prim:ram_2p`…）引入。
> 例如 `vendor/lowrisc_ip/ip/prim/prim_assert.core` → `name: "lowrisc:prim:assert:0.1"`。

---

## 3. 三条主线

### 主线 A —— RTL

```
rtl/ibex_top.sv                  ← 核的顶层（所有参数都在这里）
  ├── rtl/ibex_core.sv
  ├── rtl/ibex_if_stage.sv  → rtl/ibex_prefetch_buffer.sv / rtl/ibex_icache.sv
  ├── rtl/ibex_id_stage.sv  → rtl/ibex_decoder.sv / rtl/ibex_cs_registers.sv / rtl/ibex_controller.sv
  ├── rtl/ibex_load_store_unit.sv
  ├── rtl/ibex_pmp.sv
  └── vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv   （经 lowrisc:prim:assert 引入）

examples/simple_system/rtl/ibex_simple_system.sv   ← 唯一的"系统"范例
  ├── shared/rtl/bus.sv              （1 主 3 从，含 decode error）
  ├── shared/rtl/ram_2p.sv           （A 口=数据，B 口=取指）
  ├── shared/rtl/sim/simulator_ctrl.sv
  └── shared/rtl/timer.sv
```

### 主线 B —— 验证

```
dv/uvm/core_ibex/        riscv-dv 随机指令 + UVM + Spike 比对（主回归）
dv/uvm/icache/           ICache 专用 UVM
dv/cosim/                Simple System 与 Spike 的协同仿真
dv/cs_registers/         CSR testbench（tb_cs_registers）
dv/riscv_compliance/     RISC-V 官方 compliance 套件
formal/                  形式化
```

### 主线 C —— 软件

```
examples/sw/simple_system/common/common.mk   构建规则（ARCH ?= rv32imc）
examples/sw/simple_system/common/crt0.S      启动代码（向量表在第一段）
examples/sw/simple_system/common/link.ld     链接脚本（RAM 0x100000，栈 0x130000）
examples/sw/simple_system/common/simple_system_regs.h   MMIO 寄存器定义
examples/sw/simple_system/hello_test/        最小程序范例
```

---

## 4. 怎么跑起来

> ⚠️ **我们的开发机是 Windows**。这个工程的官方流程是 **Linux + FuseSoC + Verilator + RISC-V GCC**。
> Windows 下两条可行路径：
> 1. **WSL2**（推荐）；或
> 2. **Nix**：仓库根目录有 `flake.nix` / `flake.lock`，用 `nix develop` 可拿到接近 CI 的环境。
>
> ⚠️ 会卡住的地方（别浪费时间去试）：`common.mk` 里的 `srec_cat -byte-swap`、`$(shell dirname $(realpath …))`、
> 以及 `fusesoc` 生成的一堆 shell 脚本。**不要试图在纯 PowerShell 里跑这套流程。**

`ci/vars.env` 锁定的工具版本（CI 实际使用）：

| 工具 | 版本 |
|---|---|
| Verilator | `v4.210` |
| RISC-V 工具链 | `20220210-1`，变体 `lowrisc-toolchain-gcc-rv32imcb` |
| Verible | `v0.0-3622-g07b310a3` |
| riscv-compliance | git `844c666` |
| Spike（Ibex 版） | `20220817-git-eccdcb1` |

```bash
# ---- 依赖 ----
pip3 install -U -r python-requirements.txt

# ---- 看某个命名配置会展开成什么参数 ----
./util/ibex_config.py small fusesoc_opts
make test-cfg                       # 等价，默认 IBEX_CONFIG=small

# ---- 构建 Simple System 仿真器 ----
fusesoc --cores-root=. run --target=sim --setup --build \
        lowrisc:ibex:ibex_simple_system $(./util/ibex_config.py small fusesoc_opts)
make build-simple-system            # 用 IBEX_CONFIG ?= small

# ---- 编译软件 ----
make -C examples/sw/simple_system/hello_test

# ---- 运行 ----
./build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
    --meminit=ram,examples/sw/simple_system/hello_test/hello_test.elf
make run-simple-system              # 一键（含构建 SW）

# ---- Lint（改完 RTL 必跑，见 ENGINEERING.md E3） ----
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# ---- CSR testbench ----
make build-csr-test && make run-csr-test

# ---- 主回归（UVM + riscv-dv） ----
cd dv/uvm/core_ibex
make TEST=riscv_machine_mode_rand_test ITERATIONS=1
make TEST=riscv_machine_mode_rand_test ITERATIONS=1 SEED=123 WAVES=1   # 复盘波形
make COV=1                                                             # 带覆盖率
```

运行后产生（已在 `.gitignore` 中）：`ibex_simple_system.log`、`ibex_simple_system_pcount.csv`、`trace_core_00000000.log`。

---

## 5. 上游文档怎么读（`doc/`）

`doc/index.rst` 把官方文档分成四部分：

| 部分 | 什么时候读 |
|---|---|
| `doc/01_overview/` | 想确认"这个核符合哪些标准" → `compliance.rst`（**明确写只做 M-Mode 和 U-Mode**，第 89 行） |
| `doc/02_user/` | **接核必读** → `integration.rst`（端口/参数/时序）；`configuration.rst`（命名配置）；`system_requirements.rst` |
| `doc/03_reference/` | 深入设计 → `pipeline_details`、`instruction_fetch`、`load_store_unit`、`cs_registers`、`exception_interrupts`、`pmp`、`icache`、`rvfi`、`security`、`performance_counters` |
| `doc/04_developer/` | 开发流程 → 目前只有 `concierge.rst`（**`index.rst` 里带 `.. todo::`，说明上游自己的开发者指南还没写完**） |

**按优先级推荐的精读顺序**（针对我们的最小系统任务）：

1. `doc/02_user/integration.rst` —— 所有顶层参数和端口说明
2. `doc/03_reference/pipeline_details.rst` —— 2/3 级流水线、flush 时机
3. `doc/03_reference/instruction_fetch.rst` —— 取指通路与 prefetch buffer
4. `doc/03_reference/exception_interrupts.rst` —— 异常/中断/`wfi`
5. `doc/03_reference/cs_registers.rst` —— CSR 全表
6. `doc/03_reference/pmp.rst` —— PMP 语义与 granule
7. `examples/simple_system/README.md` —— 唯一的系统范例（含内存映射表）

---

## 6. 决策台账（Decision Log）

> 设计阶段已确认的决策。**任何改动都要在这里留痕**：加一行，不要改旧行（旧行标注"被 Dxx 取代"）。

| ID | 决策 | 理由 / 依据 | 状态 |
|---|---|---|---|
| D1 | 采用**自定义 32 位地址映射**，不复用 simple_system 的 `0x20000 / 0x30000 / 0x100000` | simple_system 的映射是演示性质，`shared/rtl/bus.sv:8-9` 明说"不要用于真实系统" | 定 |
| D2 | Boot ROM 基址 `0x0`，32 KB，指令+数据只读 | `boot_addr = 0`；见 `FOCUS.md` F11 | 定 |
| D3 | SRAM 基址 `0x0010_0000`，64 KB，双端口 | 与 ROM 分离；A 口给数据、B 口给取指 | 定 |
| D4 | ACC / bell 外设 `0x0020_0000` | | 定 |
| D5 | UART / SPI `0x0020_1000` | **只挂数据侧**（见 `FOCUS.md` F2） | 定 |
| D6 | Timer `0x0020_2000`，**仅数据侧** | 读有副作用；与 simple_system 的 `mtime` 方案不同，需自行实现 | 定 |
| D7 | 未映射地址（hole）返回 **err** | `shared/rtl/bus.sv:99`（`decode_err_resp <= host_sel_valid & !device_sel_valid`）与 `:125-126` 已实现 | 定 |
| D8 | 配置：`PMPEnable=1`、`PMPNumRegions=4`、`WritebackStage=0`、`ICache=0`、`SecureIbex=0`、`MHPMCounterNum=2`、`boot_addr=0x0`、`hart_id=0` | `WritebackStage=0` 让提交点保持简单；其余见 `FOCUS.md` | 定 |
| D9 | **不修改任一 `rtl/ibex_*.sv`**，只新增系统顶层与外设 | 本文 §1 第一原则 | **被 D14 取代** |
| D10 | 新增 RISC-V 配置时，在 `ibex_configs.yaml` **新增**一个命名配置（如 `tide`），不改动已有 6 个 CI 配置 | 见 `ENGINEERING.md` E2。★ **核对补充（2026-10-15）**：`ibex_configs.yaml` 共 **8 个**命名配置（`:19 small`、`:41 opentitan`、`:66 maxperf`、`:88 maxperf-pmp-bmbalanced`、`:116 maxperf-pmp`、`:139 maxperf-pmp-bmfull`、`:161 maxperf-pmp-bmfull-icache`、`:190 experimental-branch-predictor`）；**其中 6 个进入 per-config CI**（`.github/workflows/ci.yml:114/118/122/126/130/134`），另 2 个（`maxperf-pmp`、`maxperf-pmp-bmfull-icache`）不在 CI 内。**"6 个 CI 配置"的表述准确**；规则不变（只能新增，不许改动既有） | 定 |
| D11 | Boot ROM 的实现方式：**A** 复用 `ram_2p`（B 口取指 / A 口数据，写口接 0）／ **B** `lowrisc:prim_generic:rom` + 薄封装 | 原蓝图"新写单端口 `rom_1p.sv`"经核对**不可行**（取指与数据同拍会冲突）。详见 `FOCUS.md` F11 | ⏳ **待决** |
| D12 | 取指侧**必须**自行实现地址解码 + `instr_err`（simple_system 是 `instr_err='0` 硬接的，不可照抄） | `FOCUS.md` F5(b)；`examples/simple_system/rtl/ibex_simple_system.sv:133-134` | 定 |
| D13 | 每个外设必须**固定 1 拍响应**；慢外设用忙标志/中断，不拉长总线周期 | `FOCUS.md` F6；`shared/rtl/bus.sv:11-16` 的硬约束 | 定 |
| D14 | **允许新增与修改 `rtl/ibex_*.sv`**，以承载 TIDE-ISA 的 4 条新指令（`QWAIT`/`QTRIG`/`QLOAD`/`QSYNC`，编码 custom-0/custom-1）。附加**不可协商**条款：① 既有指令集（RV32IMC / CHERIoT / Zca-Zcb-Zcmp）的译码结果、异常语义、时序**逐拍不得改动**；② 全部 TIDE 逻辑必须被 `TIDE_EN` 门控，`TIDE_EN=0` 时综合与仿真行为逐拍回归上游 Ibex（不变量 I1）；③ 不新增顶层端口，阻塞复用既有 `stall_id_i` / `flush_id_o` | ISA 指令只能由译码器 + 执行单元承载，**不存在**"加外设"的替代路径；落点已冻结于 `../tide_doc/chapters/09-interface-freeze.md` §6 | **定（取代 D9）** |
| D15 | 仓库根新增 **`AGENTS.md`** 作为 AI agent / 协作者的操作约定入口：三仓关系与权威顺序、`TIDE_EN` 门控纪律、TIDE-ISA 契约摘要（编码/CSR/mcause/参数，标注权威来源）、RTL 落点与行号、构建与验证链、提交自检清单 | agent 驱动开发需要单一入口；其中事实性内容（行号/CSR 地址/参数默认值）受 §8 证据优先约束，须回 `../tide_isa` 与 `../tide_doc` 核对；**本文件不定义 ISA** | 定 |
| D16 | **`TIDE_EN` 等开关走 `.core` `parameters:`（带 `default`）+ 命令行 `--TIDE_EN=1`，不进 `ibex_configs.yaml`、不改 `util/ibex_config.py`**；命名配置 `tide` 由"必做"降级为"仅在需要固定整套参数组合时可选" | 实测 `util/ibex_config.py:23-60` 对**每个**配置做**全键强制**校验，加一个键会迫使全部 8 个配置补齐该键 → 直接违反 D10 且无法"不动既有配置"，还会让 `Makefile:7` 的 `$(shell ...)` 失败而**连带崩掉所有 make 目标**。先例 `FPGA_XILINX`（`ibex_top.core:56-60`，`default: false`、不在 yaml 中）证明该路径上游自己在走。详见 **`FOCUS.md` F14** | **定（细化 D10 的实现手段，不动 D10 的"不改既有配置"原则）** |

| D17 | QLOAD 写回从真实 DD result 端口取数；LATEST 诊断固定取完成记录 result[31:0]，不取 T_done | result 通道由 tide_rq_rsp_t 冻结；记录布局为 {result[79:48], T_done[47:0]}。stub 修复见 dv/uvm/core_ibex/tide/tide_dd_stub.sv:503 | 定 |
| D18 | TIDE 同步 enqueue 错误在 MULTI_CYCLE 中被 flush 时，ID FSM 必须回到 FIRST_CYCLE | TQ_LATE 先使 QTRIG 进入 MULTI_CYCLE，再由 controller 精确异常 flush；不复位 FSM 会导致 IbexMoveToFirstCycleWhenIdReady 失败。修复位于 rtl/ibex_id_stage.sv:1185，仅在 TIDE_EN && flush_id 生效 | 定 |

---

## 7. 本目录文件

| 文件 | 说明 |
|---|---|
| `README.md` | 本文件：工程地图 + 快速上手 + 上游文档导读 + 决策台账 |
| [`ENGINEERING.md`](./ENGINEERING.md) | 工程纪律：9 条硬规则、改动自检清单、验证分层 |
| [`FOCUS.md`](./FOCUS.md) | 关注重点：15 条陷阱，每条含现象 / 后果 / 硬规则 / 证据 |
| [`VALIDATION.md`](./VALIDATION.md) | M0–M6 可复现验证命令与结果 |
| [`M2_REPORT.md`](./M2_REPORT.md) | CD 集成视角的 M2 报告索引 |
| [`M6_REPORT.md`](./M6_REPORT.md) | 纯 RTL 导出包说明与验证 |
| `DESIGN.md` | *（待写）* 最小系统的详细设计：地址映射、模块分解、接口定义 |

---

## 8. 文档维护约定

1. **证据优先**：任何关于"这个工程怎么工作"的论断，都要写清 `文件:行号`。**没有行号的结论视为未验证。**
2. **决策要留痕**：设计改了 → 在决策台账**加一行**并注明取代了哪条，不要抹掉历史。
3. **陷阱要写"怎么验证"**：`FOCUS.md` 里每条都应能从 RTL 或仿真里复现，否则标注"待确认"。
4. **本目录不描述上游行为**：上游规格请直接引用 `doc/`，避免我们抄一份然后抄错。
5. **行号会漂移**：`FOCUS.md` 里的行号对应 HEAD `96a34a56`（勘察时锚点 `af456e25`，两者 `rtl/` 逐字节一致，故行号相同）。同步上游后若对不上，用给出的**搜索模式**重新定位，并顺手更新行号。
