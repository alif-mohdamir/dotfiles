---
name: grill-with-adversary
description: Interview the user about how to approach an issue or ticket, with a persistent adversary subagent that attacks each proposed decision. Use when the user asks to grill them on an issue or ticket with an adversary, to pressure-test an approach before building, or to settle design choices for a ticket. Prefer this over plain grill-me whenever the user mentions an adversary, a red team, or a second session to challenge the plan.
---

Settle the open decisions in an issue or ticket by interviewing the user, and have a
persistent adversary subagent attack every proposal before the user sees it. Your
global prose rules apply to everything you write, including the brief you give the
adversary.

## 1. Read before asking

Fetch the issue or ticket with whatever tracker the repo uses (`gh issue view`, a pasted
link, a file). Then read the code it touches: schemas, endpoints, the existing
behavior the ticket would change. A question the code can answer is yours to answer.
The user's time goes to decisions only they can make: scope, product behavior, risk
appetite, who owns what.

Keep notes of what you verified yourself. You will need them in step 5.

## 2. Spawn one adversary and keep it

Start a single read-only subagent. Brief it with the issue or ticket text, your code
findings, and its standing role: for each proposal it receives, reply with the strongest
objection (verified in code, with file and line), a concrete failure scenario, and
whether it would accept the proposal if amended, giving the amendment. It also names one
approach the proposal did not consider (a different sequencing, integration boundary or
rollout, or a different product shape) and says why it might win, or says it found none.
Cap replies at about 250 words.

Reuse that agent for the whole interview with `SendMessage`, which resumes it with its
earlier rounds intact. A fresh agent per question loses the context that makes later
objections sharp. It stops after each reply; that is normal and it stays resumable.

Ask it for its five strongest objections to a naive build first, plus the two most
plausible alternative approaches to the whole ticket. Use them to order the questions,
with the decisions others depend on coming first.

## 3. One decision per round

For each decision:

1. Write a proposal and mark it unapproved. Send it to the adversary with every
   decision settled so far, so it argues against the current state.
2. Read its reply. Verify every claim it makes about the code (step 5) before using it.
3. Revise the proposal with the amendments that hold up. Take implementation details
   yourself and say so in a line. Do not ask the user about ordering, timestamps,
   query shape or similar facts the code settles.
4. Ask the user one question, with your recommendation. Say what the adversary found,
   what you changed, and who owns the call. Stop and wait.

If the user asks which parts the code could have answered, check the code and say
plainly what you should have read earlier.

## 4. What counts as approval

Record a decision as approved only when the user answers that question explicitly. These
are not approval:

- "continue", "next", or silence
- a background task or subagent notification, which carries no user input
- the adversary's agreement
- a question from the user about process

When the user moves on without answering, keep the decision as a working position, say
so in the same message, and put it on the list to confirm before you finish.

## 5. Verify the adversary

The adversary is a model, and its line numbers and claims can be wrong. Open each file it
cites before you rely on it, and correct it when it is wrong. Never write "I checked"
about a claim you did not open. If a check changes a decision, tell the user what you
found.

## 6. Finish with a handoff

End with the list of settled decisions. Tag each with who made it and on what basis,
for example "product owner, on the ticket" versus "my recommendation, approved in the
interview, argued only on X". A recommendation can be revisited when a new consideration
appears. An owner's ruling needs the owner. Then list:

- decisions that are still working positions and need the user's confirmation
- questions for people outside the session (the ticket author, the game or service
  owner, a downstream team), each with who should answer
- follow-up tickets the interview created, such as scope you deferred

Mention that the adversary can be resumed if the work continues in this session.
Do not write to the repo or the tracker unless the user asks.
