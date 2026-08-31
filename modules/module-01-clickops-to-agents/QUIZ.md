# M01 Quiz: From ClickOps to Agents

8 questions. Pick one answer, then open the reveal to check it and read why.

---

**1. Which lists the seven eras in the correct order?**

- A. ClickOps → Scripts → Configuration management → Declarative IaC → GitOps → AI-assisted → Agentic
- B. ClickOps → Configuration management → Scripts → GitOps → Declarative IaC → AI-assisted → Agentic
- C. Scripts → ClickOps → Declarative IaC → Configuration management → AI-assisted → GitOps → Agentic
- D. ClickOps → Scripts → Declarative IaC → Configuration management → GitOps → Agentic → AI-assisted

<details>
<summary>Answer</summary>

**A.** Each era raises the level at which a human states intent and hands more of the
translation to a machine. Configuration management fixed the "runs twice" problem that
scripts left behind, before declarative IaC arrived and moved the description up another
level. Options B, C, and D each swap two eras out of that order.

</details>

---

**2. A teammate pastes a Terraform error into a chat window, gets a suggested fix, and copies the fixed line into their own file by hand. What is this?**

- A. Automation
- B. Autocomplete
- C. An agent
- D. A stopping condition

<details>
<summary>Answer</summary>

**B, autocomplete.** There's no loop: the tool produced one suggestion and stopped. It
didn't act, observe the result, and decide what to do next. The teammate did all of the
deciding and all of the acting. It's not automation either, automation runs a fixed
sequence, and there was no sequence here, just one suggestion.

</details>

---

**3. A CI script always runs `terraform fmt`, `terraform validate`, and `terraform apply` in that fixed order, with no branching logic. Is this an agent?**

- A. Yes, it acts on infrastructure without a human typing each command
- B. No, it's automation: a fixed sequence with no decisions
- C. Yes, because it runs more than one command in a row
- D. No, because it never touches a real cloud account

<details>
<summary>Answer</summary>

**B.** It executes a fixed sequence regardless of what it observes along the way. An agent
would decide, based on what `validate` actually returned, whether to proceed, fix
something, or stop. Running several commands in a row (C) isn't what makes something an
agent, deciding between them based on what happened is.

</details>

---

**4. A tool reads a one-line intent, generates a Terraform module, runs `checkov` against it, and if the scan fails, rewrites the offending resource and re-scans, up to three attempts, before handing the result to a human. Which step of the autonomy ladder is this?**

- A. Step 3, propose with plan
- B. Step 4, gated apply
- C. Step 5, supervised autonomy
- D. Step 6, unattended

<details>
<summary>Answer</summary>

**C, step 5, supervised autonomy.** The agent loops on its own across multiple iterations,
generating, checking, and fixing, and a human reviews the final outcome rather than each
individual step. To move to step 6, unattended, it would need a defined stopping condition
that doesn't require a human to review every run, and the gate that currently makes that
human review meaningful would need to become automated enough to trust without it.

</details>

---

**5. Which of the following is NOT one of the four properties that make infrastructure harder for an agent to touch than application code?**

- A. No undo
- B. State
- C. Verbose syntax
- D. Blast radius
- E. Silent failure

<details>
<summary>Answer</summary>

**C, verbose syntax.** Terraform's syntax has nothing to do with why infrastructure
mistakes are more dangerous. The four real properties are no undo, state, blast radius,
and silent failure.

</details>

---

**6. Given the thesis "the agent proposes, the pipeline decides," where is `apply` authorized to run in a well-built agentic infrastructure workflow?**

- A. As soon as `terraform plan` and `checkov` both pass
- B. Whenever the agent is confident its own plan is correct
- C. Only after the full pipeline, scans, policy checks, cost checks, and human approval, has approved the plan
- D. After the agent's own internal tests pass, before any human sees it

<details>
<summary>Answer</summary>

**C.** The agent's own confidence that its plan is correct is never sufficient on its own,
its authority ends at producing the plan. A clean `checkov` pass (A) is only one gate among
several, not the whole pipeline, and B and D both hand the decision back to the agent,
which is exactly what the thesis says not to do.

</details>

---

**7. A team says: "Our agent writes correct Terraform for simple modules, but every time we ask it to follow our internal naming convention or use our approved module registry, it ignores the instruction." Which of the three layers does this symptom point to?**

- A. Context
- B. Harness
- C. Loop

<details>
<summary>Answer</summary>

**B, harness.** The agent isn't failing to understand the task, that would be a context
problem, and it isn't failing to stop or re-trigger correctly, that would be a loop
problem. It's ignoring team standards, which live in the tools, hooks, and gates around the
agent, the harness, not in what the agent knows or when it runs.

</details>

---

**8. A junior engineer argues: "Since 46% of organizations already run AI for infrastructure in production, we should let our agent apply changes unattended, adoption is clearly high enough." What's wrong with that argument?**

- A. Nothing, 46% is a strong majority
- B. It conflates adoption with trust: only 34% would trust autonomous production changes, and 43% name absent guardrails as the top blocker
- C. The 46% figure only counts small companies
- D. Adoption numbers don't apply to infrastructure work at all

<details>
<summary>Answer</summary>

**B.** High adoption of AI-assisted work, most of it well below step 6, doesn't imply
readiness for unattended production changes. The same survey found only 34% would trust an
autonomous system to make production changes without human approval, and 43% named absent
guardrails as the top blocker to going further. Most teams that have adopted this are
deliberately not running it unattended yet.

</details>
