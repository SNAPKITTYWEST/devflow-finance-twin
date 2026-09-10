# Repository Fiduciary and Financial Compliance Examination Protocol

Perform a complete examination of the repository and determine which financial, fiduciary, trust, accounting, payments, custody, and banking requirements are implicated by the software that actually exists.

Use source evidence as the sole basis for factual conclusions.

Do not construct hypothetical functionality.

Do not attribute capabilities to the system merely because a filename, variable name, dependency, or concept resembles a financial system.

Every conclusion must be traceable to repository evidence.

---

## 1. Complete Source Examination

Traverse the repository recursively.

Inspect:
- source files, libraries, modules, packages
- database schemas, migrations
- configuration, environment definitions
- API routes, services, interfaces, contracts
- scripts, tests, fixtures
- deployment files, documentation, policies, licenses
- examples, generated artifacts, dependency manifests

Build an inventory before evaluating compliance. Record exact paths and relevant line ranges.

---

## 2. Financial Capability Extraction

Locate implemented mechanisms involving:
accounts · balances · journals · ledgers · credits · debits · transfers · settlements · payments · disbursements · invoices · assets · liabilities · custody · beneficiaries · ownership · reconciliation · financial reporting · transaction histories · payment providers · banking interfaces · card infrastructure · wallets · treasury operations

For every occurrence, explain the implemented behavior using the actual source.

---

## 3. Trust and Fiduciary Analysis

Locate concrete implementations involving:
trusts · trustees · beneficiaries · fiduciary accounts · entrusted property · stewardship · agency relationships · restricted assets · beneficiary instructions · fiduciary approvals · fiduciary records · conflicts · distributions · asset management

Distinguish terminology from executable behavior.

A name, comment, class label, or document reference is not sufficient evidence of a legal relationship.

---

## 4. Banking Activity Analysis

Determine whether the repository contains implemented mechanisms associated with:
deposit functionality · withdrawal functionality · account servicing · payment execution · money movement · settlement · payment initiation · payment acceptance · financial account administration · banking integrations · stored-value mechanisms · lending · credit · interest calculations

For each capability, identify the precise implementation responsible.

---

## 5. Payment System Analysis

Inspect all payment-related functionality.

Determine whether the repository interacts with:
ACH · card networks · payment processors · bank transfer systems · wallets · merchant systems · payment APIs · settlement systems

Record the actual provider, interface, endpoint, data structure, and transaction path when present.

---

## 6. Accounting Analysis

Examine the accounting model actually implemented.

Trace:
```
transaction creation
→ journal processing
→ account mutation
→ balance calculation
→ reconciliation
→ reporting
→ historical record
```

Check for: balancing rules · duplicate prevention · correction mechanisms · reversals · period handling · transaction provenance · reconciliation · audit history · unauthorized mutation · inconsistent balances

---

## 7. Property and Custody

Determine whether software-controlled property or assets belonging to another party are represented.

Inspect: ownership · custody · segregation · authorization · beneficiary assignment · asset movement · restrictions · valuation · reconciliation · release conditions

Document exactly what the implementation does.

---

## 8. Control Environment

Trace authority through the system. Identify who or what can:
create financial records · authorize transactions · execute transactions · modify account information · change beneficiaries · alter ownership · reverse transactions · approve distributions · modify financial configuration · override controls

Identify concentration of authority and missing separation mechanisms.

---

## 9. Record Integrity

Examine whether material records can be:
altered · deleted · replaced · backdated · duplicated · reordered · detached from authorization · changed without historical evidence

Document the actual persistence and audit mechanisms.

---

## 10. Identity and Customer Controls

Where implemented, inspect:
identity verification · customer onboarding · account ownership · authentication · authorization · customer records · beneficial ownership · account restrictions · suspicious-activity mechanisms · sanctions screening

Do not claim a compliance program exists merely because an identity field exists.

---

## 11. Regulatory Domain Mapping

For every confirmed capability, identify potentially relevant legal domains:
banking regulation · money transmission · payment regulation · electronic funds transfer · consumer financial protection · trust administration · fiduciary obligations · custody · securities regulation · investment management · lending · accounting requirements · tax reporting · privacy · records retention · electronic transactions · sanctions · anti-money-laundering requirements · payment-network rules

Separate statutory requirements, regulations, contractual requirements, industry standards, and internal controls.

---

## 12. Jurisdiction Analysis

Extract jurisdictional information from the repository. Look for:
governing-law clauses · entity locations · operating locations · customer locations · beneficiary locations · trustee locations · regulatory references · licensing references · contractual jurisdiction · deployment regions

Do not assign a jurisdiction that cannot be established. Where jurisdictional information is absent, identify the missing fact instead of selecting one arbitrarily.

---

## 13. Claim Verification

Search documentation and source comments for claims involving:
licensed status · regulated status · fiduciary authority · banking authority · custody · trust authority · payment authority · compliance certification · regulatory approval

Compare every such claim against repository evidence. Mark unsupported claims explicitly.

---

## 14. Third-Party Dependencies

Trace financial functionality into every external dependency. For each integration identify:
provider · API · credentials · data exchanged · transaction direction · authorization mechanism · persistence · failure behavior · reconciliation mechanism · contractual dependency

Do not treat an installed dependency as evidence that its functionality is actually used.

---

## 15. Legal Control Trace

For every identified requirement, trace:
```
LEGAL REQUIREMENT
→ SOFTWARE CONTROL
→ IMPLEMENTATION
→ TEST
→ EVIDENCE
```
If any link is absent, identify the missing link.

---

## 16. Evidence Standard

Every finding must contain:
- finding identifier
- repository path
- line range
- symbol or configuration key
- observed behavior
- supporting evidence
- relevant legal domain
- jurisdiction
- applicability status
- control status
- severity
- unresolved question

Never produce a legal conclusion without supporting evidence.

---

## 17. Classification

```
CONFIRMED
SUPPORTED
POTENTIALLY APPLICABLE
UNRESOLVED
INSUFFICIENT EVIDENCE
NOT PRESENT
CONTRADICTED
```

Do not upgrade an unresolved issue into a confirmed violation.

---

## 18. Contradiction Examination

Compare: source code · tests · schemas · documentation · configuration · contracts · deployment definitions

Identify situations where documentation describes behavior that the implementation does not provide, or where implementation contradicts documented controls.

---

## 19. Test Verification

Locate tests covering financial and fiduciary behavior.

Determine whether tests actually establish:
authorization · transaction integrity · accounting correctness · balance consistency · custody restrictions · beneficiary controls · reconciliation · auditability · failure handling

Do not count a test merely because its name suggests coverage.

---

## 20. Missing Evidence

Create a dedicated section identifying facts required for a definitive legal determination but unavailable from the repository:
entity structure · jurisdiction · licensing status · contractual relationships · customer type · transaction volume · geographic scope · ownership structure · regulatory registrations · actual operational procedures

Do not fill these gaps with assumptions.

---

## 21. Final Findings Matrix

```
ID | Repository Evidence | Actual Function | Legal Domain | Jurisdiction | Applicability | Control | Severity | Evidence Gap
```

Every row must correspond to something actually discovered.

---

## 22. Final Report Structure

- **CONFIRMED FUNCTIONALITY** — Everything demonstrably implemented.
- **FINANCIAL EXPOSURES** — Financial capabilities that may trigger legal or regulatory obligations.
- **FIDUCIARY EXPOSURES** — Actual mechanisms that may create fiduciary or trust-related obligations.
- **BANKING EXPOSURES** — Actual mechanisms potentially associated with banking activity.
- **ACCOUNTING EXPOSURES** — Actual accounting and ledger behavior requiring examination.
- **PAYMENT EXPOSURES** — Actual payment and money-movement functionality.
- **DOCUMENTATION CONFLICTS** — Claims that do not match implementation evidence.
- **MISSING INFORMATION** — Facts required before definitive legal conclusions can be made.
- **HIGH-PRIORITY FINDINGS** — The most consequential evidence-backed issues.
- **COMPLETE EVIDENCE INDEX** — A path-by-path index connecting every material conclusion to its repository source.

---

## 23. Absolute Audit Rule

Never replace missing evidence with imagination.

Never convert terminology into functionality.

Never convert functionality into legal status without establishing the applicable facts.

Never manufacture a regulation to fill a gap.

Never report a hypothetical capability as an implemented capability.

The final examination must describe what the repository demonstrably contains and identify the legal and regulatory questions arising from that evidence.
