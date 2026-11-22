# 📚 Zython Developer Documentation & Architecture Portal

Welcome to the internal engineering documentation and architectural reference for **Zython** — the high-performance Python runtime engineered from scratch in pure Zig.

---

## 🧭 Navigation & Document Index

| Document | Purpose | Key Topics Covered |
|---|---|---|
| [**1. Baseline Architecture (v0.1.0)**](file:///c:/Users/DELL/Downloads/zython/developer_doc/01_baseline_architecture_v0.1.0.md) | Initial Architecture & Discovery | • Recursive AST tree-walking interpreter<br>• `fast_slots: [8]` CPU cache design<br>• Peephole loop reductions ($O(1)$)<br>• Pros, cons, bottlenecks & limitations |
| [**2. Phase 2 Architecture (v0.2.0)**](file:///c:/Users/DELL/Downloads/zython/developer_doc/02_current_architecture_v0.2.0.md) | Optimized Architecture & Bugfixes | • Monomorphic inline caching (MIC)<br>• Expanded fast slots (32 locals, 16 attributes)<br>• Zero-allocation method dispatch<br>• Slicing, f-strings, exception matching<br>• Initial benchmark baselines vs CPython 3.14 |
| [**3. Future Architecture & JIT Blueprint**](file:///c:/Users/DELL/Downloads/zython/developer_doc/03_future_architecture_v0.3.0_to_v0.5.0.md) | Blueprint to 50× – 100× Speedup | • Phase 3 Bytecode VM (**Delivered**)<br>• Phase 4 Adaptive Specialization (**Delivered**)<br>• Phase 5 Copy-and-Patch Native JIT Compiler (**Target 50×–100×**)<br>• NaN-boxing 64-bit word value model |
| [**4. Master Achievements & Bug Audit**](file:///c:/Users/DELL/Downloads/zython/developer_doc/achievements.md) | Comprehensive Audit & Fix Records | • BUG-01 through BUG-08 root causes & fixes<br>• Phase 3 Bytecode VM achievements<br>• Phase 4 Quickening & PIC achievements<br>• Verified before-and-after benchmark outputs |
| [**5. Master Roadmap & Completion Matrix**](file:///c:/Users/DELL/Downloads/zython/developer_doc/roadmap.md) | Execution Plan & Milestones | • Phases 1, 2, 3, 4 marked 100% COMPLETE<br>• Phase 5 Copy-and-Patch JIT specification<br>• Full language feature compatibility matrix |

---

## ⚡ Architecture Evolution Overview

```mermaid
flowchart LR
    subgraph Phase1 ["v0.1.0: Baseline AST (✅)"]
        A1["Source (.py)"] --> B1["Lexer / Parser"]
        B1 --> C1["AST Tree (*Expr)"]
        C1 --> D1["Tree-Walk Interpreter"]
        D1 --> E1["8-Slot Env Cache"]
    end

    subgraph Phase2 ["v0.2.0: Optimized AST & MIC (✅)"]
        A2["Source (.py)"] --> B2["F-String / Tuple Parser"]
        B2 --> C2["Annotated AST"]
        C2 --> D2["Monomorphic Inline Cache"]
        D2 --> E2["32 Fast Slots + 16 OOP Slots"]
        E2 --> F2["8 Bugs Resolved"]
    end

    subgraph Phase3 ["v0.3.0: Bytecode VM (✅)"]
        A3["Source (.py)"] --> B3["AST-to-Bytecode Compiler"]
        B3 --> C3["Packed 32-bit Instructions"]
        C3 --> D3["Linear Stack VM (16k stack)"]
        D3 --> E3["Direct CallFrame Windows"]
    end

    subgraph Phase4 ["v0.4.0: Adaptive Specialization (✅ Current)"]
        A4["Bytecode Stream"] --> B4["Self-Modifying Quickening"]
        B4 --> C4["Specialized ALU (int/float)"]
        C4 --> D4["Superinstructions (slots 0..3)"]
        D4 --> E4["Unboxed Range & PIC (attr cache)"]
        E4 --> F4["1.35x - 1.79x Faster Loops"]
    end

    subgraph Phase5 ["v0.5.0: Native JIT (⏳ Target 50x+)"]
        A5["Hot Bytecode Chunks"] --> B5["Copy-and-Patch JIT Compiler"]
        B5 --> C5["Binary Machine Stencils"]
        C5 --> D5["Runtime Relocation Linker"]
        D5 --> E5["x86_64 / ARM64 Machine Code"]
    end

    Phase1 --> Phase2
    Phase2 --> Phase3
    Phase3 --> Phase4
    Phase4 --> Phase5
```

---

## 🎨 Official Brand & Benchmark Color Palette

When visualizing Zython against CPython in comparative benchmarks, the following color specifications are standardized across all charts and reporting assets:

* ⚡ **Zython Color**: `Zig Golden Amber` (`#F7A41D` / `#F6991A`)  
  *Reflects the native Zig language emblem, energy, and zero-allocation execution.*
* 🐍 **CPython Color**: `Python Ocean Blue` (`#3776AB`) / `Python Canary Yellow` (`#FFD43B`)  
  *Reflects the official PSF brand palette.*
