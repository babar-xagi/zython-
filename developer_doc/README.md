# 📚 Zython Developer Documentation & Architecture Portal

Welcome to the internal engineering documentation and architectural reference for **Zython** — the high-performance Python runtime engineered from scratch in pure Zig.

---

## 🧭 Navigation & Document Index

| Document | Purpose | Key Topics Covered |
|---|---|---|
| [**1. Baseline Architecture (v0.1.0)**](file:///c:/Users/DELL/Downloads/zython/developer_doc/01_baseline_architecture_v0.1.0.md) | Initial Architecture & Discovery | • Recursive AST tree-walking interpreter<br>• `fast_slots: [8]` CPU cache design<br>• Peephole loop reductions ($O(1)$)<br>• Pros, cons, bottlenecks & limitations |
| [**2. Current Architecture (v0.2.0)**](file:///c:/Users/DELL/Downloads/zython/developer_doc/02_current_architecture_v0.2.0.md) | Optimized Architecture & Bugfixes | • Monomorphic inline caching (MIC)<br>• Expanded fast slots (32 locals, 16 attributes)<br>• Zero-allocation method dispatch<br>• Slicing, f-strings, exception matching<br>• Current empirical benchmarks vs CPython 3.14 |
| [**3. Future Architecture (v0.3.0 – v0.5.0)**](file:///c:/Users/DELL/Downloads/zython/developer_doc/03_future_architecture_v0.3.0_to_v0.5.0.md) | Blueprint to 50× – 100× Speedup | • NaN-boxing 64-bit word value model<br>• Flat linear bytecode VM + threaded dispatch<br>• Polymorphic inline caching (PIC)<br>• Copy-and-Patch Native JIT compiler<br>• Escape analysis & register allocation |
| [**4. Achievements & Bug Resolution Log**](file:///c:/Users/DELL/Downloads/zython/developer_doc/achievements.md) | Comprehensive Audit & Fix Records | • BUG-01 through BUG-08 root causes & fixes<br>• List comprehension & tuple unpacking<br>• Verified before-and-after test outputs<br>• Performance milestones achieved |
| [**5. Master Roadmap & Completion Matrix**](file:///c:/Users/DELL/Downloads/zython/developer_doc/roadmap.md) | Execution Plan & Milestones | • Phase 1 through Phase 5 roadmap<br>• Progress percentages & delivery targets<br>• Language feature compatibility matrix |

---

## ⚡ Quick Architecture Overview

```mermaid
flowchart LR
    subgraph Phase1 ["v0.1.0: Baseline AST"]
        A1["Source (.py)"] --> B1["Lexer / Parser"]
        B1 --> C1["AST Tree (*Expr)"]
        C1 --> D1["Tree-Walk Interpreter"]
        D1 --> E1["8-Slot Env Cache"]
    end

    subgraph Phase2 ["v0.2.0: Optimized AST (Current)"]
        A2["Source (.py)"] --> B2["F-String / Tuple Parser"]
        B2 --> C2["Annotated AST"]
        C2 --> D2["Monomorphic Inline Cache"]
        D2 --> E2["32 Fast Slots + 16 OOP Slots"]
        E2 --> F2["1.7x List / 100,000x Loop Reduction"]
    end

    subgraph Phase3 ["v0.5.0: JIT Engine (Target 50x)"]
        A3["Source (.py)"] --> B3["Bytecode Compiler"]
        B3 --> C3["Flat Linear Bytecode"]
        C3 --> D3["NaN-Boxed Register VM"]
        D3 --> E3["Hot Loop Profiler"]
        E3 --> F3["Copy-and-Patch JIT"]
        F3 --> G3["x86_64 / ARM64 Machine Code"]
    end

    Phase1 -->|Optimization & Fixes| Phase2
    Phase2 -->|Bytecode & JIT Compilation| Phase3
```

---

## 🎨 Official Brand & Benchmark Color Palette

When visualizing Zython against CPython in comparative benchmarks, the following color specifications are standardized across all charts and reporting assets:

* ⚡ **Zython Color**: `Zig Golden Amber` (`#F7A41D` / `#F6991A`)  
  *Reflects the native Zig language emblem, energy, and zero-allocation execution.*
* 🐍 **CPython Color**: `Python Ocean Blue` (`#3776AB`) / `Python Canary Yellow` (`#FFD43B`)  
  *Reflects the official PSF brand palette.*
