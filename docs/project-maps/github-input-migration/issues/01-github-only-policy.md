# GitHub-only source policy

Type: grilling
Status: resolved
Blocked by: none

## Question

Should this migration use GitHub-only source retrieval with no SourceHut network
access, while preserving existing package/module interfaces and the current
nixpkgs pin?

## Answer

Yes. The user approved GitHub as the only source authority for this effort and
explicitly prohibited SourceHut network access. Existing interfaces and the
nixpkgs pin remain unchanged. This answer governs the research and any later
delivery work, but does not authorize implementation or deployment.
