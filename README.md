# Hospital Assignment System (PROMELA / SPIN)

A concurrent system model of a simplified hospital, implemented in **PROMELA** and designed for verification with **SPIN**.

## Overview
This project models a hospital that operates for 8 hours per day and handles three customer types:
- **Normal**
- **Insured**
- **VIP**

Customers are routed to one of three departments, each with different resource constraints and priority rules:
- **Department A**: doctors share limited machines, with VIP machine reservation
- **Department B**: junior/senior doctor workflow with referral logic
- **Department C**: pre-op, surgery, and cleaning pipeline with VIP preemption

The system focuses on concurrency-safe resource allocation and timing coordination while avoiding:
- deadlock
- livelock
- starvation
- race conditions

## Main Concepts
- **Global time synchronization** using a publish-subscribe style clock mechanism
- **Atomic resource locking** for safe concurrent access
- **Priority scheduling** for VIP / Insured / Normal customers
- **Hierarchical triage and referral workflow**
- **Preemptive scheduling** in the surgical pre-op stage
- **Formal modeling and verification mindset** with SPIN

## Repository Structure
```text
hospital-assignment-system/
├── hospital_demo.pml          # main submitted model
├── hospital_improvement.pml   # post-submission improved version with better time-channel design and extra logs
├── Project-Report.pdf         # project report
└── README.md
```

## Files
### 1. `hospital_demo.pml`
Initial PROMELA model of the Hospital Assignment System.

### 2. `hospital_improvement.pml`
Improved version of the model. Main updates include:
- refactored time synchronization so each client process uses its own channel
- clearer server-client communication design
- additional runtime logging for admissions, rejections, surgery readiness, pre-op kick-out events, and operating room cleaning

### 3. `Project-Report.pdf`
Formal project report describing the problem, architecture, concurrency design, and implementation details.

## How to Run with SPIN
Example commands:

```bash
spin -p -g -l -u1000 hospital_demo.pml
```

Generate verifier:

```bash
spin -a hospital_demo.pml
gcc -o pan pan.c
./pan
```

You can also test the improved model:

```bash
spin -p -g -l -u1000 hospital_improvement.pml
```

> Note: exact compiler / SPIN setup may vary depending on your operating system.

## Highlights
- Models a realistic multi-stage hospital workflow with limited shared resources
- Demonstrates safe handling of concurrent processes with priority-based constraints
- Uses atomic blocks to prevent inconsistent state updates
- Shows how formal modeling can be applied to real-world scheduling and allocation problems

## Skills Demonstrated
- Concurrent system modeling
- Synchronization
- Resource scheduling
- Formal verification
- PROMELA / SPIN
- Algorithmic thinking

## Academic Context
This project was developed as part of the module **Modelling of Concurrent Systems with PROMELA** in Winter Term 2025/26 at **Vietnamese-German University**.

## CV-Friendly Description
Designed and implemented a concurrent hospital workflow model in PROMELA, featuring priority-based scheduling, atomic resource allocation, global time synchronization, and formal verification-oriented design using SPIN.
