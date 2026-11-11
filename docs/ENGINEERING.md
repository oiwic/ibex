# 工程纪律

本文是**硬规则**，不是建议。每条格式统一：

> **规则** → **为什么** → **怎么做** → **违反的症状**

改任何 RTL 之前，先读 [`FOCUS.md`](./FOCUS.md)；提交之前，先过 §9 的自检清单。

> **跨层工程纪律**（三层同步推进、改动分级、穿透审阅、通用纪律：证据优先/决策留痕/不抄上游/行号漂移/代码编辑走 Linux 容器 `synopsys`）的**权威条款在顶层 `../../AGENTS.md` §7**；本文件只保留 CD 仓特有的可执行规则（E1–E9）。

**这些规则全部来自仓库里可验证的证据**（CI 配置、脚本、上游文档），不是我的偏好。
凡是我自己加的工程建议，都标注 **[建议]**。

---

## E1 文件清单纪律（最容易踩、后果最直接）

> **规则**：新增 / 删除 / 重命名任一 SystemVerilog 文件，必须**同步更新文件清单**，否则构建器看不到它。

### 为什么

这个仓库**没有**"扫描目录自动收集文件"的机制。文件清单是**手写**的，而且有两套：

| 清单 | 谁在用 | 位置 | 可信度 |
|---|---|---|---|
| **FuseSoC `.core`** | 仿真（Verilator/VCS）、lint、综合、DV —— **唯一权威** | 根目录 `*.core`、`examples/**/*.core`、`shared/*.core`、`dv/**/*.core` | ★ **可信** |
| **`src_files.yml`** | 给**不使用 FuseSoC** 的流程 | 根目录 `src_files.yml` | ⚠️ **已失效，不要信** |

> ★★ **实测结论：`src_files.yml` 是过期的，不要照着它改。**
> 逐条核对它的 25 个 `.sv` 条目，**3 个指向根本不存在的文件**：
>
> | 条目 | 是否存在 |
> |---|---|
> | `rtl/ibex_counters.sv` | ❌ 不存在 |
> | `shared/rtl/prim_assert.sv` | ❌ 不存在（真正的在 `vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv`） |
> | `rtl/ibex_core_tracing.sv` | ❌ 不存在（真实名字是 `rtl/ibex_top_tracing.sv`） |
>
> 而且它**遗漏了**实际存在的 `rtl/ibex_cheriot_ex.sv`、`rtl/ibex_csr.sv`、`rtl/ibex_counter.sv`、
> `rtl/ibex_branch_predict.sv`、`rtl/ibex_dummy_instr.sv`。
> → **以 `.core` 为准；`src_files.yml` 只在别人明确要求时才动，不要把它当作对账依据。**

### 怎么做

以我们最会碰的两处为例：

**① 给 Simple System 加新的系统 RTL 文件** → 改 `examples/simple_system/ibex_simple_system_core.core`：

```yaml
  files_sim:
    depend:
      - lowrisc:ibex:ibex_top_tracing
      - lowrisc:ibex:sim_shared
    files:
      - rtl/ibex_simple_system.sv
      - rtl/<你的新文件>.sv        # ← 加在这里
    file_type: systemVerilogSource
```

**② 给核心加文件** → 改 `ibex_core.core` 的 `files_rtl.files`（当前含 **21 个文件，见 `ibex_core.core:19-39`**）。
⚠️ `src_files.yml` 虽然也列了核心文件，但**它是过期清单**（见上）——**别把它当对账依据**。
如果一定要动它，先逐个 `Test-Path` 确认原有条目是否还有效。

**③ 新增一个 `.core`（新目标/新配置）** → 注意 `parameters:` 与 `targets.<t>.parameters` 是**两处**，
参数必须在两处都列出才会真正传到顶层（参考 `examples/simple_system/ibex_simple_system.core`）。

### 违反的症状

- Verilator/VCS：`Cannot find file`、`module '<X>' not found`
- 更阴险的：**lint 目标静默地只编了旧文件**，你以为过了，其实新文件没被检查
- DV 流程跑的是旧 RTL，回归通过但和你的修改无关

### 一个真能用的 30 秒自查

**Windows / PowerShell**（我们的日常环境）——把某个 `.core` 里列的文件与磁盘对账：

```powershell
# 把 <core> 换成目标 .core 的路径，例如 ibex_core.core 或 examples/simple_system/ibex_simple_system_core.core
$core = 'examples/simple_system/ibex_simple_system_core.core'
$dir  = Split-Path $core
Select-String -Path $core -Pattern '^\s*-\s+(\S+\.sv)' -AllMatches |
  ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
  Sort-Object -Unique |
  ForEach-Object { '{0,-45} {1}' -f $_, (Test-Path (Join-Path $dir $_)) }
```

任何 `False` 就是问题：要么文件被删了但清单没更新，要么路径写错了。

**Linux / bash**：

```bash
core=examples/simple_system/ibex_simple_system_core.core
grep -oP '^\s*-\s+\K\S+\.sv' "$core" | sort -u |
  while read -r f; do printf '%-45s %s\n' "$f" "$([ -f "$(dirname "$core")/$f" ] && echo OK || echo MISSING)"; done
```

**还要检查反向**（磁盘上有但清单里没有的新文件）：

```powershell
git status --short          # 新文件必须是 untracked(??) 或 added(A) 状态
```

⚠️ 注意：**不要**用同样的脚本去对账 `src_files.yml` —— 它本身就是坏的（见上），`False` 是预期结果。

---

## E2 配置矩阵纪律

> **规则 A**：改动 RTL 后，**必须保证所有已有的命名配置仍然能构建**——至少是 `small`。
> **规则 B**：新增顶层参数时，**6 个 CI 配置都要能处理它**。
> **规则 C**：我们要试的新参数组合，**新增一个命名配置**（如 `tide`），**不要**改已有的。

### 为什么

`ibex_configs.yaml` 开头（第 5-6 行）明文写着：

> `# Ibex named configurations, each configuration must specify the same set of parameters.`

也就是说：**每个配置必须给全同一套参数**。加一个参数却只在部分配置里给，会让 `util/ibex_config.py` 出错。

而 CI（`.github/workflows/ci.yml`）会**逐个**跑这 6 个配置的完整 RTL CI（lint + compliance + cosim）：

| 配置 | 关键特性 |
|---|---|
| `small` | RV32IMC，2 级流水，3 周期乘法，**PMP/ICache/SecureIbex 全关** |
| `opentitan` | RV32IMCB，3 级流水，ICache+ECC+Scramble，SecureIbex，16 PMP |
| `maxperf` | 单周期乘法、分支目标 ALU、写回级 |
| `maxperf-pmp-bmbalanced` | 上者 + PMP + balanced bitmanip |
| `maxperf-pmp-bmfull` | 上者 + full bitmanip |
| `experimental-branch-predictor` | 静态分支预测（**实验性**） |

★ 注意 `experimental-branch-predictor` 在上游被归为"**实验性、未充分验证**"。
**[建议]** 我们不要在它上面构建任何东西。

### 怎么做

```bash
# 看某个配置展开成什么参数
./util/ibex_config.py small fusesoc_opts
# 输出示例（opentitan）：
# --RV32E=0 --RV32M=ibex_pkg::RV32MSingleCycle --RV32B=ibex_pkg::RV32BFull --RegFile=ibex_pkg::RegFileFF
# --BranchTargetALU=1 --WritebackStage=1 --ICache=1 --ICacheECC=1 --ICacheScramble=1 --BranchPredictor=0
# --DbgTriggerEn=1 --SecureIbex=1 --PMPEnable=1 --PMPGranularity=0 --PMPNumRegions=16
# --MHPMCounterNum=10 --MHPMCounterWidth=32

# 改动后至少验证 small 能编
fusesoc --cores-root=. run --target=sim --setup --build \
        lowrisc:ibex:ibex_simple_system $(./util/ibex_config.py small fusesoc_opts)
```

**[建议]** 加一个 `tide` 命名配置，把我们 D8 那套参数固化下来，以后所有构建都用
`./util/ibex_config.py tide fusesoc_opts`，而不是手敲一串 `--XXX=`。

### 违反的症状

- CI 上某个你没在意的配置挂掉（比如 `opentitan` 因为 `SecureIbex=1` 走了另一条代码路径）
- `ibex_config.py` 报参数缺失
- "我本地过了" —— 因为你只跑了一个配置

---

## E3 代码风格与 lint 纪律

> **规则 A**：新 RTL 必须**能过 Verilator lint（`-Wall`）和 Verible lint**。
> **规则 B**：要豁免，就写进 waiver 文件并说明理由；**绝不为了过 lint 去改坏 RTL 语义**。
> **规则 C**：C/C++ 改动提交前跑 `clang-format`。

### 为什么

CI 里这两道是**硬门禁**（`exit 1`），不是警告：

- `.github/workflows/pr_lint.yml` —— Verible lint + reviewdog，配置取自
  `vendor/lowrisc_ip/lint/tools/veriblelint/lowrisc-styleguide.rules.verible_lint`，豁免文件 `lint/verible_waiver.vbw`
- `.github/actions/ibex-rtl-ci-steps/action.yml:22-42` —— 对**每个配置**跑
  `--target=lint --tool=verilator` 和 `--tool=veriblelint`
- `.github/workflows/ci.yml` —— 对 Simple System 跑 Verilator/Verible lint
- `.github/workflows/ci.yml` 里对 PR 的 C/C++ 变更跑 `clang-format-diff`，**有 diff 就 `exit 1`**
- Verible **format** 那步是 `continue-on-error: true`（实验性，失败可忽略）；**lint 不是**，必须过

### 怎么做

```bash
# 本地复现 CI 的 lint（必须两个都跑）
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# C/C++
clang-format -i examples/simple_system/ibex_simple_system_main.cc
```

### Waiver 放在哪

| 文件 | 范围 |
|---|---|
| `lint/verilator_waiver.vlt` | 全局 Verilator |
| `lint/verible_waiver.vbw` | 全局 Verible |
| `examples/simple_system/lint/verilator_waiver.vlt` | 仅 Simple System |
| `examples/simple_system/lint/verible_waiver.vbw` | 仅 Simple System |

★ 注意 `ibex_simple_system_core.core:24,28` —— **waiver 文件本身就是靠 `.core` 清单被加载的**。
如果你新建一个 example 目录，别忘了把它的 waiver 挂进对应的 `.core`。

### 风格参考

- SystemVerilog：lowRISC Verilog Coding Style（`README.md:85-86` 指向 `https://github.com/lowRISC/style-guides`）
- C/C++：OpenTitan C++ style guide（`README.md:88-89`）
- 现有代码的**实际写法**就是最好的样板 —— 尤其是断言（见 E5）、参数表格式、`localparam` 命名

### 违反的症状

- PR 上 reviewdog 刷一堆 comment，CI 红灯
- 为了消 lint 把 `unused_*` 变量直接删掉 → 破坏了 `ram_2p.sv:44-45` 那种"故意标记未使用"的意图

---

## E4 提交与历史纪律

> **规则**：标题 ≤50 字符、祈使句、现在时、大写开头、不加句号；正文 72 列换行；
> **`git commit --signoff`**；用 `[子系统]` 前缀；**保持线性历史（rebase，不 merge）**。

### 为什么

`CONTRIBUTING.md` 逐条写明了这些；`ci/lint-commits.sh` 在 CI 上**机器校验**
（调用 `util/lint_commits.py --no-merges`），注释里明确：

> `# * Merge commits are not checked. We always use rebases instead of merges to keep a linear history,`

### 仓库实际用法

从 `git log` 看，上游统一用 `[子系统]` 前缀（以下为 2026-10-15 自 `lowrisc/ibex` 同步后的历史摘录）：

```
96a34a56 [doc] Fix the icache data ECC layout
af456e25 [dv] Add zcmp_reserved_test
a3ab21a8 [rtl] Keep a reserved Zcmp rlist trap unexpanded
e1a6be2c [rtl] Switch to ratified bitmanip extensions
e9f55342 [doc] Add CHERIoT parameter conflicts and assert those
405c6d1d [nix] Update nixpkgs and gomod2nix
```

**[建议]** 我们沿用 `[rtl]` / `[dv]` / `[doc]`，项目特有内容加 `[tide]`。例如：

```
[tide] Add boot ROM and custom address map

Introduce a 32 KiB read-only boot ROM at 0x0 and remap SRAM to
0x00100000. Unmapped accesses now return bus errors instead of
aliasing into RAM.

Signed-off-by: ...
```

### 怎么做

```bash
git commit --signoff            # 自动加 Signed-off-by
git rebase -i origin/master     # 修正历史，不要 merge
```

### 违反的症状

- CI 的 `Commit metadata` 步失败（`ci.yml` 里 `./ci/lint-commits.sh "$GITHUB_BASE_REF"`）
- 上线后 rebase 上游时满屏冲突

---

## E5 断言纪律

> **规则 A**：断言统一用 `shared/rtl/prim_assert.sv` 的宏（`` `ASSERT ``、`` `ASSERT_KNOWN ``、`` `ASSERT_IF ``），
> **不要**在 RTL 里写裸 `assert property`。
> **规则 B**：新模块要对自己的输入做 known / 稳定性断言。

### 为什么

- `ibex_core.core:11-12` 把 `lowrisc:prim:assert` 和 `lowrisc:prim:clock_gating` 列为依赖
- ★ 注意：`shared/rtl/*.sv` 里的 `` `include "prim_assert.sv" ``（如 `ram_1p.sv:9`、`ram_2p.sv:13`）
  **靠的是 `.core` 依赖提供的 include 路径** —— 文件本身在 `vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv`，
  由 `vendor/lowrisc_ip/ip/prim/prim_assert.core`（`name: "lowrisc:prim:assert:0.1"`）提供。
  → 所以**新模块只要用了这些宏，就必须确保它所属的 `.core` 依赖了 `lowrisc:prim:assert`**，
  否则报 `Cannot find include file "prim_assert.sv"`。
- 上游对**每一个** `ibex_top` 端口都加了 `ASSERT_KNOWN`（提交 `90331a69 [rtl] Add ASSERT_KNOWN to all ibex_top ports`）
- 断言和 RTL 是**同一份代码**，不是事后补的 —— 这是这个仓库能到 V2S 的原因之一

### 现成的、值得照抄的例子

`rtl/ibex_if_stage.sv` 末尾有两条例外值钱的断言：

```systemverilog
// rtl/ibex_if_stage.sv:931-932
// Boot address must be aligned to 256 bytes.
`ASSERT(IbexBootAddrUnaligned, boot_addr_i[7:0] == 8'h00)

// rtl/ibex_if_stage.sv:937-938
// Address must be word aligned when request is sent.
`ASSERT(IbexInstrAddrUnaligned, instr_req_o |-> (instr_addr_o[1:0] == 2'b00))
```

这两条直接告诉我们**我们把核接成什么样才算合法**（见 `FOCUS.md` F9）。

### 违反的症状

- 仿真里断言不跑（Verilator 需要 `--assert`，见 `ibex_top.core` 的 lint/sim 配置）
- 用裸 `assert` 导致某些工具编不过

---

## E6 验证分层纪律

> **规则**：改动 RTL 后，**按代价从低到高依次过**；至少过到第 4 层（Simple System 能跑起来）。
> **不要**跳过 lint 直接跑长回归——那是浪费时间。

| # | 关卡 | 代价 | 命令 |
|---|---|---|---|
| 1 | Verilator lint | 秒 | `fusesoc --cores-root . run --target=lint --tool=verilator lowrisc:ibex:ibex_simple_system` |
| 2 | Verible lint | 秒 | `fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system` |
| 3 | CSR testbench | 秒 | `make build-csr-test && make run-csr-test` |
| 4 | Simple System + hello_test | 分钟 | `make run-simple-system` |
| 5 | RISC-V compliance | 分钟 | CI 跑 `rv32i rv32im rv32imc rv32Zicsr rv32Zifencei`（见 `action.yml:62`） |
| 6 | Spike 协同仿真 | 分钟 | `ci/run-cosim-test.sh CoreMark examples/sw/benchmarks/coremark/coremark.elf` |
| 7 | UVM 主回归（riscv-dv） | 小时 | `cd dv/uvm/core_ibex && make` |
| 8 | 形式化 | 小时 | 见 `formal/` 与 `.github/workflows/ci-formal.yml` |

### 分工（CI 里实际是怎么跑的）

- **compliance**：`action.yml:44-79`。注意里面有个**已知失败的白名单**：
  `rv32i` 期望 `FAIL: 4/48`（对应上游 issue #100）。你如果看到 `rv32i` 失败数**不是** 4/48，那才是新问题。
- **cosim**：`action.yml:81-102`。★ 它是**按配置条件执行**的：
  ```bash
  if ./util/ibex_config.py <cfg> query_fields PMPEnable | grep -q 'PMPEnable=1'; then
    ./ci/run-cosim-test.sh --skip-pass-check pmp_smoke .../pmp_smoke_test.elf
  fi
  ```
  → 也就是说 **`pmp_smoke_test` 只在 `PMPEnable=1` 的配置上跑**。我们的 D8 开了 PMP，所以这个测试对我们是**有效的门禁**。
  同理 `dit_test` / `dummy_instr_test` 只在 `SecureIbex=1` 时跑。
- **主回归**：`dv/uvm/core_ibex`，riscv-dv 生成随机指令 + UVM + 与 Spike 比对 trace（`doc/03_reference/verification.rst:16-20`）。
  支持 `TEST=` / `ITERATIONS=` / `SEED=` / `WAVES=` / `COV=1` / `SIMULATOR=`。

### 计分板：谁在什么时候有效

| 我们关心的东西 | 哪个关卡真的能发现它 |
|---|---|
| 语法/位宽/latch 推断 | 1、2 |
| CSR 语义、PMP 配置位、粘滞位顺序 | 3、7 |
| 系统集成（地址映射、外设握手、err 通路） | 4、5、6 |
| 异常/中断的精确性 | 7 |
| `fence.i` / 自修改代码 | 7（cosim 会比对指令流） |
| 时序/面积 | `syn/`（另有独立流程，不进 CI 门禁） |

**[建议]** 我们的定制系统**不在** `dv/uvm/core_ibex` 的默认覆盖范围内（那个 TB 有自己的内存模型，
不实例化 `ibex_simple_system`）。所以对我们最有价值的日常关卡是 **4**（Simple System）与 **6**（cosim）。
**[建议]** 给我们的系统写一个像 `pmp_smoke_test` 那样的小 directed test，并挂进 cosim 流程 —— 这是性价比最高的一步。

### 上游的验证成熟度（别高估）

`doc/03_reference/verification.rst:24` 明确：只有 **`opentitan` 配置**达到 **V2S**
（覆盖率 >90%、回归通过率 >90%，但**尚未 closed**）。
README 的配置表里 **`small` 是 `Red`（最小/无可信验证）**。
→ **[建议]** 我们选了 `small` 风格的参数，要**明确知道自己在验证上是"裸奔"的**，必须靠自己的 directed test 兜底。

---

## E7 上游资产只读纪律

> **规则 A**：`vendor/`（3148 个文件，vendored OpenTitan prims）**只读**。
> **规则 B**：`rtl/ibex_*.sv` 尽量不改（D9）。
> **规则 C**：需要改/新增公共 IP，放 `shared/rtl/`；需要改系统，新建我们自己的顶层。

### 为什么

- `README.md:19-20`：Ibex 由低RISC维护、**活跃开发中**。改核心 RTL = 持续背冲突
- `doc/02_user/getting_started.rst:8-11` 明确说：这些 prims 是从 OpenTitan vendored 过来的，
  "You may wish to replace these primitives with your own" —— **即允许替换，但要走我们自己的文件**
- `shared/` 里已经放了简化版 IP（**已逐一核对，共 6 个 `.sv`**）：
  `rtl/bus.sv`、`rtl/ram_1p.sv`、`rtl/ram_2p.sv`、`rtl/timer.sv`、
  `rtl/sim/simulator_ctrl.sv`、`rtl/fpga/xilinx/clkgen_xil7series.sv`
  → **我们的新 IP 就放 `shared/rtl/`，跟它们做邻居**
- ★ **`shared/` 里没有任何 `prim_*` 文件。** 所有 primitives（`prim_assert`、`prim_clock_gating`、
  `prim_ram_1p/2p`、`prim_lfsr`、`prim_secded*`…）都在 `vendor/lowrisc_ip/ip/prim/`。
  → 我们**不要**在 `shared/` 里复制一份 prim —— 直接依赖对应的 `lowrisc:prim:*` core。

### ★ 一个必须写下来的警告

`shared/rtl/bus.sv:8-9` 的模块头注释原文：

```
 * This module is designed for demo and simulation purposes, do not use it in
 * a real-world system.
```

它还有一条硬约束（`bus.sv:14`）：

```
 * - All devices (slaves) must respond in the next cycle after the request.
```

→ **如果我们打算把这个系统做成真实硬件，`shared/rtl/bus.sv` 必须替换。**
**[建议]** 现在就用它（省时间），但在 `DESIGN.md` 里显式记一条"待替换"的技术债。

### ★ `lowrisc:prim:*` 是**工艺无关的抽象名**，别按名字猜文件路径

`.core` 里写的 `lowrisc:prim:xxx` 是**抽象 core 名**，实际实现按目标工艺由
`prim_generic`（通用/ASIC）或 `prim_xilinx`（Xilinx FPGA）提供：

| 抽象名（`.core` 里写的） | generic 实现 | xilinx 实现 |
|---|---|---|
| `lowrisc:prim:clock_gating` | `lowrisc:prim_generic:clock_gating` | `lowrisc:prim_xilinx:clock_gating` |
| `lowrisc:prim:ram_1p` | `lowrisc:prim_generic:ram_1p` | `lowrisc:prim_xilinx:ram_1p` |
| `lowrisc:prim:ram_2p` | `lowrisc:prim_generic:ram_2p` | （无） |
| （无抽象名） | `lowrisc:prim_generic:rom` | `lowrisc:prim_xilinx:rom` |

具体文件示例：

- `vendor/lowrisc_ip/ip/prim_generic/rtl/prim_clock_gating.sv`
- `vendor/lowrisc_ip/ip/prim_xilinx/rtl/prim_clock_gating.sv`
- `vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_1p.sv`
- `vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv`（这个是**工艺无关**的，直接在 `prim/` 下）

**规则**：

1. **不要在 RTL 里直接按路径 include `prim_*` 之外的东西**，也不要假设某个工艺实现存在。
2. 我们自己的 RTL 用 `lowrisc:prim:*` 抽象名（照抄 `ibex_core.core:11-12`、`shared/sim_shared.core:10-12` 的写法）。
3. `ibex_core.core` 还有个 `FPGA_XILINX` 参数（`ibex_core.core:59-63`，`paramtype: vlogdefine`）
   —— 说明**同一个 RTL 会被不同目标编译**。我们加的参数要遵守 E2 的配置纪律。
4. ⚠️ 抽象名 → 具体实现的**解析机制细节本文未深挖**（不在本次范围）。如果哪天出现
   "找不到 core `lowrisc:prim:xxx`"，那是构建配置问题，不是 RTL 问题 —— 去查 `vendor/` 下的 `*.core`。

---

## E8 文档纪律

> **规则 A**：上游文档改动遵循 rst 规范，新页面**必须在 `index.rst` 的 `toctree` 里注册**。
> **规则 B**：我们的项目文档用 Markdown 放 `docs/`（本目录），**不往 `doc/` 里加**。

### 为什么

- `doc/03_reference/index.rst:7-31` 是列表式的 `toctree`，**没注册的页面不会进构建**
- 上游用 `.. todo::` 标记未完成的段落（`doc/04_developer/index.rst:9-12` 就是一处）
- `doc/` 是 Sphinx 构建的（`.readthedocs.yml`），格式错误会让文档构建挂掉

### 怎么做

如果确实必须改上游文档（例如我们给核加了参数）：

```rst
.. _my-new-section:

My New Section
==============

Content here.

.. todo::

   Outline what is still missing.
```

并把它加进对应的 `index.rst`：

```rst
.. toctree::
   :maxdepth: 2
   :caption: In this section

   my_new_section
```

---

## E9 变更自检清单

> 每次提交前**逐条打勾**。这是本文最有用的部分。

### 改 RTL 之前

- [ ] 读一遍 [`FOCUS.md`](./FOCUS.md)，确认没踩已记录的陷阱
- [ ] 确认这次改动**是否需要**改 `rtl/ibex_*.sv`（**D14 取代 D9**：允许改，但仅限承载 TIDE 新指令的最小必要范围，**既有指令逐拍不得改动**，且全部逻辑须 `TIDE_EN` 门控）
- [ ] 如果新增了参数 → 已在 `ibex_configs.yaml` **新增**命名配置，没动已有的 6 个（E2）

### 提交前

- [ ] 新增/删除的 `.sv` **已加进所有相关 `.core` 文件**（E1）
- [ ] 若改了核心 RTL → `src_files.yml` 也同步了（E1）
- [ ] Verilator lint 通过（E3）
- [ ] Verible lint 通过（E3）
- [ ] C/C++ 已 `clang-format`（E3）
- [ ] 新模块有 `` `ASSERT_KNOWN `` 等断言，用的是 `prim_assert.sv` 宏（E5）
- [ ] `small` 配置能构建（E2）
- [ ] Simple System + hello_test 能跑起来（E6 第 4 层）
- [ ] 用了 `--signoff`（E4）
- [ ] 提交信息符合 E4 的格式
- [ ] 决策有变化 → 已更新 `docs/README.md` 的决策台账（加行，不改旧行）
- [ ] 新发现的陷阱 → 已加进 `docs/FOCUS.md`（带证据行号）

### 同步上游之后

- [ ] `docs/FOCUS.md` 里的行号是否还对得上？对不上就按给出的搜索模式重新定位并更新
- [ ] 本次上游改动是否引入了新的顶层参数 / 新配置，需要我们的 `tide` 配置同步？
- [ ] `vendor/` 是否被上游更新（不要手改，跟着上游走）
