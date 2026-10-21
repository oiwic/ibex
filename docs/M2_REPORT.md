# M2 报告（CD 集成视角）

M2 的 DD RTL 权威报告位于：

- `../../tide_dd/docs/M2_REPORT.md`

本文只记录 CD 仓在 M2 阶段的集成与验收视角，不重复 DD 内部实现细节。

## 范围

- DD 仓实现 `tide_dd_top` 及 GC、anchor、enqueue、TQ、RQ、sync、err、CSR、MMIO、xboard。
- CD UVM testbench 通过 `TIDE_REAL_DD` 接入真实 `tide_dd_top`。
- CD 侧 `small` 基线使用真实 DD 完成 QSYNC/QTRIG/QLOAD/QTRIG-LATE 联调。

## 证据

- UVM：`out_small/run/tests/tide_qop_smoke.final2/rtl_sim.log`
- 结果：`Co-simulation matched 98 instructions`、`TEST PASSED`、0 error/fatal
- 详细 DD L2 命令与结果：`../../tide_dd/docs/M2_REPORT.md`
- 完整 M0–M6 命令：`./VALIDATION.md`

## 注意

`TIDE_EN=0` 的 5-test 回归和 M2 的真实 DD 联调是两组不同验证：

- `TIDE_EN=0`：验证 TIDE 逻辑关闭时上游 Ibex 行为不回归。
- `TIDE_EN=1 + TIDE_REAL_DD`：验证真实 DD 接入后的 TIDE 语义。