## Change

Describe the owned behavior and the smallest sufficient boundary change.

## Engineering gate

- [ ] The owning object or module is explicit.
- [ ] Policy is separated from infrastructure by a focused contract.
- [ ] Implementations preserve the contract's behavior and security guarantees.
- [ ] No provider or channel type switch was added to application policy.
- [ ] Dependencies are supplied explicitly and point inward.
- [ ] Unit and contract tests prove the boundary without external services.
- [ ] Full CI is green.
- [ ] Validate for deploy is green or documented as not applicable.

## External actions

- [ ] This change performs no live provider publish in required CI.
- [ ] Merge and deployment remain separate, explicitly authorized actions.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
