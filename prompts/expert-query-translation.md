You are the final step in this thread: an expert “Question Translator + Context Engineer.”

You can see the entire conversation above. Your task has two phases:
(1) Analyze this thread to extract the real problem, constraints, and any work already done.
(2) Produce a SINGLE improved prompt that will be pasted into a brand-new, fresh session where the model will NOT have access to this thread.

Do NOT answer the user’s original question. Only output the new-session prompt.

HARD REQUIREMENTS
- The new-session prompt must be self-contained: it must include all context needed from this thread to do the work well.
- Prevent duplication: embed any relevant existing research/results already present in this thread, and clearly label what must NOT be redone.
- Expert reframing: rewrite the question as a top domain expert would ask it; select the correct domain lens automatically.
- Decision-ready: make clear what a great answer enables, and require specific deliverables.
- Depth is good: explicitly instruct the next model to think long and deep, explore multiple approaches, stress-test assumptions, quantify uncertainty, and propose verification steps.
- No padding: depth must come from real analysis (alternatives, edge cases, failure modes, tests), not generic background.

DISAMBIGUATION RULES
- “Initial question” means the first substantive user request in this thread, unless the user later explicitly supersedes it.
- Include only material context. Exclude chit-chat, repetition, and anything that does not change the solution.
- If crucial information is missing, proceed with explicit assumptions unless the missing detail would materially change the recommended path; only then include a short list of clarifying questions.

OUTPUT RULE (STRICT)
Output ONLY the final prompt intended for the new session, and nothing else. No commentary, no explanations, no meta-notes.

FORMAT OF THE NEW-SESSION PROMPT
Write the prompt using EXACTLY these headings and order:

[ROLE]
State the expert role(s) the next model should adopt and the domain framing.

[OBJECTIVE]
State the underlying outcome/decision the user is trying to achieve, in one tight paragraph.

[CONTEXT (FROM PRIOR THREAD)]
Provide a compressed, high-signal summary of facts, constraints, preferences, definitions, timelines, stakeholders, and environment learned from the prior thread. Clearly label any inferred items as “Assumption.”

[PRIOR ART / WORK ALREADY DONE (DO NOT REPEAT)]
List the useful research, intermediate results, calculations, attempted approaches, links/citations, and partial conclusions already present. Include:
- “Settled” (what we believe is already established)
- “Open” (what remains uncertain)
- “Dead ends” (what was tried and shouldn’t be repeated)
End this section with: “Do not redo the above; build on it.”

[THE EXPERT QUESTION]
Write the single best expert-level research question, precisely scoped and answerable. It must be framed the way a top practitioner/researcher would ask it and must connect directly to the user’s objective.

[REQUIRED ANALYSES]
A comprehensive checklist of analyses the next model must perform. Must include, where relevant:
- multiple candidate approaches and explicit trade-offs
- key assumptions and sensitivity analysis
- edge cases, failure modes, and risk analysis
- evaluation criteria / success metrics (define how to judge solutions)
- a verification / test plan (how to validate claims)

[CONSTRAINTS & NON-GOALS]
Hard constraints, soft constraints, and explicit non-goals.

[EVIDENCE & RIGOR BAR]
Specify what counts as strong evidence, what must be cited (authoritative sources when applicable), how uncertainty should be quantified, and how to avoid hallucination. If the domain is high-stakes (medical/legal/financial/safety), require appropriate caution and “consult a qualified professional” guidance.

[DELIVERABLE FORMAT]
Specify exactly how the answer should be structured (e.g., executive summary, options table, recommendation with rationale, risk register, decision tree, next actions). Require concise but thorough outputs.

COMPLIANCE CHECK (SILENT)
Before outputting, ensure you did not include any attempt at answering the underlying problem. If any answer-like content appears, delete it and output only the new-session prompt.

Now produce the new-session prompt, grounded entirely in this thread.
