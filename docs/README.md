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
- [`FOCUS.md`](./FOCUS.md) —— **关注重点**（21 条陷阱，带证据行号）
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
| D18 | TIDE 同步 enqueue 错误在 MULTI_CYCLE 中被 flush 时，ID FSM 必须回到 FIRST_CYCLE | TQ_LATE 先使 QTRIG 进入 MULTI_CYCLE，再由 controller 精确异常 flush；不复位 FSM 会导致 IbexMoveToFirstCycleWhenIdReady 失败。修复位于 rtl/ibex_id_stage.sv:1222-1227，仅在 TIDE_EN && flush_id 生效 | 定 |
| D19 | CD 侧 CSR 影子的 WARL 掩码落在**写侧单点**（tqerr_policy 掩 [10:0]、tqsink 掩 [NRQ-1:0]），**不**把 0x7C4/0x7C6 的读转发给 DD | 与 tqidx 既有做法（rtl/ibex_cs_registers.sv:1123 写掩 [7:0]、:793 读掩高位）和 DD 写侧（../tide_dd/rtl/tide_dd_top.sv:299,301）一致；读转发会拉长 CSR 读时序路径并动冻结适配器协议。规格依据 ../tide_doc/data/tide_csr_map.csv:22,24；修复前复现 ../tide_exp/build/directed_tide_csr.log:46。详见 **FOCUS.md F16** | 定 |
| D20 | QWAIT 合法性改为 **room/limit 形式**：新增 `tide_room_q = TLR_MAX − TLR` 旁路寄存器，`limit = room − imm` 与 RF 读出并行计算，RF 数据到达后仅剩 `rs1 > limit` 的 32 位无符号比较；`rs1 + imm` 扩到 33 位；`TLR_MAX` 修正为 `2⁴⁸ − 32` | 原实现把转发寄存器堆读数据直接送 49 位加法器/比较，是外部综合报告的最差路径（RF → control）。新形式与 `TLR + rs1 + imm > TLR_MAX` 精确等价，不改变 ISA 可见语义（QWAIT 仍单拍、不 stall）。原 `rs1+imm` 为 32 位，和超过 2³² 时丢进位；原 `TLR_MAX` 实为 `2⁴⁸ − 33`，与 ISA §4.1 不符。RTL 见 rtl/ibex_id_stage.sv:948-994,1058-1088、rtl/ibex_tide_pkg.sv:51-54；边界用例 ../tide_exp/firmware/tide_qwait_limit/main.c。详见 **FOCUS.md F17** | 定 |
| D21 | QTRIG 入队检查器改为**固定 2 级流水**（DD `tide_enqueue`）：T 拍采样并寄存 C2/C3/C4，T+1 拍掩码归约 + 裁决；成功裁决拍原子扇出并与 CD 退休同拍。CD 用 `tide_qtrig_wait_q`/`tide_qtrig_abort_q` 做固定一拍等待和错误撤销；C3 用 `elapsed(T) + TQ_GUARD + 1`，与实际入队点 `elapsed(T+1) + TQ_GUARD` 等价 | 外部综合报告指出 32 路 49 位比较 + 归约 + 跨域控制回环是 1 GHz 不可收敛路径。流水把比较/寄存与归约/裁决分开，QTRIG 最小退休延迟 +1 拍（正常路径 2 拍），不改变 ISA 可见语义；DD 侧 `done_q` 允许背靠背接收，错误响应电平保持至 `valid` 撤销。RTL 见 rtl/ibex_id_stage.sv:1024-1099、../tide_dd/rtl/tide_enqueue.sv:48-159；冻结更新 ../tide_doc/chapters/09-interface-freeze.md §5.1/§6.2/§10 与 ../tide_doc/data/tide_iface_signals.csv:2-3。详见 **FOCUS.md F18**；2026-11-10 由 D28 再叠加输入边界一拍（CD 可见 T+2，见 C21） | 沿用（时序见 D28） |
| D22 | enqueue 错误的同步陷阱上下文必须**跨 abort/FLUSH 拍保持**：在 `enq_tq_err` 拍寄存 `tqcause/ch`，`tide_qtrig_abort_q` 有效期间 `tide_id_trap` 输出该错误现场（`ts=tide_ts`、`target_is_queue=0`） | D21 的 abort 相位在裁决拍后撤销 `qtrig_go`，DD 随之撤回错误响应；而 controller 的 `gen_tide_trap_ctx` 在下一拍 FLUSH 才采样组合的 `tide_id_trap_i`，导致 CSR 快照落到默认 `TQ_HALTED`/`ts=0`（实测 `tide_errors` line 124 `got=0000000a exp=00000000`）。RTL 见 rtl/ibex_id_stage.sv:1196-1240、rtl/ibex_controller.sv:1205-1230、rtl/ibex_cs_registers.sv:1279-1294。详见 **FOCUS.md F19** | 定 |
| D23 | 编码非法的 TIDE 指令不得产生任何副作用：`qtrig_active`/`qload_active`/`qsync_active` 与 `qwait_commit` 全部与 `~illegal_insn_o` 相与 | 译码器在 `illegal_insn=1` 时仍输出 `tide_op_o`（rd≠0、QLOAD 越界、保留字段非 0），原实现只查本地语义（anchored/mask/room），于是越界 QLOAD 仍拉起 `stall_tide` 并触发上游 `IllegalInsnStallMustBeMemStall`（17 005 000 ps），rd≠0 的 QTRIG/QWAIT 还可能发请求/推进 TLR，违反 ISA §3.3 与 I7。寄存器堆读口无 ren（数据只由地址决定），该门控不构成组合环。RTL 见 rtl/ibex_decoder.sv:856-898、rtl/ibex_id_stage.sv:1043-1050、:1102-1104。详见 **FOCUS.md F20** | 定 |
| D24 | TIDE CSR split bus 读回改为**寄存一拍**（T1/T2）：请求载荷 `addr/wdata/tlr` 无条件跟踪当前 CSR 指令（T1）；CD 在 ID 第一拍发单拍读请求并 stall 一拍，第二拍用 DD 寄存的响应完成写回（T2） | 外部综合报告两条 1 GHz 违例路径：(a) `csr_op_en → DD 组合读 → CD 写回/DPC`；(b) `rsp.valid → mcycle 计数 ICG`。原协议要求 DD 同拍返回（ADR C15），读回锥从晚到的 CSR 完成控制出发。T1 让 DD 读回锥从早期译码/RF/TLR 寄存器出发；T2 在 DD 侧寄存响应，CSR 访问固定 +1 拍（不可见的延后，ISA 仅约束结果）。写访问仍在单拍完成（W1S 副作用在请求拍）；stall 谓词含 `~illegal_insn_o`，避免非法 SYSTEM 编码触发 `IllegalInsnStallMustBeMemStall`。`tide_dd_stub` 与 `tide_dd_tb` 同步建模 1 拍延迟。RTL 见 rtl/ibex_cs_registers.sv:1301-1333、rtl/ibex_id_stage.sv:1097-1106,1400-1407、../tide_dd/rtl/tide_csr.sv:102-113；冻结更新 ../tide_doc/chapters/09-interface-freeze.md C20 与 ../tide_doc/data/tide_iface_signals.csv:10-11。详见 **FOCUS.md F21**；2026-11-10 由 D28 再叠加输入边界一拍（CD 可见 T+2，见 C21） | 沿用（时序见 D28） |
| D25 | ~~TIDE 构建强制 **`BranchTargetALU=1`**~~（2026-11-10 由 D26 取代）：`tide_cd_top` 传 `.BranchTargetALU(TIDE_EN)`，`ibex_top` 传 `.BranchTargetALU(BranchTargetALU \| TIDE_EN)` | 2026-11-09 `syn_final.timing.rpt`：10 条 ICG 违例（−0.21 ns）的头弧是 `branch_decision → csr_op_en`；BTALU=1 使分支/跳转 `stall=0`、目标改由专用加法器产生。**2026-11-10 复测发现该配置反而使时序变差**：组合重定向锥把 `branch_decision`/目标加法器直接送入取指地址与 `csr_op_en` 反馈，成为新的最大违例源（详见 D26）。冻结更新 ../tide_doc/chapters/09-interface-freeze.md I3、../tide_doc/chapters/02-overview.md §3。详见 **FOCUS.md F22** | **已取代（2026-11-10）** |
| D26 | **A1：TIDE 构建恢复 `BranchTargetALU=0`**。`tide_cd_top` 显式传 `.BranchTargetALU(1'b0)`（rtl/tide_cd_top.sv:165-173）；`ibex_top` 不再派生 `BranchTargetALU \| TIDE_EN`，simple_system/small 配置不动 | 2026-11-09 的 BTALU=1 组合重定向把 `branch_decision` 与目标加法器直接送入取指地址、`csr_op_en` 与 ICG 反馈，复测报告反而恶化（clk 组 100 条 −0.27 ns、clock_gating 组 100 条）。BTALU=0 恢复上游**已寄存**的 `branch_set_raw_q`（rtl/ibex_id_stage.sv:865-885），切断该锥；代价是 taken branch/jump +1 拍（2 级流水语义不变，仅 WCET +1，ISA 可见结果不变）。I1 复验：TIDE_EN=0 hello_test 输出逐行一致，13268 cycles / 261 instructions。冻结更新 ../tide_doc/chapters/09-interface-freeze.md I3、../tide_doc/chapters/02-overview.md §3。详见 **FOCUS.md F22** | 定（取代 D25） |
| D27 | **A2：RV32MFast 末级乘积累加流水**。AHBL（MUL）与 AHBH（MULH/MULHSU/MULHU）把 17×17 乘积寄存到 `tide_prod_q`，下一拍（`tide_wrap_q`）用寄存乘积 + 冻结的部分和完成 34 位加法与格式拼接；乘积拍 `imd_val_q[0]` 保持。MUL/MULH 各 +1 拍（MUL 4 拍、MULH 5 拍），DIV 不变；`TIDE_EN=0` 由 generate 旁路保持上游 3/4 拍 | 复测报告最差路径从 RF 读出发经 17×17 乘法、加法与格式选择直接到 RF 写（38 条 −0.27 ns）。寄存乘积把乘法移出末拍，末拍只剩 34 位加法 + mux + RF setup。功能验证：MUL/MULH/MULHSU/MULHU 定向向量与依赖乘法链 `MUL_TEST_PASS`（457 instructions，TIDE_EN=1）。RTL：rtl/ibex_multdiv_fast.sv:273-290,350-430,445-470；rtl/ibex_ex_block.sv:155-159；rtl/ibex_core.sv:940-945 | **已取代（2026-11-10，由 D31）** |
| D28 | **A3/A3b：DD 输入提交边界 + 事件流水**。enq/rq/sync/csr 四类请求在 `tide_dd_top` 增加提交寄存器（请求拍 T 采样载荷，T+1 起驱动内部 FSM；成功裁决后一拍气泡），事件侧增加 `tide_evt_pipe` 隔离错误计数/现场/trap 快照。CD 侧 QTRIG 改两级等待（`tide_qtrig_wait_q`/`tide_qtrig_rsp_rdy_q`），CSR 读改两拍等待（`stall_tide_csr` + `tide_csr_hold_q`） | 复测报告把 `CD 同拍控制 → DD 组合逻辑 → 裁决/回环` 列为 ICG 与 clk 组的主要违例来源（56 条 DD 相关路径）。边界只加延迟不改语义：QTRIG 相对 CD 请求拍 T 的裁决为 T+2，QLOAD 响应 T+1，QSYNC anchor 后移一拍，CSR 读 T+2；C3 以边界后采样拍的 `elapsed` 为基准（`guard_limit = elapsed + TQ_GUARD + 1`）。DD 定向/随机（seed 1/7）与 CD-DD 联合 UVM 复验通过。RTL：../tide_dd/rtl/tide_dd_top.sv:178-257,259-275；../tide_dd/rtl/tide_enqueue.sv:48-80,97-111；rtl/ibex_id_stage.sv:1089-1160,1395-1450。冻结：../tide_doc/chapters/09-interface-freeze.md §5.1/§5.2、ADR C21、../tide_doc/data/tide_iface_signals.csv | 定 |
| D29 | **B1：IF 段 TIDE 预译码随指令寄存进 ID**。`tide_op/pi/imm12/rq_idx/enc_illegal` 在 IF 组合预译码并与指令一起写入 IF-ID 寄存器，ID 不再从 `instr_rdata_id` 重新译码 TIDE 字段 | 复测报告 8 条 IF/ID 握手 ICG 违例的头弧来自 ID 侧对 32 位指令的 TIDE 译码进入 `stall_tide`/`csr_op_en`。预译码把该锥冻结在 IF-ID 寄存器之前，ID 消费寄存后的窄字段。逐拍语义由 UVM 与 `tide_exp` 定向回归复验。RTL：rtl/ibex_if_stage.sv:580-634,657-671,686-728；rtl/ibex_core.sv:244-249,633-641,915-923 | 定 |
| D30 | **B2：`csr_op_en` 完成使能去 TIDE 等待项**。`csr_instr_done = ~(stall_ld_hz \| stall_mem) & ~flush_id & instr_executing`（去掉 `stall_tide_csr`），切断 `branch_decision/flush → csr_op_en → CSR 写使能/ICG` 锥 | 与计划的“计数写使能寄存”**偏差**：TIDE DD-managed RO CSR 的合法访问译码为纯读（`CSR_OP_READ`、`csr_wr=0`），第二拍 `csr_op_en` 脉冲下 `csr_we_int` 与 `csr_pipe_flush` 恒为 0；0xFCx 写尝试经 `illegal_csr_write` 精确异常且 `tide_csr_wait_dec` 被 `~illegal_insn_o` 门控，无副作用。CSR 读数据仍取 split-bus 寄存响应。RTL：rtl/ibex_id_stage.sv:834-841,1141-1144；rtl/ibex_cs_registers.sv（`tide_csr_fwd_write`/`illegal_csr_write`）。详见 **FOCUS.md F24** | 定（实现方式偏差，已复验） |
| D31 | **乘法全寄存**（取代 D27，A2 第二阶）：TIDE 构建在 RV32MFast 增加 `MD_LATCH`（idle 拍寄存 `op_a/op_b/signed_mode/operator`，共 69 个 flop）与 `MD_DONE`（呈现 `imd_val_q[0]`）；AHBL/AHBH 末拍只把格式化结果写入 `imd_val_q[0]` 并转 `MD_DONE`；`multdiv_result_o` 在 TIDE 构建恒取 `imd_val_q_i[0][31:0]`（`div_sel_i \| TIDE_EN`），组合乘法器不再驱动 RF 写口。MUL 3→5、MULH 类 4→6（各 +2；比 D27 再多 1 拍），DIV 不变；`TIDE_EN=0` 逐拍保持上游 3/4 拍 | 2026-11-10 复测报告：clk 组 100/100 条违例（−0.17 ns）中 99 条穿过 `gen_multdiv_fast_multdiv_i`，起点为 IF-ID 指令寄存器、终点为 RF 写寄存器；扣除用户已确认不动的 U1（0.22 ns uncertainty / `ssg0p81vm40c`）后仅 +0.05 ns，是本设计唯一净余量不足 0.1 ns 的锥（其余违例净余量 ≥ +0.07 ns）。D27 只寄存末级乘积，`multdiv_result_o` 的 `mac_res_d` 支路与 `imd_val_d_o[0]` 仍由组合乘法器驱动。全寄存后 RF 写口只看见 `imd_val_q[0]`（flop → ex/id/wb mux → RF），乘法锥止于 `imd_val_q[0]` 的 D 端：按报告分段估算 arrival ≈ 0.63 ns vs 1 GHz 的 required 0.76 ns，约 +0.12 ns 余量（预测值，待用户综合复测）。功能验证：MUL/MULH/MULHSU/MULHU 定向向量与 32/16 深依赖链 `MUL_TEST_PASS`（457 instructions；1196 cycles vs D27 的 1116，差 80 = 80 次乘法 × +1 拍）。RTL：rtl/ibex_multdiv_fast.sv:144-149,275-302,309-339,369-418,420-444,446-473；rtl/ibex_ex_block.sv:157-159。详见 **FOCUS.md F26** | 定（取代 D27） |
| D32 | **乘法操作数/累加器提前一拍寄存**（细化 D31，拍数不变）：TIDE 构建在乘法器入口增加 68 个 flop（`tide_mul_a_q/tide_mul_b_q/tide_sign_a_q/tide_sign_b_q/tide_accum_q`），由 `mult_state_d`（下一拍状态）选择 `mul_a/mul_b/mul_signed_mode/mul_operator/mac_res_d`；ALBL 的输入在 `MD_LATCH` 拍直接取 `op_a_i/op_b_i[15:0]`。乘法器与 34 位累加器从 flop 出发，FSM 状态译码不再进入乘法锥。MUL 5 拍 / MULH 类 6 拍与 D31 相同（周期数不变），DIV 不变；`TIDE_EN=0` 保留上游组合操作数 mux | 2026-11-11 复测报告：`clk` 组中 TIDE 自有最差路径为 `gen_mult_fast_mult_state_q_reg_2_ → id_stage_i/imd_val_q_reg_0__{17..33}_`（15 条），arrival 0.89 / required 0.74 / slack −0.14；扣除 U1 后 +0.08。路径分段：状态译码 0.08→0.22、操作数 mux →0.22、乘法+累加链 0.31→0.86、ID mux →0.89；D31 已让操作数来自 `MD_LATCH` 寄存器，但 FSM 状态仍以 4 级译码驱动操作数/符号/累加 mux，把 0.14 ns 带进乘法锥。按分段估算新 arrival ≈ 0.75（乘法器从 flop 出发，状态译码与 mux 移出），报告 slack ≈ 0.00（预测值；扣除 U1 后 ≈ +0.22），待用户综合复测。功能验证：`MUL_TEST_PASS`（457 instructions，1196 cycles，与 D31 一致）；`TIDE_EN=0` hello_test 13268/261 逐行一致；UVM 98 instructions / 0 error。RTL：rtl/ibex_multdiv_fast.sv:319-412。详见 **FOCUS.md F27** | 定（细化 D31，拍数不变） |
| D33 | **时序收口 Stage 6（P0/P1/P2/P3/P4a/P4b）**：① **P0** TIDE 构建条件分支固定两拍：`stall_branch = TIDE_EN \| ...`、`id_fsm_d = MULTI_CYCLE`（rtl/ibex_id_stage.sv:1467-1472），分支目标改由 `ibex_ex_block` 的 TIDE 专用 33 位加法器产生（rtl/ibex_ex_block.sv:97-106），`branch_decision` 不再进入第一拍 `stall_id`/`id_in_ready` 锥；代价是未跳转条件分支 +1 拍（taken/not-taken 均固定 2 拍）。② **P1** `tide_tq` commit 输出寄存一拍（`commit_valid_q/commit_ts_q/commit_code_q`，../tide_dd/rtl/tide_tq.sv:45-67）：队列状态仍在 `ts==elapsed` 拍推进，码字交付固定延后 1 tick；DD 断言改比 `elapsed_q`（../tide_dd/rtl/tide_dd_top.sv:429-446）。③ **P2** SPI 把 `DIV−1` 寄存为 `div_term_q`，计数器比较改 `div_cnt_q >= div_term_q`，组合减法移出 ICG 使能锥（../tide_mmio/rtl/tide_spi.sv:142,155）。④ **P3** `tide_dd_top` 增加 TQ 本地异步置位/同步释放复位同步器（2 拍，../tide_dd/rtl/tide_dd_top.sv:171-189），全局复位释放锥不再进入 TQ 时钟门控。⑤ **P4a/P4b** 乘法累加器 `tide_accum_q` 与除法商 `op_quotient_q` 改为无使能 always_ff + 纯数据次态（rtl/ibex_multdiv_fast.sv:112-133,360-430,616-617）：报告违例终点是 ICG EN（ECE 的 D≠Q 比较），去掉寄存器使能即去掉 ICG 与 ECE 锥；相对批准的“加一级寄存器 / +1 拍”偏差为 **0 额外拍**，MUL 5 / MULH 类 6 / DIV 拍数不变 | 2026-11-11 报告（303 条路径：`clk` 100 违例、`clock_gating_default` 92 违例）中：最差 gating 路径为 `instr_rdata_id_reg_19 → decoder/RF/ALU/branch_decision → id_in_ready → compressed decoder → fetch FIFO ICG`（−0.14，外部建议 §2.3）；TQ 为 `head_q → 外部 DAQ ICG` 24 条（最差 −0.09，外部建议 §1）；SPI 为 `div_q_reg_1_ → clk_gate_div_cnt_q_reg_9_`（−0.09，外部建议 §4）；复位释放到 TQ 门控（−0.06，外部建议 §3）；TIDE 自有 ICG 终点 `tide_accum_q`（−0.11）与 `op_quotient_q`（−0.08）。P4 原计划“加寄存器/加拍”，但报告显示这两条路径的 flop D 端已 MET，违例在 ICG EN 的 ECE 条件上；改为恒写纯数据次态可同时消除 ICG 与 ECE，且拍数不变（D 端路径仍从 flop 出发）。验证：`MUL_TEST_PASS` 457 instr / 1203 cycles（+7 全部来自 P0 的未跳转分支 +1 拍）、`DIV_TEST_PASS` 315188 cycles、TIDE_EN=0 hello 13268/261 逐行一致、UVM `tide_qop_smoke` 98 instructions / 0 error、`tide_dd` 定向 + 随机 seed 1/7、`tide_exp` directed 15/15 + mcu-lint/elab/top、`tide_mmio` lint 0 warning + `TIDE_MMIO_TEST_PASS`。详见 **FOCUS.md F28/F29** 与 `docs/VALIDATION.md` 2026-11-11 Stage 6 | 定 |
| D34 | **`csr_op_en` 在 `WritebackStage=1` 时恢复 `ready_wb_i` 门控**（修正 D30）：`csr_op_en_o = csr_access_o & instr_executing & (CHERIoT ? instr_first_cycle : (csr_instr_done & (WritebackStage ? ready_wb_i : 1'b1)))` | D30 用 `csr_instr_done` 替换上游 `instr_id_done_o` 时漏掉了 `instr_id_done_o = en_wb_o & ready_wb_i` 里的 `ready_wb_i`。`stall_wb` 不在 `stall_id` 内，WB 忙时 `csr_instr_done` 仍为 1，`csr_op_en_o` 会跨多拍重复脉冲（重复 CSR 写/`csr_pipe_flush`）。TIDE 构建（`small`，`WritebackStage=0`）下 `ready_wb_i` 恒 1，行为与 D30 一致且不把 `ready_wb_i` 引入 TIDE 构建的 `csr_op_en` 锥；其余 `WritebackStage=1` 配置恢复上游逐拍等价。验证：Verilator/Verible lint `lowrisc:ibex:ibex_top_tracing` 的 `small` 与 `opentitan`（WB=1、SecureIbex=1、CHERIoT BaseIsa）均 RC=0；simple system `hello_test`（TIDE_EN=0）执行 13268 cycles / 261 instructions，与 D26/D33 基线逐字一致。RTL：rtl/ibex_id_stage.sv:853-866 | 定（修正 D30） |
| D35 | **TIDE 乘法结果 mux 限定 `RV32MFast`**（修正 D31/D32 的适用域）：`multdiv_result_o = (div_sel_i \| (TIDE_EN && (RV32M == RV32MFast))) ? imd_val_q_i[0][31:0] : mac_res_d[31:0]` | D31/D32 的 `MD_LATCH`/`MD_DONE` 只在 `gen_mult_fast`（`RV32MFast`）内存在；裸 `TIDE_EN` 会让 `TIDE_EN=1` + `RV32MSingleCycle`（`opentitan` 的 `RV32M`）从要到该拍结束才更新的 `imd_val_q[0]` 取乘法结果，而单周期乘法器的 `mult_valid` 仍在 `mac_res_d` 有效的同一拍拉高 → 读到陈旧值。修正后 `TIDE_EN=0` 与 `TIDE_EN=1`+`RV32MFast` 行为不变，其余乘法器恢复上游组合结果路径。验证：Verilator/Verible lint `ibex_simple_system`（`TIDE_EN_SYS=1`，RV32MFast）与 `lowrisc:ibex:ibex_top_tracing` 的 `small`/`opentitan` 均 RC=0。RTL：rtl/ibex_multdiv_fast.sv:155-163 | 定（修正 D31/D32 适用域） |

---

## 7. 本目录文件

| 文件 | 说明 |
|---|---|
| `README.md` | 本文件：工程地图 + 快速上手 + 上游文档导读 + 决策台账 |
| [`ENGINEERING.md`](./ENGINEERING.md) | 工程纪律：9 条硬规则、改动自检清单、验证分层 |
| [`FOCUS.md`](./FOCUS.md) | 关注重点：21 条陷阱，每条含现象 / 后果 / 硬规则 / 证据 |
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
