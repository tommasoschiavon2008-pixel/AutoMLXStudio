"""Deterministic standard-library verification for the intentional shipping bug."""  # Documents the test's offline scope.

from shipping import shipping_total  # Imports only the fixture function from the same local directory.


def main() -> None:  # Defines one bounded test entrypoint without a third-party runner.
    actual = shipping_total(12, 3)  # Executes the exact observable behavior under test.
    expected = 15  # Records the required result explicitly so equivalent-looking wrong expressions cannot pass.
    if actual != expected:  # Detects the intentional baseline bug deterministically.
        raise SystemExit(f"FAIL: shipping_total(12, 3) returned {actual}; expected {expected}")  # Returns a concise nonzero test-process failure.
    print("PASS: shipping_total(12, 3) == 15")  # Emits fixed success evidence only after the exact assertion passes.


if __name__ == "__main__":  # Runs the bounded test only when invoked as the fixture script.
    main()  # Executes the deterministic assertion and returns immediately.
