# M6 纯 RTL 导出报告

## 交付路径

`tide_cd/export/tide_cd_rtl/`

## 内容约束

- 只包含 `.sv`、`.svh` 源码/编译必需头文件。
- `EXPORT_FILES.f` 为按包依赖排序的编译文件清单。
- `MANIFEST.sha256` 为导出文件校验清单。
- 不包含 FuseSoC `.core`、Makefile、Python/Make 脚本、仿真日志或构建产物。
- `TIDE_EN` 仍是 `tide_cd_top`/`ibex_tide_pkg` 的综合期参数，默认值保留。

## 验证

在导出目录内执行：

```bash
synopsys-cli vcs -full64 -sverilog -timescale=1ns/1ps \
  -Mdir=/tmp/tide_cd_export_csrc \
  -f EXPORT_FILES.f -top tide_cd_top \
  -o /tmp/tide_cd_export_simv
```

结果：VCS elaboration/link PASS，无端口宽度错误；导出包仅依赖清单内源码与 include 目录。