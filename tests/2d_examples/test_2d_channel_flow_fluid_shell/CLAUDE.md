# AI Assistant Instructions for SPH Channel Flow Project
在执行任何含中文输出的命令或读写文件时，必须强制指定并全流程使用UTF-8编码以杜绝乱码。
## Quick Context
- **Project**: 2D Poiseuille flow simulation (SPHinXsys framework)
- **Main file**: `channel_flow_shell.cpp` (362 lines)
- **Physical model**: Re=100, periodic boundary, shell walls

## Working Rules

### Code Modification Strategy
**ALWAYS use `rigorous-code-modifier` agent for code changes**
```
Task(
  subagent_type="rigorous-code-modifier",
  description="brief description",
  prompt="detailed task with file names and requirements"
)
```

### Task Management
- Use `TodoWrite` for tasks with >3 steps
- Mark tasks `in_progress` before starting
- Complete tasks immediately after finishing

### Parameter Dependencies (Critical!)
When modifying these parameters, check cascading effects:

| Parameter | Location | Auto-affects | Manual checks needed |
|-----------|----------|--------------|---------------------|
| `Re` | Line 21 | `mu_f` (22) | `fx` (207) - verify formula |
| `DL`, `DH` | Lines 13-14 | None | `WaterBlock` (33-35), observation points (77-109) |
| `U_f` | Line 19 | None | `c_f` (20), `fx` (207) |
| `resolution_ref` | Line 359 | Particle count | Computation time (~$4^d$ scaling) |

### Documentation Updates (Mandatory)
After code changes, update:
1. **CHANGELOG.md** - always (rigorous-code-modifier generates this)
2. **索引.md** - if line numbers or function locations change
3. **README.md** - if user-facing parameters or workflow change

## Quick Reference

### Common Tasks
```
Modify Reynolds number:
→ Edit Line 21 → verify mu_f (22) auto-updates → check fx (207)

Change geometry:
→ Edit Lines 13-14 → update WaterBlock (33-35) → adjust observation points (77-109)

Change resolution:
→ Edit Line 359 → warn about 4x computation time increase

Extend simulation time:
→ Edit Line 250 (end_time) → adjust Line 251 (output_interval) to control file count
```

### File Structure
```
📄 channel_flow_shell.cpp  - Main simulation
📄 CMakeLists.txt          - Build config
🔧 build.bat               - Compile & run script
📊 process_velocity_data.m - Data extraction
📊 visualize_velocity_field.m - Animation
📚 README.md               - User documentation
📚 CHANGELOG.md            - Version history
📚 索引.md                 - Code mapping (detailed, in Chinese)
📚 SPHinXsys_Workflow_Cookbook.md - Workflow guide
```

### Physical Context
- **Theoretical Umax**: 1.5
- **Numerical Umax**: ~1.55 (3.3% overshoot, expected due to transport velocity correction)
- **Convergence time**: 30-50 seconds
- **Validation**: 72 observation points, ±5% tolerance

## Detailed Documentation
For comprehensive code mapping and explanations, refer to **索引.md** (in Chinese, very detailed).

This file (`CLAUDE.md`) focuses on **AI workflow rules**, not code explanations.
