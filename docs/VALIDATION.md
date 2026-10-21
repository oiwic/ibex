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