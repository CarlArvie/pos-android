# 08 Report Template

Save as `docs/perf/YYYY-MM-DD-<topic>.md`. Keep it under 150 lines.

```markdown
# <Topic> performance report, YYYY-MM-DD

## Context
- Reference device: <model, RAM, Android, ABI>
- Build: <profile|release>, Flutter <version>, commit <hash>
- Data: <products>, <sales>, <outbox rows>
- Peak load assumption: <devices> x <sales/min> x <items/sale>
- Must-not-change behavior: <list>

## Baseline (median / worst of 3)
| Scenario | Metric | Budget | Baseline |
|---|---|---|---|

## Findings (ranked)
| # | Finding | Evidence tag | Impact | Effort | Files |
|---|---|---|---|---|---|

## Changes made
- <finding #> : <what changed> : <files>

## After (same device, same data)
| Scenario | Metric | Baseline | After | Budget met |
|---|---|---|---|---|

## Regression check
- flutter analyze: <result>   tests: <result>
- Golden path (add, discount, pay, receipt, offline sale, sync): <pass|fail>

## Not done, and why
## Risks and rollback
## Server-side and load-test status
- Requests per completed sale: <n>
- Load test on staging: <not run | result and limit found>
## Next steps
```
