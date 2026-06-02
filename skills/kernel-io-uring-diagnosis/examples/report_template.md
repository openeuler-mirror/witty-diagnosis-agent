# io_uring Diagnosis Report Template

## Summary

- Case ID:
- Host:
- Kernel:
- Process/PID:
- Failure window:
- Classification:
- Confidence:

## User-visible Symptom

Describe the application error, timeout, throughput drop, missing completion, or
syscall errno observed by the user.

## Evidence

| Evidence | Source | Interpretation |
| --- | --- | --- |
|  |  |  |

## Root Cause Analysis

State the most likely root cause and explain which io_uring stage is involved:
setup, submit, complete, register, worker execution, SQPOLL, direct I/O, or
kernel compatibility.

## Excluded Causes

-
-

## Risk and Impact

- Affected workload:
- Failure mode:
- Data integrity risk:
- Performance risk:

## Recommendations

Read-only recommendations:

-

Actions that require explicit approval:

-

## Missing Evidence

-

## Commands Run

```bash

```

## Cleanup

No cleanup is required for read-only diagnosis. If fault injection was used,
record the exact cleanup command and result here.
