# TIDE-MCU 验证与门禁记录

## 报告索引

- CD 集成视角：`M2_REPORT.md`
- DD 权威报告：`../../tide_dd/docs/M2_REPORT.md`
- M6 导出：`M6_REPORT.md`

## 环境

- EDA 容器：`synopsys`
- VCS：`O-2018.09-SP2-2`
- Verilator：`4.210`
- Verible：容器 `/tools/verible`
- RISC-V 工具链：`/tools/riscv`

## M0：TIDE_EN=0 上游基线

临时从 `dv/uvm/core_ibex/ibex_dv.f` 移除 `+define+TIDE_REAL_DD`，使用上游 `opentitan`
配置跑 5-test 回归，结束后恢复文件清单：

```bash
cd tide_cd/dv/uvm/core_ibex
make OUT=out_m0_current IBEX_CONFIG=opentitan SIMULATOR=vcs ISS=spike \
  ITERATIONS=1 SEED=7 \
  TEST=riscv_machine_mode_rand_test,riscv_csr_test,riscv_unaligned_load_store_test,riscv_rand_jump_test,riscv_rv32im_instr_test
```

结果（`out_m0_current/run/regr.log`）：

```text
100.00% PASS 5 PASSED, 0 FAILED
```

另外使用 `tide_small` 配置复跑同一组 5 个 testcase（TIDE 逻辑关闭）：

```bash
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_m0_small IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
  ITERATIONS=1 SEED=7 \
  TEST=riscv_machine_mode_rand_test,riscv_csr_test,riscv_unaligned_load_store_test,riscv_rand_jump_test,riscv_rv32im_instr_test
```

结果：`out_m0_small/run/regr.log` 同样为 `100.00% PASS 5 PASSED, 0 FAILED`。

## TIDE_EN=0 的实际覆盖边界

已运行的是 `IBEX_CONFIG=opentitan` 下的 5 个 UVM/riscv-dv testcase：

- `riscv_machine_mode_rand_test`
- `riscv_csr_test`
- `riscv_unaligned_load_store_test`
- `riscv_rand_jump_test`
- `riscv_rv32im_instr_test`

这组回归使用 `google_riscv-dv` 生成程序，并用 `riscv-isa-sim`/Spike 作为 RV32IMC 参考；
`lowrisc_ip` 作为 RTL/断言/primitive 依赖参与 elaboration。它不是在跑 vendor 目录中的全部资产。

明确未覆盖：

- `riscv-arch-tests` 全套架构合规测试
- `riscv-tests` 全套单元测试
- EEMBC CoreMark
- 所有 vendor primitive 配置、RAM/ROM 变体和 patched 第三方测试套件
- vendor 各目录自身的单元测试/CI

因此当前结论应表述为：

> TIDE_EN=0 通过了指定的 5-test UVM 回归、Simple System hello_test smoke 与 lint，不等于“验证了整个 vendor”。

## TIDE_EN=0：Simple System hello_test

```bash
export VERILATOR_ROOT=/tmp/verilator-root
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:$PATH

cd tide_cd
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0

make -C examples/sw/simple_system/hello_test hello_test.elf
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=examples/sw/simple_system/hello_test/hello_test.elf
```

结果：

```text
Executed cycles:       13268
Instructions Retired:  261
$finish()
```

说明：容器缺少 `srec_cat`，因此不生成 `.vmem`，而使用 Verilator 支持的 ELF
`--raminit` 路径；这不改变 RTL 回归语义。

## M1：CD lint

```bash
cd tide_cd
fusesoc --cores-root . run --target=lint --tool=verilator \
  lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint \
  lowrisc:ibex:ibex_simple_system
```

结果：两条命令均 exit 0；Verilator 零告警，Verible 零违规。

## M1/M4：CD+真实 DD UVM 定向联调

`IBEX_CONFIG_FILE` 指向只复制 `small` 流水参数的测试配置；TIDE_EN 由
`TIDE_REAL_DD` 编译宏启用，不写入 `ibex_configs.yaml`。

```bash
cd tide_cd/dv/uvm/core_ibex
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_small IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
  ITERATIONS=1 SEED=9 TEST=tide_qop_smoke WAVES=0 COV=0
```

最终证据：`out_small/run/tests/tide_qop_smoke.final2/`。

```text
Co-simulation matched 98 instructions
--- RISC-V UVM TEST PASSED ---
UVM_ERROR : 0
UVM_FATAL : 0
```

## M2/M4：DD L2

```bash
cd tide_dd
synopsys-cli make run
synopsys-cli make random SEED=1
./build_random/tide_dd_simv +SEED=2
./build_random/tide_dd_simv +SEED=3
```

结果：

```text
TIDE_DD_TEST_PASS
TIDE_DD_RANDOM_PASS seed=1
TIDE_DD_RANDOM_PASS seed=2
TIDE_DD_RANDOM_PASS seed=3
```

`tide_dd_top` 内含 commit 精确 tick SVA；定向/随机 scoreboard 逐事件核对
`commit_ts`、`code`、FIFO 顺序和完成记录。

## M6：纯 RTL 导出

```bash
cd tide_cd/export/tide_cd_rtl
synopsys-cli vcs -full64 -sverilog -timescale=1ns/1ps \
  -Mdir=/tmp/tide_cd_export_csrc \
  -f EXPORT_FILES.f -top tide_cd_top -o /tmp/tide_cd_export_simv
```

结果：VCS elaboration/link PASS；导出包只含 `.sv/.svh`、`EXPORT_FILES.f` 和
`MANIFEST.sha256`，不含 FuseSoC/Makefile/脚本/构建产物。
## 2026-10-22 A3 单 hart 改造后复验

单 hart DD 端口改造后，原 A3 证据不再足够新。此前 `out_single_hart` 已编译到 testbench，但 Spike DPI 被容器默认 `g++ 4.4 + -std=c99` 阻塞。现已修正 UVM VCS 配置：

- C++ DPI 使用 `/usr/bin/g++-7`；
- 移除对 C++ 源不合法的 `--std=c99`；
- 链接增加 `-no-pie`，兼容容器内 VCS 静态对象；
- C 源码仍由 gcc 编译，`date.c` 使用默认 gnu89 兼容模式。

复验命令：

```bash
cd tide_cd/dv/uvm/core_ibex
export PATH=/opt/py313/bin:/tools/riscv/bin:$PATH
export PKG_CONFIG_PATH=/tools/riscv-isa-sim/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/tools/riscv-isa-sim/lib:$LD_LIBRARY_PATH
export RISCV_TOOLCHAIN=/tools/riscv
export RISCV_GCC=/tools/riscv/bin/riscv32-unknown-elf-gcc
export RISCV_OBJCOPY=/tools/riscv/bin/riscv32-unknown-elf-objcopy
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_single_hart_v4 IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
       ITERATIONS=1 SEED=9 TEST=tide_qop_smoke WAVES=0 COV=0
```

结果：

```text
100.00% PASS 1 PASSED, 0 FAILED
Co-simulation matched 98 instructions
--- RISC-V UVM TEST PASSED ---
UVM_ERROR : 0
UVM_FATAL : 0
```

证据：`out_single_hart_v4/run/regr.log`、`out_single_hart_v4/run/tests/tide_qop_smoke.9/rtl_sim_stdstreams.log`。

## 2026-11-06 QWAIT room/limit 改动后 TIDE_EN=0 复验

QWAIT 合法性改为 room/limit 形式（见 `docs/README.md` D20 / `docs/FOCUS.md` F17）后，按不变量 I1 重跑 `TIDE_EN=0` 的 Simple System + `hello_test`。

```bash
cd tide_cd
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:$PATH
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0 \
  --SRAMInitFile=examples/sw/simple_system/hello_test/hello_test.vmem
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system
```

结果（`build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/ibex_simple_system.log`）：

```text
Hello simple system
DEADBEEF
BAADF00D
Tick!
Tock!
Tick!
Tock!
Tick!
```

```text
Executed cycles:       13268
Instructions Retired:  261
$finish()
```

说明：容器缺少 `srec_cat`，`hello_test.vmem` 由 `hello_test.bin` 生成；`@` 后必须是**字地址**（`$readmemh` 把 `@addr` 当数组下标），写成字节地址会使镜像错位 4 倍。周期数与 2026-10-22 基线一致。

## 2026-11-06 QTRIG 入队检查器 2 级流水复验

DD `tide_enqueue` 改为固定 2 级流水（T 拍采样并寄存 C2/C3/C4，T+1 拍掩码归约、仲裁并原子 push；C3 用 `elapsed(T)+TQ_GUARD+1`），CD 侧按 `tide_qtrig_wait_q`/`tide_qtrig_abort_q` 做固定一拍握手，并新增错误现场跨 abort/FLUSH 拍保持（D22）与编码非法 TIDE 指令门控（D23）。见 `docs/README.md` D21–D23、`docs/FOCUS.md` F18–F20。

```bash
# DD 定向 + 随机
cd ../tide_dd && make run && make random SEED=1 && ./build_random/tide_dd_simv +SEED=7

# 最小系统定向回归（自检固件自动发现）
cd ../tide_exp && make directed-verify

# MCU 顶层 lint / elaboration / hello world
make mcu-lint mcu-elab mcu-top
```

结果：

| 项目 | 结果 |
|---|---|
| `tide_dd` `make run` | `TIDE_DD_TEST_PASS` |
| `tide_dd` random seed 1 / 7 | `TIDE_DD_RANDOM_PASS seed=1` / `seed=7` |
| `tide_exp` `make directed-verify` | 15/15 `DIRECTED_TEST_PASS`（含 `tide_errors` 的 TQ_LATE 现场、`tide_qtrig_dual` 原子双通道、`tide_qwait_limit`） |
| `tide_exp` `make mcu-lint` | Verilator + Verible 0 warning / 0 error |
| `tide_exp` `make mcu-elab` | PASS |
| `tide_exp` `make mcu-top` | `TIDE_MCU_TOP_TEST_PASS` |
| `tide_cd` TIDE_EN=0 hello_test | 输出与基线逐行一致（`Hello simple system` / `DEADBEEF` / `BAADF00D` / `Tick!/Tock!`）；13268 cycles / 261 instructions |
| `tide_cd` UVM `tide_qop_smoke`（small + 真实 DD，SEED=9） | `Co-simulation matched 98 instructions`；`UVM_ERROR : 0`、`UVM_FATAL : 0`；`--- RISC-V UVM TEST PASSED ---` |

证据：`../tide_exp/build/directed_verify_final.log`、`../tide_dd/build/dd_run_final.log`、`dd_random_s1_final.log`、`dd_random_s7_final.log`、`../tide_exp/build/mcu_verify_run2.log`、`build/tide_en0_run.log`、`ibex_simple_system.log`、`dv/uvm/core_ibex/out_qtrig_pipe/run/regr.log`、`dv/uvm/core_ibex/out_qtrig_pipe/run/tests/tide_qop_smoke.9/rtl_sim_stdstreams.log`。

说明：`make mcu-lint` 曾报 `ibex_id_stage.sv:1107` 的 48/33 位宽减法警告；修复为显式零扩展 `{15'd0, qwait_incr}`（与隐式零扩展语义完全相同），修复后 lint 0 warning。

## 2026-11-09 T1/T2 CSR split bus 寄存响应复验

TIDE CSR split bus 读响应改为**寄存一拍**（ADR C20、`docs/README.md` D24、`docs/FOCUS.md` F21）：T1 请求载荷（`addr/wdata/tlr`）无条件跟踪当前 CSR 指令，只有 `valid/write` 受控；T2 CD 在 ID 第一拍发单拍读请求并 `stall_tide_csr` 一拍，第二拍用 DD 寄存的响应写回。DD `tide_csr` 增加 `clk_i/rst_ni` 与响应寄存器；`tide_dd_stub` 与 `tide_dd_tb` 同步建模 1 拍延迟。

```bash
# DD 定向 + 随机
cd ../tide_dd && make run && make random SEED=1 && ./build_random/tide_dd_simv +SEED=7

# 最小系统定向回归
cd ../tide_exp && make directed-verify

# MCU 顶层 lint / elaboration / hello world
make mcu-lint mcu-elab mcu-top

# CD lint（Verilator + Verible）
cd ../tide_cd
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:/tools/verible/bin:$PATH
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# TIDE_EN=0 回归
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0 \
  --SRAMInitFile=examples/sw/simple_system/hello_test/hello_test.vmem
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system

# small 配置 + 真实 DD UVM（ibex_dv.f 已含 +define+TIDE_REAL_DD）
cd dv/uvm/core_ibex
make TEST=tide_qop_smoke SEED=9 SIMULATOR=vcs OUT=out_t1t2_csr
```

结果：

| 项目 | 结果 |
|---|---|
| `tide_dd` `make run` | `TIDE_DD_TEST_PASS` |
| `tide_dd` random seed 1 / 7 | `TIDE_DD_RANDOM_PASS seed=1` / `seed=7` |
| `tide_exp` `make directed-verify` | 15/15 `DIRECTED_TEST_PASS`（含 `tide_csr` 的 DD RO 读回、`tide_errors` 现场、`tide_qtrig_dual` 原子双通道、`tide_qwait_limit`） |
| `tide_exp` `make mcu-lint` | Verilator + Verible 0 warning / 0 error（日志 0 字节） |
| `tide_exp` `make mcu-elab` | PASS |
| `tide_exp` `make mcu-top` | `TIDE_MCU_TOP_TEST_PASS` |
| `tide_cd` Verilator lint | exit 0；无 RTL warning（`build/lint_verilator_t1t2.log` 仅 edalize 弃用提示） |
| `tide_cd` Verible lint | exit 0；0 warning / 0 error |
| `tide_cd` TIDE_EN=0 hello_test | 输出与基线逐行一致（`Hello simple system` / `DEADBEEF` / `BAADF00D` / `Tick!/Tock!`）；`Executed cycles: 13268` / `Instructions Retired: 261` |
| `tide_cd` UVM `tide_qop_smoke`（small + 真实 DD，SEED=9） | `Co-simulation matched 98 instructions`；`UVM_ERROR : 0`、`UVM_FATAL : 0`；`--- RISC-V UVM TEST PASSED ---` |

证据：`../tide_dd/build/sim.log`、`../tide_dd/build_random/sim.log`、`../tide_dd/build_random/sim_seed7.log`、`../tide_exp/build/directed_*.log`（2026-11-09）、`../tide_exp/build/tide_mcu_verilator_lint.log`（0 字节）、`tide_mcu_verible_lint.log`（0 字节）、`tide_mcu_elab.log`、`tide_mcu_sim.log`、`build/lint_verilator_t1t2.log`、`build/lint_verible_t1t2.log`、`build/tide_en0_t1t2_run.log`、`build/tide_en0_t1t2_sim.log`、`dv/uvm/core_ibex/out_t1t2_csr/run/regr.log`、`dv/uvm/core_ibex/out_t1t2_csr/run/tests/tide_qop_smoke.9/rtl_sim_stdstreams.log`。

说明：Verilator lint 同时清掉 QWAIT 工作区遗留的 `qwait_sum[48]` UNUSED 警告：`qwait_sum` 声明为 `logic [47:0]`（`ibex_id_stage.sv:995`），由 `tide_tlr_q + {15'd0, qwait_incr}`（`:1003`）直接得到 48 位和并赋给 `tide_tlr_q`（`:1155`）。只有合法（`TLR + incr ≤ TLR_MAX`）时 `qwait_commit` 有效，非法情形不提交，合法路径上 48 位和不会溢出；被丢弃的进位位从来不属于体系结构结果。功能等价，0 warning。

## 2026-11-10 Stage 3（A1/A2/A4/B1/A3+A3b/B2）时序优化复验

按新 `syn_final.timing.rpt` 的违例类型实施六项（决策 D26–D30，冻结 `../tide_doc` ADR C21）：A1 恢复 `BranchTargetALU=0`；A2 RV32MFast 末级乘积累加流水（MUL/MULH 各 +1 拍）；A3/A3b `tide_dd_top` 输入提交边界 + `tide_evt_pipe`；A4 `tide_mcu_top` 取指输出寄存器；B1 IF 段 TIDE 预译码随指令寄存进 ID；B2 `csr_instr_done` 锥切割（与计划的"计数写使能寄存"存在偏差，论证见 D30/F24）。

复验命令：

```bash
# DD 定向 + 随机
cd ../tide_dd
synopsys-cli make run
synopsys-cli make random SEED=1
synopsys-cli make random SEED=7

# tide_exp
cd ../tide_exp && make directed-verify

# MCU 顶层 lint / elaboration / hello world
make mcu-lint mcu-elab mcu-top

# CD lint（Verilator + Verible）
cd ../tide_cd
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:/tools/verible/bin:$PATH
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# TIDE_EN=0 回归
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0 \
  --SRAMInitFile=examples/sw/simple_system/hello_test/hello_test.vmem
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system

# small 配置 + 真实 DD UVM（ibex_dv.f 已含 +define+TIDE_REAL_DD）
cd dv/uvm/core_ibex
export RISCV_TOOLCHAIN=/tools/riscv
export RISCV_GCC=/tools/riscv/bin/riscv32-unknown-elf-gcc
export RISCV_OBJCOPY=/tools/riscv/bin/riscv32-unknown-elf-objcopy
export PKG_CONFIG_PATH=/tools/riscv-isa-sim/lib/pkgconfig
export SPIKE_PATH=/tools/riscv-isa-sim/bin
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_b3 IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
       ITERATIONS=1 SEED=9 TEST=tide_qop_smoke WAVES=0 COV=0
```

结果：

| 项目 | 结果 |
|---|---|
| `tide_dd` `make run` | `TIDE_DD_TEST_PASS` |
| `tide_dd` random seed 1 / 7 | `TIDE_DD_RANDOM_PASS seed=1` / `seed=7` |
| `tide_exp` `make directed-verify` | 15/15 `DIRECTED_TEST_PASS` |
| `tide_exp` `make mcu-lint` | Verilator + Verible exit 0；日志 0 字节 |
| `tide_exp` `make mcu-elab` | PASS |
| `tide_exp` `make mcu-top` | `TIDE_MCU_TOP_TEST_PASS` |
| `tide_cd` Verilator lint | exit 0 |
| `tide_cd` Verible lint | exit 0 |
| `tide_cd` TIDE_EN=0 hello_test | 输出与基线逐行一致（`Hello simple system` / `DEADBEEF` / `BAADF00D` / `Tick!`/`Tock!`）；`Executed cycles: 13268` / `Instructions Retired: 261` |
| `tide_cd` UVM `tide_qop_smoke`（small + 真实 DD，SEED=9） | `Co-simulation matched 98 instructions`；`UVM_ERROR : 0`、`UVM_FATAL : 0`；`--- RISC-V UVM TEST PASSED ---` |

证据：`../tide_dd/build/sim_directed_b3.log`、`../tide_dd/build_random/sim_seed1_b3.log`、`../tide_dd/build_random/sim_seed7_b3.log`、`../tide_exp/build/regr_b3_directed.log`（15 条 `DIRECTED_TEST_PASS`）、`../tide_exp/build/regr_b3_lint.log`、`../tide_exp/build/tide_mcu_verilator_lint.log`（0 字节）、`tide_mcu_verible_lint.log`（0 字节）、`../tide_exp/build/regr_b3_elab.log`、`../tide_exp/build/regr_b3_top.log`、`build/lint_verilator_b3.log`、`build/lint_verible_b3.log`、`build/tide_en0_b3_build.log`、`build/tide_en0_b3_run.log`、`ibex_simple_system.log`（字符输出）、`dv/uvm/core_ibex/out_b3/run/regr.log`、`dv/uvm/core_ibex/out_b3/run/tests/tide_qop_smoke.9/rtl_sim.log`、`.../rtl_sim_stdstreams.log`。

说明：A2 的乘法语义另经 8 向量定向测试覆盖 MUL/MULH/MULHSU/MULHU、符号/无符号高半与 32/16 深依赖链（scratch 测试，未入库）。外部综合仍需在用户环境（O-2018.06-SP1 + `/data/pdk`）重跑 `syn` 取新 `syn_final.timing.rpt` 复核最差 slack ≥ −0.05 ns。

## 2026-11-10 Stage 4（D31 乘法全寄存）时序优化复验

按复测报告（clk 组 100/100 条违例 −0.17 ns，其中 99 条穿过 `gen_multdiv_fast_multdiv_i`，起点为 IF-ID 指令寄存器、终点为 RF 写寄存器；扣除用户确认不动的 U1（0.22 ns uncertainty / `ssg0p81vm40c`）后仅 +0.05 ns，是本设计唯一净余量不足 0.1 ns 的锥（其余违例净余量 ≥ +0.07 ns））实施 D31：TIDE 构建的 RV32MFast 增加 `MD_LATCH`（idle 拍寄存 `op_a/op_b/signed_mode/operator`，69 个 flop）与 `MD_DONE`（呈现 `imd_val_q[0]`）；AHBL/AHBH 末拍只把格式化结果写入 `imd_val_q[0]`；`multdiv_result_o` 在 TIDE 构建恒取 `imd_val_q_i[0][31:0]`（`div_sel_i | TIDE_EN`），组合乘法器不再驱动 RF 写口。MUL 3→5 拍、MULH/MULHSU/MULHU 4→6 拍（各 +2；比 D27 再多 1 拍），DIV 不变；`TIDE_EN=0` 逐拍保持上游。D27 的 `tide_prod_q/tide_wrap_q/tide_sum` 实现与对应 Verilator waiver 一并删除。

复验命令：

```bash
# DD 定向 + 随机
cd ../tide_dd
synopsys-cli make run
synopsys-cli make random SEED=1
synopsys-cli make random SEED=7

# tide_exp
cd ../tide_exp && make directed-verify

# MCU 顶层 lint / elaboration / hello world
make mcu-lint mcu-elab mcu-top

# CD lint（Verilator + Verible）
cd ../tide_cd
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:/tools/verible/bin:$PATH
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# TIDE_EN=0 回归
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=examples/sw/simple_system/hello_test/hello_test.elf

# small 配置 + 真实 DD UVM（ibex_dv.f 已含 +define+TIDE_REAL_DD）
cd dv/uvm/core_ibex
export PATH=/opt/py313/bin:/tools/riscv/bin:$PATH
export RISCV_TOOLCHAIN=/tools/riscv
export RISCV_GCC=/tools/riscv/bin/riscv32-unknown-elf-gcc
export RISCV_OBJCOPY=/tools/riscv/bin/riscv32-unknown-elf-objcopy
export PKG_CONFIG_PATH=/tools/riscv-isa-sim/lib/pkgconfig
export SPIKE_PATH=/tools/riscv-isa-sim/bin
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_s4 IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
       ITERATIONS=1 SEED=9 TEST=tide_qop_smoke WAVES=0 COV=0
```

结果：

| 项目 | 结果 |
|---|---|
| `tide_dd` `make run` | `TIDE_DD_TEST_PASS` |
| `tide_dd` random seed 1 / 7 | `TIDE_DD_RANDOM_PASS seed=1` / `seed=7` |
| `tide_exp` `make directed-verify` | 15/15 `DIRECTED_TEST_PASS` |
| `tide_exp` `make mcu-lint` | Verilator + Verible exit 0；日志 0 字节 |
| `tide_exp` `make mcu-elab` | PASS |
| `tide_exp` `make mcu-top` | `TIDE_MCU_TOP_TEST_PASS` |
| `tide_cd` Verilator lint | exit 0；无 RTL warning |
| `tide_cd` Verible lint | exit 0；0 warning / 0 error |
| `tide_cd` TIDE_EN=0 hello_test | 输出与基线逐行一致（`Hello simple system` / `DEADBEEF` / `BAADF00D` / `Tick!`/`Tock!`）；`Executed cycles: 13268` / `Instructions Retired: 261` |
| `tide_cd` UVM `tide_qop_smoke`（small + 真实 DD，SEED=9） | `Co-simulation matched 98 instructions`；`UVM_ERROR : 0`、`UVM_FATAL : 0`；`--- RISC-V UVM TEST PASSED ---` |

证据：`../tide_dd/build/sim_directed_s4.log`、`../tide_dd/build_random/sim_seed1_s4.log`、`../tide_dd/build_random/sim_seed7_s4.log`、`../tide_exp/build/regr_s4_directed.log`（15 条 `DIRECTED_TEST_PASS`）、`../tide_exp/build/tide_mcu_verilator_lint.log`（0 字节）、`tide_mcu_verible_lint.log`（0 字节）、`../tide_exp/build/regr_s4_top.log`、`build/lint_verilator_s4b.log`、`build/lint_verible_s4b.log`、`build/tide_en0_s4_build2.log`、`build/tide_en0_s4_run2.log`、`build/tide_en0_s4_uart.log`、`build/mul_sim_build_s4.log`、`build/mul_sim_run_s4.log`、`build/mul_s4_uart.log`、`build/mul_s4_trace.log`、`dv/uvm/core_ibex/out_s4/run/regr.log`、`dv/uvm/core_ibex/out_s4/run/tests/tide_qop_smoke.9/rtl_sim.log`、`.../rtl_sim_stdstreams.log`、`dv/uvm/core_ibex/out_s4/run/uvm_s4_make.log`。

说明：乘法语义另经 8 向量定向测试覆盖 MUL/MULH/MULHSU/MULHU、符号/无符号高半与 32/16 深依赖链（scratch 测试，未入库；`MUL_TEST_PASS`，457 instructions）。周期数从 D27 的 1116 增至 1196，差值 80 = 80 次乘法 × +1 拍，与 MUL 5 拍 / MULH 6 拍一致。外部综合仍需在用户环境（O-2018.06-SP1 + `/data/pdk`）重跑 `syn` 取新 `syn_final.timing.rpt` 复核最差 slack ≥ −0.05 ns；按报告分段估算新最差路径约 +0.12 ns（RF 写路径约 0.2 ns），为预测值。U1（0.22 ns uncertainty）按用户决定不动；`clock_gating_default` 组与 `tide_mmio` SPI 路径在扣除 U1 后均满足，不属本设计净违例。

## 2026-11-11 Stage 5（D32 乘法操作数/累加器提前一拍寄存；删除死参数）时序优化复验

按新复测报告（303 条路径；`clk` 组 100/100 违例、`clock_gating_default` 组 90/100 违例、`sclk` 100 条 MET；最差 slack −0.15 ns）分析：两条 −0.15 均为**上游 Ibex 分支锥**（`if_stage_i/instr_rdata_id_o_reg_18_` → `gen_prefetch_buffer_prefetch_buffer_i/fifo_i/valid_q_reg_0_/1_`，路径中无 TIDE 信号，扣除 U1 后净余量 +0.07）；TIDE 自有最差为 `gen_mult_fast_mult_state_q_reg_2_ → id_stage_i/imd_val_q_reg_0__{17..33}_`（15 条，arrival 0.89 / required 0.74 / slack −0.14；扣除 U1 后 +0.08）。D31 已把操作数/控制寄存进 `MD_LATCH`，但 FSM 状态仍以 4 级译码驱动操作数/符号/累加 mux（0.08→0.22，0.14 ns）进入乘法锥。D32 增加 68 个 flop（`tide_mul_a_q/tide_mul_b_q/tide_sign_a_q/tide_sign_b_q/tide_accum_q`），由 `mult_state_d` 提前选好下一拍的操作数/符号/累加器；ALBL 的输入在 `MD_LATCH` 拍直接取 `op_a_i/op_b_i[15:0]`。FSM 状态转移与拍数完全不变（MUL 5 拍、MULH/MULHSU/MULHU 6 拍、DIV 不变），`TIDE_EN=0` 保留上游组合操作数表达式。同轮删除 `ibex_tide_pkg` 中无任何 RTL 读者的 `TIDE_EN` 包参数（门控仍由各模块 `parameter bit TIDE_EN` 与 `tide_cd_top` 传递），并更新 `ibex_simple_system.sv` 中引用该包参数的过时注释。

复验命令：

```bash
# DD 定向 + 随机
cd ../tide_dd
synopsys-cli make run
synopsys-cli make random SEED=1
synopsys-cli make random SEED=7

# tide_exp
cd ../tide_exp && make directed-verify

# MCU 顶层 lint / elaboration / hello world
make mcu-lint mcu-elab mcu-top

# CD lint（Verilator + Verible）
cd ../tide_cd
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:/tools/verible/bin:$PATH
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# TIDE_EN=0 回归
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=examples/sw/simple_system/hello_test/hello_test.elf

# TIDE_EN=1 + 乘法定向测试（scratch，未入库）
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=1
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=/tmp/tide_mul_test/mul_test.vmem

# small 配置 + 真实 DD UVM（ibex_dv.f 已含 +define+TIDE_REAL_DD）
cd dv/uvm/core_ibex
export PATH=/opt/py313/bin:/tools/riscv/bin:$PATH
export RISCV_TOOLCHAIN=/tools/riscv
export RISCV_GCC=/tools/riscv/bin/riscv32-unknown-elf-gcc
export RISCV_OBJCOPY=/tools/riscv/bin/riscv32-unknown-elf-objcopy
export PKG_CONFIG_PATH=/tools/riscv-isa-sim/lib/pkgconfig
export SPIKE_PATH=/tools/riscv-isa-sim/bin
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_s5 IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
       ITERATIONS=1 SEED=9 TEST=tide_qop_smoke WAVES=0 COV=0
```

结果：

| 项目 | 结果 |
|---|---|
| `tide_dd` `make run` | `TIDE_DD_TEST_PASS` |
| `tide_dd` random seed 1 / 7 | `TIDE_DD_RANDOM_PASS seed=1` / `seed=7` |
| `tide_exp` `make directed-verify` | 15/15 `DIRECTED_TEST_PASS` |
| `tide_exp` `make mcu-lint` | Verilator + Verible exit 0；日志 0 字节 |
| `tide_exp` `make mcu-elab` | PASS |
| `tide_exp` `make mcu-top` | `TIDE_MCU_TOP_TEST_PASS` |
| `tide_cd` Verilator lint | exit 0；无 RTL warning（`build/lint_verilator_s5.log`） |
| `tide_cd` Verible lint | exit 0；0 warning / 0 error（`build/lint_verible_s5.log`） |
| `tide_cd` TIDE_EN=0 hello_test | 输出与基线逐行一致（`Hello simple system` / `DEADBEEF` / `BAADF00D` / `Tick!`/`Tock!`）；`Executed cycles: 13268` / `Instructions Retired: 261` |
| `tide_cd` TIDE_EN=1 乘法定向测试 | `MUL_TEST_PASS`；457 instructions / 1196 cycles（与 D31 完全一致，证明零额外拍） |
| `tide_cd` UVM `tide_qop_smoke`（small + 真实 DD，SEED=9） | `Co-simulation matched 98 instructions`；`UVM_ERROR : 0`、`UVM_FATAL : 0`；`--- RISC-V UVM TEST PASSED ---` |

证据：`../tide_dd/build/sim_directed_s5.log`、`../tide_dd/build/sim_seed1_s5.log`、`../tide_dd/build/sim_seed7_s5.log`、`../tide_exp/build/regr_s5_directed.log`（15 条 `DIRECTED_TEST_PASS`）、`../tide_exp/build/regr_s5_lint.log`、`../tide_exp/build/tide_mcu_verilator_lint.log`（0 字节）、`tide_mcu_verible_lint.log`（0 字节）、`../tide_exp/build/regr_s5_elab.log`、`../tide_exp/build/regr_s5_top.log`（`TIDE_MCU_TOP_TEST_PASS`）、`build/lint_verilator_s5.log`、`build/lint_verible_s5.log`、`build/tide_en0_s5_build.log`、`build/tide_en0_s5_run2.log`、`build/tide_en0_s5_uart.log`、`build/tide_en1_s5_build.log`、`build/mul_s5_sim.log`、`build/uvm_s5_make.log`、`dv/uvm/core_ibex/out_s5/run/regr.log`、`dv/uvm/core_ibex/out_s5/run/tests/tide_qop_smoke.9/rtl_sim_stdstreams.log`。

说明：按报告分段，乘法锥的起点从 `mult_state_q` Q（0.08）移到操作数 flop Q（0.08），但去掉了 4 级状态译码（0.08→0.22）与状态选择 mux，预计新 arrival ≈ 0.75、slack ≈ 0.00（预测值；扣除 U1 的 0.22 ns 后 ≈ +0.22），需在用户环境（O-2018.06-SP1 + `/data/pdk`）重跑 `syn` 复核。报告最差仍是上游 Ibex 分支锥的两条 −0.15（净余量 +0.07），该锥不经过任何 TIDE 逻辑，除非改上游分支判定/取指握手时序（会改变既有指令逐拍行为）或调整 U1；两者均不在本轮范围。`tide_mmio` SPI（−0.12，净 +0.10）、TIDE 预译码 ICG（−0.10，净 +0.12）、DD `head_q` → 外部 DAQ ICG（−0.09..−0.05，净 ≥ +0.13）等其余违例在扣除 U1 后均为正余量，未改动。

## 2026-11-11 Stage 6（P0/P1/P2/P3/P4a/P4b）时序优化复验

按用户确认的方向实施六项（`tide_cd` D33）：P0 TIDE 构建条件分支固定两拍 + 专用目标加法器；P1 `tide_tq` commit 输出寄存一拍；P2 SPI `div_term_q` 寄存比较；P3 DD 本地 TQ 复位同步器；P4a/P4b `tide_accum_q`、`op_quotient_q` 改为无使能寄存器。P4 相对批准的“加一级寄存器 / +1 拍”为 **0 额外拍**实现：报告显示这两条违例的终点是 ICG EN（ECE 的 D≠Q 比较），flop D 端已 MET；恒写纯数据次态同时去掉 ICG 与 ECE，乘除拍数不变（MUL 5 / MULH 类 6 / DIV 不变）。

复验命令：

```bash
# DD 定向 + 随机（commit 输出寄存后的断言/TB 已同步）
cd ../tide_dd
synopsys-cli make run
synopsys-cli make random SEED=1
synopsys-cli make random SEED=7

# tide_mmio lint + 定向（SPI 分频比较）
cd ../tide_mmio
synopsys-cli make lint
synopsys-cli make run

# tide_exp
cd ../tide_exp && make directed-verify
make mcu-lint mcu-elab mcu-top

# CD lint（Verilator + Verible）
cd ../tide_cd
export PATH=/opt/py313/bin:/tools/riscv/bin:/tools/verilator/v4.210/bin:/tools/verible/bin:$PATH
fusesoc --cores-root . run --target=lint --tool=verilator   lowrisc:ibex:ibex_simple_system
fusesoc --cores-root . run --target=lint --tool=veriblelint lowrisc:ibex:ibex_simple_system

# TIDE_EN=0 回归
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=0
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=examples/sw/simple_system/hello_test/hello_test.elf

# TIDE_EN=1 + 乘除定向测试（scratch，未入库）
fusesoc --cores-root=. run --target=sim --setup --build \
  lowrisc:ibex:ibex_simple_system --TIDE_EN_SYS=1
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=/tmp/tide_mul_test/mul_test.vmem
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system \
  --raminit=/tmp/tide_div_test/div_test.vmem

# small 配置 + 真实 DD UVM（out_s7：out_s6 为修复断言前的旧树，不能复用）
cd dv/uvm/core_ibex
export PATH=/opt/py313/bin:/tools/riscv/bin:$PATH
export RISCV_TOOLCHAIN=/tools/riscv
export RISCV_GCC=/tools/riscv/bin/riscv32-unknown-elf-gcc
export RISCV_OBJCOPY=/tools/riscv/bin/riscv32-unknown-elf-objcopy
export PKG_CONFIG_PATH=/tools/riscv-isa-sim/lib/pkgconfig
export SPIKE_PATH=/tools/riscv-isa-sim/bin
IBEX_CONFIG_FILE=dv/uvm/core_ibex/tide_small_config.yaml \
  make OUT=out_s7 IBEX_CONFIG=tide_small SIMULATOR=vcs ISS=spike \
       ITERATIONS=1 SEED=9 TEST=tide_qop_smoke WAVES=0 COV=0
```

结果：

| 项目 | 结果 |
|---|---|
| `tide_dd` `make run` | `TIDE_DD_TEST_PASS`（commit 断言改比 `elapsed_q`） |
| `tide_dd` random seed 1 / 7 | `TIDE_DD_RANDOM_PASS seed=1` / `seed=7` |
| `tide_mmio` `make lint` | Verilator + Verible exit 0；两份日志 0 字节 |
| `tide_mmio` `make run` | `TIDE_MMIO_TEST_PASS` |
| `tide_exp` `make directed-verify` | 15/15 `DIRECTED_TEST_PASS`，`all directed tests passed` |
| `tide_exp` `make mcu-lint` | exit 0；Verilator + Verible 日志 0 字节 |
| `tide_exp` `make mcu-elab` / `mcu-top` | PASS / `TIDE_MCU_TOP_TEST_PASS` |
| `tide_cd` Verilator lint | exit 0；无 RTL warning（`build/lint_verilator_s6.log`） |
| `tide_cd` Verible lint | exit 0；0 warning / 0 error（`build/lint_verible_s6.log`） |
| `tide_cd` TIDE_EN=0 hello_test | 输出与基线逐行一致；`Executed cycles: 13268` / `Instructions Retired: 261` |
| `tide_cd` TIDE_EN=1 乘法定向测试 | `MUL_TEST_PASS`；457 instructions / **1203** cycles（+7 = P0 使未跳转条件分支也走两拍） |
| `tide_cd` TIDE_EN=1 除法定向测试 | `DIV_TEST_PASS`；174199 instructions / 315188 cycles（200 随机 + 边界向量） |
| `tide_cd` UVM `tide_qop_smoke`（small + 真实 DD，SEED=9） | `Co-simulation matched 98 instructions`；`UVM_ERROR : 0`、`UVM_FATAL : 0`；`--- RISC-V UVM TEST PASSED ---`；DD `tide_dd_top.sv` 断言 0 条 |

证据：`../tide_dd/build/sim_directed_s6.log`、`../tide_dd/build_random/sim_seed1_s6.log`、`../tide_dd/build_random/sim_seed7_s6.log`、`../tide_mmio/build/lint_s6.log`、`../tide_mmio/build/verilator_lint.log`（0 字节）、`../tide_mmio/build/verible_lint.log`（0 字节）、`../tide_mmio/build/run_s6.log`、`../tide_mmio/build/sim.log`、`../tide_exp/build/regr_s6_directed.log`、`../tide_exp/build/regr_s6_lint.log`、`../tide_exp/build/tide_mcu_verilator_lint.log`（0 字节）、`../tide_exp/build/tide_mcu_verible_lint.log`（0 字节）、`../tide_exp/build/regr_s6_elab.log`、`../tide_exp/build/regr_s6_top.log`、`build/lint_verilator_s6.log`、`build/lint_verible_s6.log`、`build/tide_en0_s6_build2.log`、`build/tide_en0_s6_run2.log`、`build/tide_en0_s6_uart.log`、`build/mul_s6_run2.log`、`build/mul_s6_uart.log`、`build/div_s6_run.log`、`build/div_s6_uart.log`、`build/uvm_s7_make.log`、`dv/uvm/core_ibex/out_s7/run/regr.log`、`dv/uvm/core_ibex/out_s7/run/tests/tide_qop_smoke.9/rtl_sim_stdstreams.log`。

说明：本轮只针对报告中的 TIDE/外设自有锥，未改 U1，也未改任何既有指令的译码、异常语义（`TIDE_EN=0` 逐拍回归由 hello_test 与 lint 复验）。P1 使码字交付相对 `ts==elapsed` 弹出拍固定延后 1 tick（队列状态仍在弹出拍推进）；该延迟由用户确认接受，DD 断言与 TB 已按“弹出拍的 `elapsed`”语义同步。P0 使 TIDE 构建的未跳转条件分支由 1 拍变 2 拍（taken/not-taken 固定一致，利于 WCET），这是 MUL 定向测试 1196→1203 的唯一来源。目标违例（分支 `id_in_ready` 锥、TQ `head_q`→外部 ICG、SPI 分频 ICG、复位释放→TQ 门控、`tide_accum_q`/`op_quotient_q` ICG）预计在用户重跑 `syn` 后消失或显著改善，仍需以新 `syn_final.timing.rpt` 复核 ≤ 0.05 ns（扣除 U1 的口径按前几轮执行）。
