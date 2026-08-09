"""
Guards that lock in two promises so a future change can't quietly break them:

  1. The coin ledger is CLOSED-LOOP — no reason converts coins back to money. This
     is the property that keeps coins a virtual currency (not e-money / gambling).
     If someone adds a 'cashout' reason later, this test fails loudly.
  2. Regions are well-formed (unique codes), since region_code is a stable key used
     by both profiles and the region leaderboard.
"""
from app.core.regions import REGION_CODES, REGIONS
from app.services import coins


def test_coin_ledger_is_closed_loop():
    forbidden = {"cashout", "withdraw", "transfer", "redeem_cash", "payout",
                 "refund_to_money", "convert"}
    all_reasons = coins.EARN_REASONS | coins.SPEND_REASONS
    assert forbidden.isdisjoint(all_reasons), (
        "a money-out coin reason was introduced — this turns coins into e-money / "
        "gambling and needs legal sign-off, not a code change")


def test_earn_and_spend_reasons_disjoint():
    assert coins.EARN_REASONS.isdisjoint(coins.SPEND_REASONS)


def test_regions_unique_and_complete():
    codes = [r["code"] for r in REGIONS]
    assert len(codes) == len(set(codes))          # no dup codes
    assert len(REGIONS) == 14                       # 12 viloyat + Karakalpakstan + Tashkent city
    assert REGION_CODES == set(codes)
    for r in REGIONS:                               # every region localized
        assert r["uz"] and r["ru"]
