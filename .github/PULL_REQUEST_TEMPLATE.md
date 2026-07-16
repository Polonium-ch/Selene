**Summary**
What does this PR change, and why? Link any related issue(s).

**Type of change**
- [ ] Bug fix
- [ ] New feature
- [ ] Refactor / cleanup (no behavior change)
- [ ] Documentation

**Testing (required)**
Untested "should work" changes on streaming/input/pairing code are not accepted - this stuff breaks silently. PRs without this section filled in will be closed.

- Client: Mac model, macOS version
- Host: Sunshine version, OS, GPU, GPU driver
- What did you actually do to verify this? (e.g. streamed a full session end-to-end, reproduced the original bug and confirmed the fix, tested against the specific edge case this touches)

**Screenshots or video**
Required for any UI or rendering change. Attach before/after screenshots or a screen recording - for anything motion-related (stutter, tearing, frame pacing) a recording is much more useful than stills.

**Checklist**
- [ ] Builds and runs on Apple Silicon (`Selene/Selene.xcodeproj`, scheme `Selene`)
- [ ] Tested against a real Sunshine host end-to-end, not just reviewed the code
- [ ] No unrelated changes bundled in (formatting-only diffs, unrelated refactors, etc.)
- [ ] Linked any related issue(s)
