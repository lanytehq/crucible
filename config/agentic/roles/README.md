# Role Catalog

Baseline role prompts for AI agent sessions.

The **operating** catalog for estate seats is
[3leaps/crucible](https://github.com/3leaps/crucible). This directory holds
Lanyte product copies and Lanyte-only seats. `entarch` is defined in the
3leaps catalog and is not duplicated here.

**Schema**: [`role-prompt.schema.json`](../../../schemas/agentic/v0/role-prompt.schema.json)

## Quick Reference by Timeline

| Timeline               | Roles                      | Use When                                                       |
| ---------------------- | -------------------------- | -------------------------------------------------------------- |
| **Minutes - Hours**    | devlead, devrev, qa, uxdev | Writing code, reviewing changes, fixing bugs, building UI      |
| **Days - Week**        | dispatch, secrev           | Session handoffs, security reviews, coordination               |
| **Sprint (1-4w)**      | deliverylead, cicd         | Sprint planning, delivery coordination, pipelines              |
| **Quarter (3mo)**      | releng, prodmktg           | Release planning, marketing campaigns, roadmaps                |
| **Strategic (6-18mo)** | cxotech                    | Architecture decisions, product direction, cross-repo strategy |

## Role Categories

| Category   | Purpose                              | Roles                              |
| ---------- | ------------------------------------ | ---------------------------------- |
| agentic    | Implementation and creation          | devlead, uxdev, infoarch, prodmktg |
| automation | Pipeline and release automation      | cicd, releng                       |
| review     | Quality, security, and correctness   | devrev, qa, secrev                 |
| governance | Strategy, coordination, architecture | dispatch, cxotech, deliverylead    |

## Process Domains

Roles are organized across these business process domains:

| Domain         | Description                              | Primary Roles                      |
| -------------- | ---------------------------------------- | ---------------------------------- |
| development    | Code creation, testing, implementation   | devlead, uxdev, devrev, qa, secrev |
| delivery       | Release, deployment, project management  | cicd, releng, deliverylead         |
| governance     | Strategy, coordination, architecture     | dispatch, cxotech                  |
| strategy       | Long-term decisions, product direction   | cxotech, prodmktg                  |
| architecture   | System design, pattern selection         | cxotech, infoarch                  |
| coordination   | Session handoff, task routing            | dispatch, deliverylead             |
| marketing      | Brand, messaging, positioning            | prodmktg                           |
| documentation  | Schema governance, information structure | infoarch                           |
| security       | Vulnerability review, infosec            | secrev                             |
| quality        | Testing, validation, review              | devrev, qa                         |
| implementation | Code writing, feature delivery           | devlead, uxdev                     |

## Available Roles

| Role                                                | Slug           | Category   | Domains                         | Timeline       | Purpose                                    |
| --------------------------------------------------- | -------------- | ---------- | ------------------------------- | -------------- | ------------------------------------------ |
| [Development Lead](devlead.yaml)                    | `devlead`      | agentic    | development, implementation     | Hours-Days     | Implementation, architecture               |
| [Development Reviewer](devrev.yaml)                 | `devrev`       | review     | development, quality            | Hours-Days     | Code review, four-eyes audit               |
| [Quality Assurance](qa.yaml)                        | `qa`           | review     | development, quality            | Hours-Week     | Testing, validation                        |
| [Security Review](secrev.yaml)                      | `secrev`       | review     | development, security           | Days-Week      | Security analysis, vulnerabilities         |
| [Information Architect](infoarch.yaml)              | `infoarch`     | agentic    | development, documentation      | Days-Sprint    | Documentation, schemas                     |
| [CI/CD Automation](cicd.yaml)                       | `cicd`         | automation | automation, delivery            | Days-Week      | Pipelines, GitHub Actions                  |
| [Dispatch Coordinator](dispatch.yaml)               | `dispatch`     | governance | coordination, governance        | Days-Sprint    | Cross-session coordination                 |
| [Delivery Lead](deliverylead.yaml)                  | `deliverylead` | governance | coordination, delivery          | Sprint-Quarter | Project lifecycle, sprint coordination     |
| [Release Engineering](releng.yaml)                  | `releng`       | automation | delivery, development           | Quarter        | Versioning, releases                       |
| [Product Marketing](prodmktg.yaml)                  | `prodmktg`     | agentic    | delivery, marketing             | Quarter        | Branding, messaging, personas              |
| [UX Developer](uxdev.yaml)                          | `uxdev`        | agentic    | development, implementation     | Hours-Days     | Desktop, web, and TUI interfaces           |
| [Skill Author](skillauthor.yaml)                    | `skillauthor`  | agentic    | development, implementation     | Hours-Days     | WASM skill dev, ABI compliance             |
| [Chief Experience Technology Officer](cxotech.yaml) | `cxotech`      | governance | strategy, architecture, product | Strategic      | Strategic fulcrum for product-architecture |

## When to Use Which Role

### By Work Phase

| Phase                          | Primary Role     | Escalation                     | Timeline      |
| ------------------------------ | ---------------- | ------------------------------ | ------------- |
| **Emergency fix**              | devlead          | secrev (security)              | Minutes-hours |
| **Feature implementation**     | devlead          | devrev (review)                | Hours-days    |
| **UI/UX implementation**       | uxdev            | devlead (backend), devrev      | Hours-days    |
| **Bug investigation**          | devlead → devrev | qa (validation)                | Days          |
| **Security review**            | secrev           | human maintainers              | Days-week     |
| **Session handoff**            | dispatch         | deliverylead (project context) | Days          |
| **Sprint planning**            | deliverylead     | cxotech (priority conflicts)   | 1-4 weeks     |
| **Pipeline setup**             | cicd             | releng (release integration)   | Days-week     |
| **Release prep**               | releng           | cxotech (strategic timing)     | Week          |
| **Architecture decision**      | cxotech          | human maintainers              | Weeks-months  |
| **Documentation**              | infoarch         | prodmktg (messaging)           | Days-sprint   |
| **Multi-project coordination** | deliverylead     | dispatch (session routing)     | Sprint        |
| **Cross-repo strategy**        | cxotech          | human maintainers              | Quarter       |

### By Decision Type

| Decision Scope                  | Role         | Typical Timeline |
| ------------------------------- | ------------ | ---------------- |
| Code pattern selection          | devlead      | Minutes-hours    |
| Session routing                 | dispatch     | Minutes          |
| Sprint commitment               | deliverylead | 1-4 weeks        |
| Release versioning              | releng       | Quarter          |
| Feature brief approval          | cxotech      | Weeks            |
| Product direction               | cxotech      | Months           |
| Security vulnerability handling | secrev       | Hours-days       |
| Test strategy                   | qa           | Sprint           |
| Pipeline architecture           | cicd         | Days-week        |

### By Complexity Level

- **Simple coding task**: devlead
- **UI/frontend task**: uxdev (escalates to devlead for backend changes)
- **Multi-step feature**: devlead → devrev → qa (sequential)
- **Cross-role conflict**: cxotech resolves
- **Multi-session delivery**: deliverylead coordinates, dispatch routes sessions
- **Cross-project dependencies**: deliverylead orchestrates, cxotech approves escalations
- **Strategic architecture decision**: cxotech evaluates, deliverylead sequences, devlead implements

## Timeline Contrast: Governance Roles

The three governance roles operate at different time horizons:

| Role             | Timeline           | Scope                | Key Question                               |
| ---------------- | ------------------ | -------------------- | ------------------------------------------ |
| **dispatch**     | Minutes - Days     | Session handoff      | "What context does the next session need?" |
| **deliverylead** | Sprint - Quarter   | Project coordination | "When do we ship this?"                    |
| **cxotech**      | Strategic (6-18mo) | Product-architecture | "Should we build this? Which pattern?"     |

**Relationship**: Cxotech approves feature briefs → Deliverylead sequences the work → Dispatch routes individual sessions

## Usage

Reference roles by slug in `AGENTS.md`:

```yaml
roles:
  - slug: devlead
    source: config/agentic/roles/devlead.yaml
  - slug: deliverylead
    source: config/agentic/roles/deliverylead.yaml
  - slug: cxotech
    source: config/agentic/roles/cxotech.yaml
```

## Schema Validation

All role files conform to the [role-prompt schema](../../../schemas/agentic/v0/role-prompt.schema.json).

Validate with:

```bash
# Using goneat
goneat validate data --schema-file schemas/agentic/v0/role-prompt.schema.json --data config/agentic/roles/deliverylead.yaml

# Or validate all
make lint-config
```

## Extending Roles

To extend a baseline role:

```yaml
slug: devlead
extends: https://schemas.3leaps.dev/roles/devlead.yaml
# Add or override fields
scope:
  - ...additional scope items...
```

## New Roles

When adding roles to this catalog:

1. **Determine timeline**: Minutes, Days, Sprint, Quarter, or Strategic
2. **Assign category**: agentic | automation | review | governance
3. **Assign domains**: 1-3 process domains (see table above)
4. **Define escalation paths**: Which roles does this escalate to/from?
5. **Validate**: Run `make lint-config` before committing
6. **Update README**: Add to Available Roles table with timeline
