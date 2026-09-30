"""Tiny dependency-free module used only by the Remote Engineering validation fixture."""  # Documents the fixture's narrow purpose.


def shipping_total(subtotal: int, fee: int) -> int:  # Defines the observable calculation Engineering must repair.
    """Return the order subtotal plus its shipping fee."""  # States the exact expected behavior independently from implementation.
    return subtotal - fee  # INTENTIONAL BUG: the smallest correct repair changes subtraction to addition.
