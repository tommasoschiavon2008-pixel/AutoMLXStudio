# Remote Engineering deterministic fixture

This disposable fixture contains one intentional arithmetic bug. It exists only for later physical Windows-inference revalidation while every file operation and test process remains on the Mac.

Expected task for Engineering:

> Fix `shipping_total` so the observable test passes. Make the smallest correct change, then run the approved test and verify the result.

Run locally from this directory:

```sh
make test
```

The command uses only a Python 3 standard-library interpreter, performs no network access, package installation, privilege escalation, or external filesystem mutation, and normally finishes well below one second. The baseline is intentionally failing; a successful Engineering run must change `subtotal - fee` to `subtotal + fee`, receive explicit approval for the edit and test command, and report the actual passing output.

The runtime safely resolves the allowlisted `make` command and still requires explicit process approval. A harness must compare the requested executable semantically; it must not reject a safe request merely because the model emitted `make test` instead of `/usr/bin/make test`.

Use [PHYSICAL_REVALIDATION.md](PHYSICAL_REVALIDATION.md) for the focused Windows revalidation procedure. Its status remains PENDING until that physical run is completed.
