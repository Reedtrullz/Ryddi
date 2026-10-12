# Reviewed Trash handoff

Clean, Audit (including the CLI), DerivedData and session maintenance retain their existing eligibility and open-file checks. The shared mover then opens the reviewed source and parent, checks their identity, and stages through exclusive descriptor-relative rename in a private sibling directory. Reviewed sessions also carry their recorded size and modification time into this handoff.

The mover resolves the native user Trash directory, requires it to share the source's device, and uses exclusive rename between pinned descriptors. A post-move identity/generation check rejects replacement or redirection. Failure restores the original name exclusively; an occupied original name is preserved, and the error reports the retained object's current location. If an external actor makes that location unavailable, the error says so. No failure path permanently deletes the object.

Other volumes and inaccessible Trash fail closed. Apple's [directory lookup contract](https://developer.apple.com/documentation/foundation/filemanager/url(for:in:appropriatefor:create:)) does not use `appropriateFor` to choose a Trash volume. Items remain recoverable in Trash, with a unique name; this path does not create Finder Put Back metadata. Session size/mtime checks are the existing review generation contract, not content digests. They do not freeze writers, recursively snapshot directory children, or certify resistance to a same-user adversary deliberately rewriting metadata or the private staging namespace.

Regression tests use disposable source and fixture Trash directories. They do not use the user's real Trash, sessions, caches or cloud provider folders. Installed-app and release acceptance are separate gates.
