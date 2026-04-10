def test_over_limit():
    """SPEC rate-limiting/fixed-window enforcement: rejects request 101"""
    # ...

def test_window_reset():
    """SPEC rate-limiting/fixed-window enforcement: allows requests after window reset"""
    # ...

def test_burst_flag():
    """SPEC rate-limiting/burst detection: flags 3x spike"""
    # ...

def test_gradual_ramp_not_flagged():
    """SPEC rate-limiting/burst detection: gradual ramp is not flagged"""
    # ...
