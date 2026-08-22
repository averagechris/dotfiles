# Domain and boundaries

Use the language of the problem domain. Put each invariant where one owner can enforce it. Another boolean, lifecycle checks scattered among callers, or the same branch copied across files often signals a missing domain value or misplaced ownership. They are clues, not commands to add a framework.

Sketch caller usage before internals. Then define the smallest types and interfaces that make valid use clear and invalid states hard to express. Validate and parse untrusted input at the trust boundary. Pass domain values internally instead of repeatedly interpreting strings, maps, or loosely related flags.

Map who creates, owns, mutates, and observes each value. Keep policy with the component that has enough information to enforce it. Avoid interfaces that leak sequencing rules or require callers to know hidden state.

Every abstraction must pay rent. Name a likely shared change or failure it localizes. If the answer is only reuse in theory, prefer boring direct code. Count the concepts a reader must hold, hidden state, indirection, and methods that merely pass arguments through.
