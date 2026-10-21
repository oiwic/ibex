# 关注重点 / 已知陷阱

> **每条都带证据行号。**没有行号的结论视为未验证。
> 行号对应 HEAD `96a34a56`（2026-10-15 自 `lowrisc/ibex` 同步；勘察时锚点 `af456e25` 与它 `rtl/` 逐字节一致，**行号未漂移**）。每条都附**搜索模式**，上游同步后行号漂移时用它重新定位。
>
> 格式：**现象** → **后果** → **硬规则** → **证据** → **对我们的影响**

---

## F1 取指通路的"推测"是天生的，与分支预测无关

**现象**：即使把 `ICache=0`、`BranchPredictor=0` 全关，Ibex 仍然有一个 **prefetch buffer**，
它会**在你还没执行到那条指令时就去读取指总线**。

**后果**：取指总线上的读是"投机"的，可能被丢弃、可能重复。任何"读一次就变状态"的设备放在这里都会被破坏。

**硬规则**：**把取指通路当作"只读、无副作用、可任意重复访问"的存储器通路来对待。**

**证据**：

- `rtl/ibex_if_stage.sv:313-314` —— prefetch buffer 的例化（`ibex_prefetch_buffer`）
- `rtl/ibex_prefetch_buffer.sv` —— 模块本体，默认就在用
- `rtl/ibex_if_stage.sv:141-148`、`:287-288` —— prefetch 相关信号与 `prefetch_addr`

**搜索模式**：`ibex_prefetch_buffer`、`prefetch_branch`

---

## F2 ★★ 取指总线上绝不能挂有副作用的设备

**现象**：PMP **只闸数据侧**，取指侧的请求**完全不经过 PMP 检查**。

**后果**：如果你把 UART / SPI / 任何"读一下就清标志/推进 FIFO"的设备挂到取指总线上，
CPU 一投机取指就会吃掉数据。**这种 bug 极难复现、极难定位。**

**硬规则**：

1. **我们的 UART / SPI / Timer 一律只挂数据侧**（已在 D5 / D6 决策）。
2. 取指总线上只允许：ROM、SRAM、以及任何"读无副作用"的存储器。
3. 如果被迫要在取指总线上放一个非存储设备，**必须自己加一层"只读、幂等"的适配**。

**证据**：`doc/03_reference/pmp.rst:22-30` 原文（极其明确）：

> Addresses from the instruction fetch unit and load-store unit are passed to the PMP module for checking.
> The output of PMP check is used to gate the external request of the load-store unit.
> **This is because both writes and reads can have side-effects on MMIO devices connected to the data memory bus.**
> **The request coming from the instruction fetch unit are not gated by the PMP check, so integrators must choose carefully what to connect to the instruction fetch bus.**
> **Specifically, no devices that experience side-effects due to reading should be available on this bus.**
> In general, connecting memories to the instruction fetch bus should be safe.

**搜索模式**：`not gated by the PMP check`、`side-effects due to reading`

---

## F3 `fence` 是 NOP，`fence.i` 不是 —— 而且与 ICache 开关**无关**

**现象**：很多人以为"没开 ICache 就不用 `fence.i`"。**错。**

**后果**：

- 漏掉 `fence.i` → CPU 执行到**旧的**指令（stale instruction from prefetch buffer）
- 把 `fence` 当成"内存屏障能保证代码可见" → 不成立，`fence` 在 Ibex 里是 NOP

**硬规则**：

1. **"写内存 → 跳过去执行"** 这个动作，**无论 ICache 开不开，都必须 `fence.i`**。
   （因为 prefetch buffer 是默认存在的，见 F1）
2. **SPI 加载器 / 自修改代码 / 运行时补丁 / JIT** 都必须 `fence.i`。
3. `fence` 和 `fence.i` 是**两条不同的指令**，语义不要混。

**证据**：

```systemverilog
// rtl/ibex_decoder.sv:1206
// FENCE is treated as a NOP since all memory operations are already strictly ordered.

// rtl/ibex_decoder.sv:1212
// FENCE.I will flush the IF stage, prefetch buffer and ICache if present.
```

配套证据 `rtl/ibex_prefetch_buffer.sv:76-77`：

```systemverilog
// Note that the FENCE.I instruction relies on this flushing behaviour on branch. If it is
// altered the FENCE.I implementation may require changes.
```

**搜索模式**：`FENCE.I will flush the IF stage`、`relies on this flushing behaviour`

**对我们的影响**：这条直接决定 Q7 里"SPI 下载程序到 SRAM"的软件流程——**下载完必须 `fence.i` 再跳转**。

---

## F4 ★★ `ram_2p` 丢弃高位地址 —— 越界访问会**静默回绕**

**现象**：`ram_2p` 只用地址的中间若干位做索引，**高位直接丢弃**（还被显式命名成 `unused_*` 来满足 lint）。

**后果**：任何越界地址访问都会**悄悄命中 RAM 里某个错误位置**，读到垃圾或**覆盖掉别的数据**。
没有 err、没有断言、没有任何提示。这类 bug 会表现为"程序偶尔跑飞"。

**硬规则**：

1. **绝不能把未经解码的原始地址喂给 `ram_2p`。** 必须在外面做范围判断（地址高位比较），
   只有落在 RAM 范围内才发请求。
2. 我们的 SRAM（D3）是 **64 KB @ `0x0010_0000`**，而 simple_system 是 **1 MB @ `0x100000`**
   （`examples/simple_system/rtl/ibex_simple_system.sv:118-119`：`base=32'h100000`，`mask=~32'hFFFFF`）。
   两者**规模和对齐都不同**，所以我们必须**自己写范围比较并自行截取 RAM 内偏移**，
   不能像 simple_system 那样把地址原样透传给 `ram_2p`。
3. ★ 特别注意：simple_system 的**取指侧根本没有地址解码**（见 F5），
   所以它在 RAM 范围外取指也是静默回绕的。**我们不能照抄这一点。**

**证据**：

```systemverilog
// shared/rtl/ram_2p.sv:40-50
localparam int Aw = $clog2(Depth);

logic [Aw-1:0] a_addr_idx;
assign a_addr_idx = a_addr_i[Aw-1+2:2];
logic [31-Aw:0] unused_a_addr_parts;
assign unused_a_addr_parts = {a_addr_i[31:Aw+2], a_addr_i[1:0]};   // ← 高位被丢弃

logic [Aw-1:0] b_addr_idx;
assign b_addr_idx = b_addr_i[Aw-1+2:2];
logic [31-Aw:0] unused_b_addr_parts;
assign unused_b_addr_parts = {b_addr_i[31:Aw+2], b_addr_i[1:0]};   // ← 高位被丢弃
```

模块头也确认了这是**有意为之**的简化：`shared/rtl/ram_2p.sv:6-10`。

★ **`shared/rtl/ram_1p.sv` 有一模一样的问题**（所以我们的 ROM 也同样危险）：

```systemverilog
// shared/rtl/ram_1p.sv:27-32
localparam int Aw = $clog2(Depth);
logic [Aw-1:0] addr_idx;
assign addr_idx = addr_i[Aw-1+2:2];
logic [31-Aw:0] unused_addr_parts;
assign unused_addr_parts = {addr_i[31:Aw+2], addr_i[1:0]};   // ← 高位同样被丢弃
```

**搜索模式**：`unused_a_addr_parts`、`unused_b_addr_parts`、`unused_addr_parts`、`a_addr_idx`

**怎么验证**：写一个程序访问 SRAM 范围外的地址（比如 `0x0011_0000`），观察是否**没有异常**却读到了
SRAM 里的内容。如果读到了 → 你在**绕回**。

---

## F5 ★ err 必须"先拦后写"，且读/写 err 都以 `rvalid` 形式返回

**三条独立但相关的事实：**

### (a) 未映射地址返回 err，不 hang

```systemverilog
// shared/rtl/bus.sv:99
decode_err_resp <= host_sel_valid & !device_sel_valid;

// shared/rtl/bus.sv:125-126
host_rvalid_o[host] = device_rvalid_i[device_sel_resp] | decode_err_resp;
host_err_o[host]    = device_err_i[device_sel_resp]    | decode_err_resp;
```

→ **hole 访问会得到一个"带 err 的成功响应"**，Ibex 把它转成异常，而不是死等。

### (b) ★ simple_system 的取指侧**完全没有 err / 没有解码** —— 我们不能照抄

```systemverilog
// examples/simple_system/rtl/ibex_simple_system.sv:133-134
assign instr_gnt = instr_req;
assign instr_err = '0;        // ← 取指永远"成功"，永远不报错
```

并且取指**不经过 `bus`**，而是直连 RAM 的 B 口（`:335-341`）。

**后果**：取指越界 → 无异常 + 静默回绕（叠加 F4）。
**硬规则**：**我们的设计必须自己给取指侧加地址解码 + `instr_err`**，
这样越界取指会变成 **instruction access fault（mcause=1）**，可诊断。

### (c) PMP 错误与外部错误的语义**被刻意做成一致**

`doc/03_reference/pmp.rst:32-34` 原文：

> To maintain consistency with external errors, the instruction fetch unit and load-store unit progress with their request as if it was granted externally.
> The PMP error is registered and consumed by the core when the data would have been consumed.

**硬规则**（对我们实现外设最要紧的一条）：

- **被拒绝的 store 绝不会真正到达总线**（PMP 在 `load_store_unit` 的外部请求上做门控，`pmp.rst:25`）。
  → 所以**有副作用的写操作是安全的**：权限不够就写不进去。
- 但**响应仍然会来**（只是带 err），所以你不能用"没有响应"来判断被拒绝。

**证据汇总**：`shared/rtl/bus.sv:93,99,125-126,130`；`examples/simple_system/rtl/ibex_simple_system.sv:133-134,335-341`；`doc/03_reference/pmp.rst:22-34`

**搜索模式**：`decode_err_resp`、`assign instr_err`、`as if it was granted externally`

---

## F6 ★ 从设备必须"下一拍就响应"——`bus.sv` 的硬约束

**现象**：`shared/rtl/bus.sv` **不支持等待状态**。

**证据**：`shared/rtl/bus.sv:11-16` 的模块头：

```
 * This implementation doesn't handle the full bus protocol, but makes the
 * following simplifying assumptions.
 *
 * - All devices (slaves) must respond in the next cycle after the request.
 * - Host (master) arbitration is strictly priority based.
```

并且 `:8-9` 有一条**必须记住的免责声明**：

```
 * This module is designed for demo and simulation purposes, do not use it in
 * a real-world system.
```

**硬规则**：

1. 我们写的**每一个外设**都必须是**固定 1 拍延迟**：`req` 进来，下一拍出 `rvalid` + `rdata`。
   参考 `shared/rtl/ram_2p.sv:77-78`（`a_rvalid_o <= a_req_i`）和 simple_system 的 `timer` / `simulator_ctrl` 写法。
2. 慢外设（比如 SPI 传输）**不能靠拉长总线周期来实现** ——
   必须在外设内部用"忙标志 + 轮询"或者中断，总线上永远是 1 拍响应。
3. ★ **技术债登记**：`bus.sv` 明说不要用于真实系统。如果这个系统要流片/上 FPGA 长期运行，
   必须换成真正的总线（如 OpenTitan 的 TL-UL）。**现在先用它换速度，但 `DESIGN.md` 里要记这条债。**

**搜索模式**：`must respond in the next cycle`、`do not use it in a real-world system`

---

## F7 ★★ `wfi` 没有中断源 = **永久挂死**

**现象**：CPU 执行 `wfi` 后停止取指，**整个时钟被门控掉**。时钟只在**中断到来**时才重新打开。

**后果**：如果没有任何中断源，或者该中断被 `mie`/`mstatus` 屏蔽，**CPU 永远醒不过来**。
仿真是挂死（`--meminit` 跑不完），硬件是整机变砖。

**硬规则**：

1. **在接上中断源之前，不要在软件里用 `wfi`。** 我们目前 D5/D6 的 UART/Timer 就是为了提供中断源。
2. 中断必须走 `irq_timer_i` / `irq_external_i` / `irq_software_i` / `irq_fast_i`（**不是** 自己发明的引脚），
   而且要正确设置 `mie` / `mstatus.MIE` / `mip`。
3. ★ **NMI（`irq_nm_i`）绕过所有屏蔽**，是"救命"通道 —— 出问题时可以用它把 CPU 拉回来。

**证据**（整条睡眠链已逐行验证）：

```systemverilog
// rtl/ibex_decoder.sv:685-686   —— wfi 被译码
// 然后进控制器 FSM：FLUSH → WAIT_SLEEP → SLEEP

// rtl/ibex_controller.sv:598-621
WAIT_SLEEP: begin
  ctrl_busy_o = 1'b0;
  instr_req_o = 1'b0;
  halt_if     = 1'b1;
  flush_id    = 1'b1;
  ctrl_fsm_ns = SLEEP;
end

SLEEP: begin
  instr_req_o = 1'b0;
  halt_if     = 1'b1;
  flush_id    = 1'b1;

  // normal execution flow
  // in debug mode or single step mode we leave immediately (wfi=nop)
  if (irq_nm || irq_pending_i || debug_req_i || debug_mode_q || debug_single_step_i) begin
    ctrl_fsm_ns = FIRST_FETCH;          // ← 唯一的唤醒路径
  end else begin
    // Make sure clock remains disabled.
    ctrl_busy_o = 1'b0;                 // ← 时钟保持关闭
  end
end
```

时钟使能的**组合逻辑**（这是全链路最关键的一行）：

```systemverilog
// rtl/ibex_top.sv:314
assign clock_en = (core_busy_q != IbexMuBiOff) | debug_req_i | irq_pending | irq_nm_i;
// rtl/ibex_top.sv:331
assign core_sleep_o = ~clock_en;
```

→ 睡眠时 `core_busy_q` 为 off，**只有 `debug_req_i` / `irq_pending` / `irq_nm_i` 能把时钟拉回来**。

★ 还有一条设计约束（解释了为什么 `mip` 是组合逻辑）：

```systemverilog
// rtl/ibex_cs_registers.sv:406
// mip CSR is purely combinational - must be able to re-enable the clock upon WFI
```

**可用中断引脚**（`rtl/ibex_top.sv:117-122`）：
`irq_software_i`、`irq_timer_i`、`irq_external_i`、`irq_fast_i[14:0]`、`irq_nm_i`

**搜索模式**：`must be able to re-enable the clock upon WFI`、`Make sure clock remains disabled`、`clock_en`

**怎么复现**：写个只执行 `wfi` 的死循环程序，跑仿真 → 观察它永远不结束。
（simple_system 的 `timer` 外设就是为了避免这个；`examples/simple_system/README.md:9` 说明了它的存在理由。）

---

## F8 sleep 是**时钟门控**，不是断电；唤醒有竞态窗口

**现象**：`core_sleep_o` 驱动 `prim_clock_gating` 关掉**核的时钟**。
它**不是**复位，**不是**掉电 —— 寄存器文件、CSR、SRAM 全都保持。

**后果**：

- 不要指望"睡眠能清状态"；醒来时状态原封不动
- `core_sleep_o` 是**组合输出**，它是 `~clock_en`，随中断**立刻**变化
  → 外部若有"时钟门控 + 异步唤醒"逻辑，要小心毛刺/亚稳态

**硬规则**：

1. `core_sleep_o` 只用来做**时钟门控**；不要用它当复位或电源使能。
2. 唤醒后 CPU 从 **`mepc` 指向的 PC** 继续（因为 `wfi` 是被当作"已完成的指令"，
   中断处理完返回时 PC 是 `wfi` 的下一条）—— **不要**自己假设它从某个向量重启。
3. 外部时钟门控单元请用仓库里现成的 `prim_clock_gating` ——
   它**有两个工艺实现**（`vendor/lowrisc_ip/ip/prim_generic/rtl/prim_clock_gating.sv` 和
   `vendor/lowrisc_ip/ip/prim_xilinx/rtl/prim_clock_gating.sv`），
   由抽象 core `lowrisc:prim:clock_gating` 按目标解析（`ibex_core.core:12` 就是它的引用）。
   **不要自己写 latch**；也**不要以为它在 `shared/rtl/` 里**（那里只有 `bus.sv`/`ram_1p.sv`/`ram_2p.sv`/`timer.sv` 等 6 个文件）。

**证据**：`rtl/ibex_core.sv:521`（`core_sleep_o = ~core_busy_o` 的传递）、
`rtl/ibex_top.sv:303-314`（`clock_en` 的产生，含 SecureIbex 分支 `:303-312`）、`:331`（`core_sleep_o`）。

**搜索模式**：`core_sleep_o`、`prim_clock_gating`、`u_prim_core_busy_flop`

---

## F9 ★★ PMP 有四个非常隐蔽的坑（附**正确编程顺序**）

### 坑 1：写 `pmpcfg` 可能被**静默忽略**（不报错！）

```systemverilog
// rtl/ibex_cs_registers.sv:1421-1424
assign pmp_cfg_we[i] = csr_we_int &
                       ~pmp_cfg_locked[i] &          // 被 lock 挡住
                       ~pmp_cfg_wr_suppress[i] &     // 被 MSECCFG.MML 挡住
                       (csr_addr == (CSR_OFF_PMP_CFG + (i[11:0] >> 2)));
```

```systemverilog
// rtl/ibex_cs_registers.sv:1461
assign pmp_cfg_locked[i] = pmp_cfg[i].lock & ~pmp_mseccfg_q.rlb;
// rtl/ibex_cs_registers.sv:1465-1467
assign pmp_cfg_wr_suppress[i] = pmp_mseccfg_q.mml & ~pmp_mseccfg_q.rlb &
                                is_mml_m_exec_cfg(pmp_cfg_wdata[i]);
```

→ **lock 一旦置位，除非 `MSECCFG.RLB` 被设置，写操作无声失败**。软件必须**读回验证**。

### 坑 2：★ TOR 模式下**必须从高索引往低索引写 `pmpaddr`**

```systemverilog
// rtl/ibex_cs_registers.sv:1472-1475
if (i < PMPNumRegions - 1) begin : g_lower
  assign pmp_addr_we[i] = csr_we_int & ~pmp_cfg_locked[i] &
                          (~pmp_cfg_locked[i+1] | (pmp_cfg[i+1].mode != PMP_MODE_TOR)) &  // ← 依赖 i+1！
                          (csr_addr == (CSR_OFF_PMP_ADDR + i[11:0]));
```

→ 区域 `i` 的 `pmpaddr` 可写性**取决于区域 `i+1`**（若 `i+1` 已锁定且是 TOR，则 `i` 写不进去）。

**硬规则**：配置 TOR 区域时，**先写 `pmpaddr[N-1]` … 最后写 `pmpaddr[0]`，最后才置 `pmpcfg`**。

### 坑 3：★ `pmpaddr` 的**读回值不等于写进去的值**

```systemverilog
// rtl/ibex_cs_registers.sv:1383-1407（节选）
if (PMPGranularity == 0) begin
  assign pmp_addr_rdata[i] = pmp_addr[i];                    // G=0：原值
end else if (PMPGranularity == 1) begin
  if (mode == OFF || mode == TOR) pmp_addr_rdata[i][0] = '0; // G=1：TOR/OFF 时 bit0 读 0
end else begin
  pmp_addr_rdata[i] = {pmp_addr[i], {G-1{1'b1}}};            // G>=2：NAPOT 时低 G-2 位读 1
  if (mode == OFF || mode == TOR) pmp_addr_rdata[i][G-1:0] = '0;
end
```

→ **`pmpaddr` 的读-改-写（RMW）会出错。** 别做 RMW；直接写目标值，并理解读回是掩码后的。

### 坑 4：`NA4` 在 `PMPGranularity > 0` 时**写不进去**（自动变成 OFF）

```systemverilog
// rtl/ibex_cs_registers.sv:1428-1436
// NA4 mode is not selectable when G > 0, mode is treated as OFF
2'b10 : pmp_cfg_wdata[i].mode = (PMPGranularity == 0) ? PMP_MODE_NA4 : PMP_MODE_OFF;
```

另外 `:1440-1443` —— `MSECCFG.MML` 未置位时，`W=1, R=0` 是保留组合，**硬件强制把 W 清零**。

### 参考数据

| 项 | 值 | 出处 |
|---|---|---|
| PMP 模式编码 | `OFF=2'b00`、`TOR=2'b01`、`NA4=2'b10`、`NAPOT=2'b11` | `rtl/ibex_pkg.sv:413-416` |
| `pmp_cfg_t` 字段顺序 | `{lock, 2'b00, mode, exec, write, read}` | `rtl/ibex_pkg.sv:425`、`rtl/ibex_cs_registers.sv:1379-1380` |
| 复位值 | 所有区域 `lock=0, mode=OFF` | `rtl/ibex_pkg.sv:741-742` |
| 未实现的区域读 0 | 所以 `PMPNumRegions=4` 时 `pmpcfg1` 读 0 | `rtl/ibex_cs_registers.sv:1409-1412` |
| 送入 PMP 模块的地址 | `{pmp_addr_rdata[i], 2'b00}`（**掩码后的值**） | `rtl/ibex_cs_registers.sv:1497` |
| 访问通道数 | 2（i-side + d-side） | `rtl/ibex_pmp.sv:14` |

**搜索模式**：`pmp_cfg_wr_suppress`、`pmp_addr_we`、`NA4 mode is not selectable`、`is_mml_m_exec_cfg`

**对我们的影响**：D8 选了 `PMPEnable=1` / `PMPNumRegions=4` / `PMPGranularity=0`。
`Granularity=0` 意味着 **4 字节粒度、`NA4` 可用**（撞不到坑 4），
但**坑 1/2/3 全都还在**，软件启动代码里必须按正确顺序写 PMP。

---

## F10 对齐约束：取指 4 字节、boot 地址 256 字节

**现象**：Ibex 对**取指地址**和**boot 地址**有硬性对齐要求，且**自带断言**。

**后果**：违反会导致断言失败（仿真）或未定义行为（硬件）。

**硬规则**：

1. **`instr_addr_o[1:0]` 永远是 `2'b00`** —— 所以取指通路上看到的地址永远是字对齐的，
   但**取回来的 32 bit 里可能含两条 16 bit 压缩指令**（见 F3 关于 `rdata[1]` 的处理）。
2. **`boot_addr` 必须 256 字节对齐**（低 8 位为 0）。我们选 `0x0`，**满足**。
3. ★ 注意 `rtl/ibex_if_stage.sv:424` 提到：**取指错误可能来自"当前 PC"或"非对齐的下一条 PC"**
   （对应 `instr_fetch_err_plus2_o`）。所以取指 err 的处理要区分这两种情况。

**证据**：

```systemverilog
// rtl/ibex_if_stage.sv:931-932
// Boot address must be aligned to 256 bytes.
`ASSERT(IbexBootAddrUnaligned, boot_addr_i[7:0] == 8'h00)

// rtl/ibex_if_stage.sv:937-938
// Address must be word aligned when request is sent.
`ASSERT(IbexInstrAddrUnaligned, instr_req_o |-> (instr_addr_o[1:0] == 2'b00))
```

**搜索模式**：`IbexBootAddrUnaligned`、`IbexInstrAddrUnaligned`、`instr_fetch_err_plus2_o`

---

## F11 ROM 只有读口：启动 ROM 里的内容**必须能在复位后直接取到**

**现象**：simple_system 用同一个 `ram_2p` 当"ROM"，但它的 **B 口（取指口）的写信号是硬接 0 的**：

```systemverilog
// examples/simple_system/rtl/ibex_simple_system.sv:335-337
.b_req_i     (instr_req),
.b_we_i      (1'b0),        // ← B 口永远不写
.b_be_i      (4'b0),
```

**后果**：

- 取指口**只读**。我们的 boot ROM 也必须只读。
- ★ 更关键的是：**CPU 复位后第一条指令从 `boot_addr` 取**，此时**没有任何软件参与**。
  所以 ROM 必须在**上电瞬间就已经有内容**（仿真靠 `--meminit`，硬件靠 ROM 硬连线/掩膜或 FPGA BRAM 初始化）。

**硬规则**：

1. **Boot ROM 里的向量表、复位入口、常量表必须是"预置内容"**，不能依赖任何运行时初始化。
2. 我们在 `0x0` 放 32 KB ROM，`boot_addr = 0`，所以 CPU 复位后从 `0x0` 开始取指 ——
   **`0x0` 处必须是一条有效指令**（通常是 `j reset_handler`），
   并且**异常向量也在这块 ROM 里**（Ibex 的向量表基址 = `boot_addr`）。
3. ★★ **重要修正：不需要从零写 `rom_1p.sv`。** 仓库里**已经有**两样现成的东西：
   - `shared/rtl/ram_1p.sv` —— 单端口 RAM 封装（`shared/sim_shared.core:14` 已挂进清单）
   - **`lowrisc:prim_generic:rom` / `lowrisc:prim_xilinx:rom`** —— 工艺映射的 ROM core
     （`vendor/lowrisc_ip/ip/prim_generic/prim_generic_rom.core`、`vendor/lowrisc_ip/ip/prim_xilinx/prim_xilinx_rom.core`），
     另有 `vendor/lowrisc_ip/ip/prim/prim_rom_adv.core`

4. ★ **但端口数仍然是个真问题**：Ibex 是**取指/数据分离的端口**
   （`instr_*` 与 `data_*`，见 `rtl/ibex_top.sv:83-105`），
   **同一拍可能既取指又读数据**。单端口 ROM 会结构冲突。

**搜索模式**：`b_we_i      (1'b0)`、`Ram`、`lowrisc:prim_generic:rom`

### ★★ 结论：修正蓝图

原蓝图打算"新写一个 `rom_1p.sv`（32 KB，单端口）"。核对现状后应改为：

| 方案 | 做法 | 评价 |
|---|---|---|
| **A（推荐）** | 直接复用 `shared/rtl/ram_2p.sv` 当 ROM，**B 口接取指、A 口接数据，`b_we_i`/`a_we_i` 接 0**，靠 `MemInitFile` 预置内容 | **和 simple_system 完全同构**（`:319-342`），零新代码、零新端口冲突。代价是"ROM"其实可写（软件写它不会被拦），需要靠 PMP 或地址解码兜住 |
| **B** | 用 `lowrisc:prim_generic:rom` + 自己写一层薄封装 | 语义上真是 ROM（只读），但要多一层封装 + 新 `.core` 条目 |
| **C** | 只用 `shared/rtl/ram_1p.sv` 单端口 | ❌ **会冲突**：取指和数据同拍访问会丢请求 |

→ **需要重新决策**（已记入 `README.md` 决策台账的待办）。
**[建议]** 先用 **A** 跑通全链路，再考虑是否升级到 B。

---

## F12 Debug 模式下 `wfi` 是 NOP —— 以及一批"零成本"的上游能力

**现象**：`wfi` 在 **debug mode 或 single-step** 下**不进入睡眠**，直接当 NOP 放行。

**证据**：

```systemverilog
// rtl/ibex_controller.sv:613-615
// normal execution flow
// in debug mode or single step mode we leave immediately (wfi=nop)
if (irq_nm || irq_pending_i || debug_req_i || debug_mode_q || debug_single_step_i) begin
```

**硬规则 / 提示**：

1. **"`wfi` 之后程序卡住"可以先用 debug/single-step 排掉** —— 如果在单步下能过，
   说明问题在睡眠/唤醒链，不在 `wfi` 本身。这是一个很好用的**调试技巧**。
2. ★ Debug 能力是**上游白送的**：只要接上 `debug_req_i` 并配好 `DmBaseAddr` / `DmHaltAddr` /
   `DmExceptionAddr`（`rtl/ibex_top.sv:48-51`），就得到符合 **RISC-V Debug Spec** 的调试能力。
   我们**不需要**为它写 RTL。
3. ★ **NMI 被强制跳到 `0x7C`**（`rtl/ibex_if_stage.sv:216-219`）——
   这是一个独立于常规异常向量的入口，做"看门狗救命"很合适。

**可诊断性参考**（异常 cause 编码，`rtl/ibex_pkg.sv` 中的 `exc_cause_t`，`:330-355`）：

| cause | 枚举常量 | 我们最可能遇到的场景 |
|---|---|---|
| 0 | `ExcCauseInsnAddrMisa` | 跳到非对齐地址 |
| 1 | `ExcCauseInstrAccessFault` | **取指越界 → 我们加的 `instr_err`（见 F5）** |
| 2 | `ExcCauseIllegalInsn` | 未实现的指令、**访问不存在的 CSR** |
| 3 | `ExcCauseBreakpoint` | 断点 / `ebreak` |
| 4 | `ExcCauseLoadAddrMisaligned` | 非对齐 load |
| 5 | `ExcCauseLoadAccessFault` | 读未映射地址（hole，见 F5） |
| 6 | `ExcCauseStoreAddrMisaligned` | 非对齐 store |
| 7 | `ExcCauseStoreAccessFault` | 写未映射地址；**PMP 拒绝的 store（见 F9）** |
| 8 / 11 | `ExcCauseEcallUMode` / `ExcCauseEcallMMode` | `ecall`（注意 **U 模式是 8，M 模式是 11**，不是连号！） |
| 31 | `ExcCauseIrqNm` | NMI（`irq_ext=1`） |

> ★ 这条表是我们**唯一的"症状 → 病因"映射工具**。有了它，
> "程序跑飞"才能变成"`mcause=7, mtval=0x0020_1004` → 你往 UART 的只读寄存器写了东西"。

**搜索模式**：`wfi=nop`、`exc_cause_t`、`ExcCauseStoreAccessFault`、`DmBaseAddr`

---

## F13 `make lint-core-tracing` 引用的是**过期 core 名**，必失败

**现象**：`make lint-core-tracing` 报 FuseSoC 找不到 `lowrisc:ibex:ibex_core_tracing`。
**后果**：让人误以为自己的 RTL 有问题。实际是这个 make 目标自身引用了一个**不存在的 core**，与你的改动无关。
**硬规则**：不要用 `make lint-core-tracing`。需要 lint 带 tracing 的核时，直接用真实 core 名：

```bash
fusesoc --cores-root . run --target=lint --tool=verilator lowrisc:ibex:ibex_top_tracing
```

**证据**：
- `Makefile:62` 写的是 `lowrisc:ibex:ibex_core_tracing`；
- 全仓库**没有任何** `.core` 声明该名字（逐一核对 32 个 `.core` 的 `name:` 字段）；真实名字是 `ibex_top_tracing.core:5` 的 `lowrisc:ibex:ibex_top_tracing:0.1`；
- 与 E1 里 `src_files.yml` 指向不存在的 `rtl/ibex_core_tracing.sv` 是**同一处历史改名的遗留**（`ibex_core_tracing` → `ibex_top_tracing`）。

**搜索模式**：`ibex_core_tracing`、`ibex_top_tracing`
**怎么验证**：`fusesoc --cores-root . run --target=lint lowrisc:ibex:ibex_core_tracing` → 报 core 不存在；换成 `lowrisc:ibex:ibex_top_tracing` → 正常开始 lint。
**状态**：✅ **已确认**（2026-10-15 复核：同步到 `96a34a56` 后 `Makefile:62` **仍然**写着 `lowrisc:ibex:ibex_core_tracing`；上游这 7 个提交未触及 `Makefile` —— 实测 `git diff --name-only af456e25 96a34a56` 中无 `Makefile`）。**该 target 仍是坏的，不要用。**

---

## F14 `ibex_configs.yaml` 是**全键强制**的 —— 新参数不能只加给 `tide` 配置

**现象**：想给 TIDE 加一个参数（如 `TIDE_EN`），并"只在新加的 `tide` 配置里给值、不动既有配置"——按 `util/ibex_config.py` 的**实际逻辑做不到**。`Config.known_fields`（`:23-43`）是一份**硬编码的 19 项白名单**，而 `Config.__init__` 对**每一个**配置都强制校验键集合**完全相等**：

- `:52-55` —— 多出未知键 → `ValueError: unknown keys`
- `:57-60` —— 缺少已知键 → `ValueError: missing keys`

**后果**：一旦把 `TIDE_EN` 写进 `known_fields`，`ibex_configs.yaml` 里**所有 8 个配置都必须显式写出 `TIDE_EN`**，否则 `util/ibex_config.py small fusesoc_opts` 直接抛异常 → `Makefile:7` 的 `$(shell ...)` 失败 → **所有使用该变量的 make 目标全崩**（含 CI 的 6 个配置）。这会直接违反 D10「不改动已有配置」。

**硬规则**：**不要把 `TIDE_EN`（及任何 TIDE 参数）加进 `ibex_configs.yaml`，也不要动 `util/ibex_config.py`。** 照抄 `FPGA_XILINX` 的既有先例：

1. 在 `.core` 的 `parameters:` 里声明并给 `default`（`ibex_top.core:56-60` 就是模板：`default: false` + `paramtype: vlogdefine`）；
2. **不给** yaml 加键 —— `TIDE_EN` 默认取 `.core` 的 default（=0），**既有 8 个配置与 6 个 CI 全部零改动**；
3. 需要打开时在**命令行**覆盖：`fusesoc ... --TIDE_EN=1`，或给 Makefile 加 `TIDE_EN ?= 0` 拼进 `FUSESOC_CONFIG_OPTS`。

**证据**：

- `util/ibex_config.py:23-43` `known_fields`（19 项硬编码白名单）；`:49-60` 双向键校验；
- `util/ibex_config.py:60` 还有个**上游 bug**：`missing keys` 分支打印的是 `extra_keys`（`f'missing keys: {extra_keys}'`）—— 真触发时**报错信息会误导你去找"多出的键"**；
- `ibex_configs.yaml` 共 **8 个**命名配置（`:19/41/66/88/116/139/161/190`），其中 **6 个**进 per-config CI（`.github/workflows/ci.yml:114/118/122/126/130/134`）；
- 实测：`ibex_configs.yaml` 的 19 个唯一键**全部**声明在 `ibex_top.core` 的 `parameters:` 里（两集合包含关系已逐项核对通过）；
- **反例先例**：`FPGA_XILINX` **只在** `ibex_top.core:56-60` 声明（`default: false`），**不出现在 `ibex_configs.yaml` 里** —— 证明"参数由 `.core` 默认、不经 yaml"这条路是上游自己在走的；
- `Makefile:7` `FUSESOC_CONFIG_OPTS = $(shell ./util/ibex_config.py $(IBEX_CONFIG) fusesoc_opts)` —— yaml 解析失败会污染**所有**用该变量的目标。

**搜索模式**：`known_fields`、`missing keys`、`extra_keys`、`FPGA_XILINX`、`FUSESOC_CONFIG_OPTS`
**怎么验证**：`./util/ibex_config.py small fusesoc_opts` 正常输出 `--BaseIsa=... --RV32M=...`；临时给 `small` 删掉一行（如 `RV32E`）再跑，会抛 `missing keys:` 但打印的是多出键集合（即 `:60` 的 bug），验证完记得还原。
**对我们影响**：`TIDE_EN` 的开关**必须**走「`.core` 参数 + 命令行覆盖」，**不能**走命名配置。推论：**`tide` 命名配置并非必需** —— 只有当 TIDE 需要固定一套与既有不同的参数组合时才新增它（那时它同样必须给全那 19 个既有键）。

**状态**：✅ 已确认（2026-10-15，同步到 `96a34a56` 后逐项核对）

---

## F15 TIDE 同步错误 flush 后必须复位 ID FSM

**现象**：QTRIG 在入队点收到 TQ_LATE 后先进入 MULTI_CYCLE，controller 随即以精确异常 flush ID；若 FSM 保持 MULTI_CYCLE，异常返回后 id_in_ready 与 FSM 状态不一致。
**后果**：IbexMoveToFirstCycleWhenIdReady 断言失败，TIDE 错误处理路径无法继续。
**硬规则**：TIDE_EN && flush_id 时必须把 ID FSM 复位到 FIRST_CYCLE；TIDE_EN=0 路径不得改变。
**证据**：rtl/ibex_id_stage.sv:1185；small 配置 out_small/run/tests/tide_qop_smoke.final/rtl_sim.log。
**搜索模式**：synchronous TIDE enqueue error、id_fsm_q <= FIRST_CYCLE。
**怎么验证**：small 配置 + 真实 DD 跑 tide_qop_smoke，覆盖 QTRIG C3 迟到。


## 汇总：改代码前先扫一眼这张表

| # | 陷阱 | 一句话 | 严重度 |
|---|---|---|---|
| F1 | prefetch buffer 默认存在 | 取指是投机的 | ★★ |
| F2 | 取指总线不闸 PMP | **副作用设备只能挂数据侧** | ★★★ |
| F3 | `fence.i` 与 ICache 无关 | 写内存后必须 `fence.i` | ★★★ |
| F4 | `ram_2p` 丢弃高位地址 | **越界静默回绕** | ★★★ |
| F5 | 取指侧无 err | **必须自己加取指解码 + `instr_err`** | ★★★ |
| F6 | `bus.sv` 要 1 拍响应 | 慢外设必须内部排队 | ★★ |
| F7 | `wfi` 无中断源会挂死 | 先接中断再用 `wfi` | ★★★ |
| F8 | sleep 是时钟门控 | 别当复位/掉电用 | ★★ |
| F9 | PMP 四个隐蔽坑 | **TOR 从高到低写、别做 `pmpaddr` RMW** | ★★★ |
| F10 | 对齐约束 | 取指 4B、boot 256B | ★ |
| F11 | ROM 只读且需预置 | **修正：单端口 ROM 可能有取指/数据冲突** | ★★★ |
| F12 | `wfi` 在 debug 下是 NOP | 排障利器 + 白送的调试能力 | ★ |
| F13 | `make lint-core-tracing` 的 core 名过期 | **改用 `lowrisc:ibex:ibex_top_tracing`** | ★ |
| F14 | `ibex_configs.yaml` 全键强制 | `TIDE_EN` **走 `.core` 参数，别加进 yaml** | ★★★ |
| F15 | TIDE 同步错误 flush 后 FSM 未复位 | TIDE_EN && flush_id 时回 FIRST_CYCLE | ★★★ |

### 新增本文条目的模板

```markdown
## F<n> <标题>

**现象**：
**后果**：
**硬规则**：
**证据**：    ← 必须有 `文件:行号`
**搜索模式**： ← 便于上游同步后重新定位
**怎么验证**：
```
