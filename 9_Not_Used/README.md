# Not used by the team build

Kept for reference only. Nothing here is added to the Vivado project.

| Folder | What | Why it is not used |
|---|---|---|
| `old_top_level/` | Matthew's `My_Top_Module.v` and `Basys3_Master.xdc` | replaced by `0_Integrated_Top/Integration_Top.v` and `Integration.xdc` |
| `old_duplicates/` | `Oled_Display.v`, `slower_clk.v` from the original template | the same modules as Matthew's copies in `1_Shared_Modules/` (two copies of a module clash) |
| `mouse/` | `Mouse_Control.vhd`, `Ps2Interface.vhd` | the mouse was removed from the project (17 Oct) |
| `unused_snippets/` | Matthew's code snippets that nothing instantiates yet | move one back into `5_Matthew_Display/` when it is used |
| `old_vivado_project/` | `TradingSimProject.xpr`, `dfx_runtime.txt` | the project is now built by `0_Integrated_Top/create_integration_project.tcl` |
