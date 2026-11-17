# C 盘扫描报告（只读阶段）

- 生成时间：{{GENERATED_AT}}
- 计算机：{{COMPUTER}}｜用户：{{USER}}｜管理员：{{ELEVATED}}
- 系统：{{OS}}
- 说明：本阶段只读取元数据，未删除任何文件。

## 一、磁盘概况

| 项目 | 数值 |
|---|---|
| C 盘总容量 | {{DISK_TOTAL_GB}} GB |
| 已用空间 | {{DISK_USED_GB}} GB |
| 剩余空间 | {{DISK_FREE_GB}} GB |
| 使用率 | {{DISK_USED_PCT}}% |

## 二、一级目录占用

| 目录 | 占用 | 文件数 |
|---|---|---|
{{TOP_DIR_ROWS}}

## 三、根目录大文件

| 文件 | 大小 |
|---|---|
{{ROOT_FILE_ROWS}}

## 四、垃圾文件分级统计

### A 级：可以安全清理（合计 {{TOTAL_A_GB}} GB）

| 项目 | 大小 | 文件数 | 风险 |
|---|---|---|---|
{{LEVEL_A_ROWS}}

### B 级：需要用户确认（合计 {{TOTAL_B_GB}} GB）

| 项目 | 大小 | 文件数 | 风险 |
|---|---|---|---|
{{LEVEL_B_ROWS}}

### C 级：禁止删除（合计 {{TOTAL_C_GB}} GB）

| 项目 | 大小 | 文件数 | 风险 |
|---|---|---|---|
{{LEVEL_C_ROWS}}

## 五、备注

{{NOTES}}

## 六、下一步

1. 审阅 A/B 分级，确认要清理的范围；
2. 运行 `clean-c-drive.ps1 -Mode DryRun` 生成精确清理清单；
3. 用户确认后，再运行 `-Mode Execute -Yes` 执行删除；
4. 运行 `verify-cleanup.ps1` 生成前后对比报告。
