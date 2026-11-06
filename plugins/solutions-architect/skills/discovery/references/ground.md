# Ground to cover in the conversation

This is territory, not a script. Do not walk it in order and do not ask one question per bullet.
Start from the first thing the user said, offer a corrigible guess where you can ("it sounds
like the pain is the peak, not the average - right?"), and let the answers decide what to ask
next. One question per message. No list of answers to pick from.

Cover, as far as it matters to the decision:

- **Business driver and why now.** What changed, what hurts, what does it cost? A moment that
  makes it concrete ("the last time the order system hurt someone") beats "what are your goals".
- **Who is affected.** Customers, operators, other systems, regulators; who loses if it goes
  wrong, who wins if it goes right.
- **Success in business terms.** What would make the sponsor say it worked, in a sentence they
  could say without a technical word.
- **Goals, non-goals and anti-goals.** A goal is wanted. A non-goal is out of scope. An anti-goal
  is something the solution must not do or become, even if it would otherwise help ("must not
  need a team to run Kubernetes", "no second cutover weekend").
- **Current state.** Systems, data and its size, contracts and integrations, the team and its
  skills, how it runs today and where it hurts. Read the repository and any existing IaC first;
  ask only about what they do not show.
- **What they have already seen.** Approaches tried, products evaluated, what they liked or hated
  about them, and why.
- **Must versus prefer.** For every constraint or solution the user names: is it mandatory (a
  contract, a law, an existing commitment) or a preference? A mandatory item becomes a
  constraint with its source; a preference becomes an option to compare.
- **Time and money in orders of magnitude.** A deadline that is real, a budget ceiling that is
  real, and the unit cost is measured in. Exact figures belong to the requirements stage.

Mark every item you write down with where it came from (`Source: user | inferred | default |
agent`). When you restate what you heard, restate it in parts of 200 to 300 words and end by
asking what is wrong or missing.
