# @version ^0.4.0
"""
@title DebtEngine
@notice Structured multi-tranche capital waterfall and dynamic kinked jump-rate model.
@dev Partitions capital into Senior (AAA), Mezzanine (BBB), and Junior (Equity) tranches.
"""

from ethereum.ercs import IERC20

owner: public(address)
vault: public(address)
credit_manager: public(address)

# Tranche IDs
SENIOR_TRANCHE: constant(uint256) = 0
MEZZANINE_TRANCHE: constant(uint256) = 1
JUNIOR_TRANCHE: constant(uint256) = 2

# Accounting per asset per tranche: asset => tranche_id => amount
tranche_assets: public(HashMap[address, HashMap[uint256, uint256]])
tranche_shares: public(HashMap[address, HashMap[uint256, uint256]])
user_tranche_shares: public(HashMap[address, HashMap[uint256, HashMap[address, uint256]]])

# Interest rate model parameters (in 18-decimal WAD)
# Base rate: 2% (0.02 WAD)
# Optimal utilization kink: 80% (0.80 WAD)
# Slope 1: 4% (0.04 WAD)
# Slope 2 (jump multiplier): 60% (0.60 WAD)
base_rate_wad: public(HashMap[address, uint256])
kink_utilization_wad: public(HashMap[address, uint256])
slope1_wad: public(HashMap[address, uint256])
slope2_wad: public(HashMap[address, uint256])

# Cumulative interest index in RAY (27 decimals)
borrow_index_ray: public(HashMap[address, uint256])
last_accrual_timestamp: public(HashMap[address, uint256])
total_borrowed_assets: public(HashMap[address, uint256])

WAD: constant(uint256) = 1_000_000_000_000_000_000
RAY: constant(uint256) = 1_000_000_000_000_000_000_000_000_000
SECONDS_PER_YEAR: constant(uint256) = 31_536_000

event TrancheDeposited:
    asset: indexed(address)
    tranche_id: indexed(uint256)
    user: indexed(address)
    assets: uint256
    shares: uint256

event TrancheWithdrawn:
    asset: indexed(address)
    tranche_id: indexed(uint256)
    user: indexed(address)
    assets: uint256
    shares: uint256

event InterestAccrued:
    asset: indexed(address)
    borrow_rate_wad: uint256
    new_index_ray: uint256

event BadDebtAbsorbed:
    asset: indexed(address)
    junior_loss: uint256
    mezz_loss: uint256
    senior_loss: uint256

@deploy
def __init__(vault_address: address):
    self.owner = msg.sender
    self.vault = vault_address

@external
def set_credit_manager(cm: address):
    assert msg.sender == self.owner, "DebtEngine: unauthorized"
    self.credit_manager = cm

@external
def configure_interest_model(
    asset: address,
    base_rate: uint256,
    kink_util: uint256,
    slope1: uint256,
    slope2: uint256
):
    assert msg.sender == self.owner, "DebtEngine: unauthorized"
    assert kink_util < WAD, "DebtEngine: kink >= 100%"
    assert kink_util > 0, "DebtEngine: kink is zero"

    self.base_rate_wad[asset] = base_rate
    self.kink_utilization_wad[asset] = kink_util
    self.slope1_wad[asset] = slope1
    self.slope2_wad[asset] = slope2

    if self.borrow_index_ray[asset] == 0:
        self.borrow_index_ray[asset] = RAY
        self.last_accrual_timestamp[asset] = block.timestamp

@view
@external
def get_total_supply(asset: address) -> uint256:
    return (
        self.tranche_assets[asset][SENIOR_TRANCHE] +
        self.tranche_assets[asset][MEZZANINE_TRANCHE] +
        self.tranche_assets[asset][JUNIOR_TRANCHE]
    )

@view
@external
def get_utilization_rate(asset: address) -> uint256:
    total_supply: uint256 = (
        self.tranche_assets[asset][SENIOR_TRANCHE] +
        self.tranche_assets[asset][MEZZANINE_TRANCHE] +
        self.tranche_assets[asset][JUNIOR_TRANCHE]
    )
    if total_supply == 0:
        return 0
    borrowed: uint256 = self.total_borrowed_assets[asset]
    return (borrowed * WAD) // total_supply

@view
@external
def get_borrow_rate(asset: address) -> uint256:
    """
    @notice Evaluates continuous annual borrow rate using the two-slope jump model.
    """
    u: uint256 = self._get_utilization_rate(asset)
    kink: uint256 = self.kink_utilization_wad[asset]
    base: uint256 = self.base_rate_wad[asset]
    s1: uint256 = self.slope1_wad[asset]
    s2: uint256 = self.slope2_wad[asset]

    if kink == 0:
        kink = 800_000_000_000_000_000 # default 80%
    if s1 == 0:
        s1 = 40_000_000_000_000_000 # default 4%
    if s2 == 0:
        s2 = 600_000_000_000_000_000 # default 60%

    if u <= kink:
        return base + (u * s1) // kink
    else:
        excess: uint256 = u - kink
        range_rem: uint256 = WAD - kink
        return base + s1 + (excess * s2) // range_rem

@view
@internal
def _get_utilization_rate(asset: address) -> uint256:
    total_supply: uint256 = (
        self.tranche_assets[asset][SENIOR_TRANCHE] +
        self.tranche_assets[asset][MEZZANINE_TRANCHE] +
        self.tranche_assets[asset][JUNIOR_TRANCHE]
    )
    if total_supply == 0:
        return 0
    borrowed: uint256 = self.total_borrowed_assets[asset]
    return (borrowed * WAD) // total_supply

@view
@external
def get_tranche_supply(asset: address, tranche_id: uint256) -> uint256:
    return self.tranche_assets[asset][tranche_id]

@view
@external
def get_tranche_share_price(asset: address, tranche_id: uint256) -> uint256:
    shares: uint256 = self.tranche_shares[asset][tranche_id]
    assets: uint256 = self.tranche_assets[asset][tranche_id]
    if shares == 0 or assets == 0:
        return WAD
    return (assets * WAD) // shares

@external
def deposit_tranche(
    asset: address,
    tranche_id: uint256,
    amount: uint256,
    receiver: address
) -> uint256:
    assert tranche_id <= JUNIOR_TRANCHE, "DebtEngine: invalid tranche"
    assert amount > 0, "DebtEngine: zero deposit"

    shares: uint256 = 0
    curr_shares: uint256 = self.tranche_shares[asset][tranche_id]
    curr_assets: uint256 = self.tranche_assets[asset][tranche_id]

    if curr_shares == 0 or curr_assets == 0:
        shares = amount
    else:
        shares = (amount * curr_shares) // curr_assets

    self.tranche_assets[asset][tranche_id] = curr_assets + amount
    self.tranche_shares[asset][tranche_id] = curr_shares + shares
    self.user_tranche_shares[asset][tranche_id][receiver] += shares

    # Transfer tokens from caller to vault
    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self.vault, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "DebtEngine: deposit transfer failed"

    log TrancheDeposited(
        asset=asset,
        tranche_id=tranche_id,
        user=receiver,
        assets=amount,
        shares=shares
    )
    return shares

@external
def withdraw_tranche(
    asset: address,
    tranche_id: uint256,
    shares: uint256,
    receiver: address
) -> uint256:
    assert tranche_id <= JUNIOR_TRANCHE, "DebtEngine: invalid tranche"
    assert shares > 0, "DebtEngine: zero withdrawal"

    user_shares: uint256 = self.user_tranche_shares[asset][tranche_id][msg.sender]
    assert user_shares >= shares, "DebtEngine: insufficient shares"

    total_shares: uint256 = self.tranche_shares[asset][tranche_id]
    total_assets: uint256 = self.tranche_assets[asset][tranche_id]

    assets_out: uint256 = (shares * total_assets) // total_shares
    assert assets_out > 0, "DebtEngine: zero asset out"

    self.user_tranche_shares[asset][tranche_id][msg.sender] = user_shares - shares
    self.tranche_shares[asset][tranche_id] = total_shares - shares
    self.tranche_assets[asset][tranche_id] = total_assets - assets_out

    # Transfer tokens from vault to receiver
    call_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(receiver, bytes32),
        convert(assets_out, bytes32)
    )
    # Trigger vault to release capital
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "DebtEngine: withdrawal transfer failed"

    log TrancheWithdrawn(
        asset=asset,
        tranche_id=tranche_id,
        user=msg.sender,
        assets=assets_out,
        shares=shares
    )
    return assets_out

@external
def distribute_cashflow(asset: address, amount: uint256):
    """
    @notice Distributes interest / yield according to waterfall priority:
    1. Senior tranche fixed return (target: 3% of senior principal)
    2. Mezzanine tranche variable return (target: 7% of mezz principal)
    3. Junior tranche captures 100% of the remaining surplus!
    """
    assert amount > 0, "DebtEngine: zero distribution"

    rem: uint256 = amount
    sen_assets: uint256 = self.tranche_assets[asset][SENIOR_TRANCHE]
    mezz_assets: uint256 = self.tranche_assets[asset][MEZZANINE_TRANCHE]

    # Senior target coupon: 3% annualized pro-rata
    sen_quota: uint256 = (sen_assets * 3) // 100
    sen_pay: uint256 = 0
    if rem >= sen_quota:
        sen_pay = sen_quota
        rem -= sen_quota
    else:
        sen_pay = rem
        rem = 0
    self.tranche_assets[asset][SENIOR_TRANCHE] += sen_pay

    # Mezzanine target coupon: 7% annualized pro-rata
    if rem > 0:
        mezz_quota: uint256 = (mezz_assets * 7) // 100
        mezz_pay: uint256 = 0
        if rem >= mezz_quota:
            mezz_pay = mezz_quota
            rem -= mezz_quota
        else:
            mezz_pay = rem
            rem = 0
        self.tranche_assets[asset][MEZZANINE_TRANCHE] += mezz_pay

    # Residual surplus flows completely to Junior tranche (first-loss equity upside)
    if rem > 0:
        self.tranche_assets[asset][JUNIOR_TRANCHE] += rem

@external
def absorb_bad_debt(asset: address, amount: uint256) -> (uint256, uint256, uint256):
    """
    @notice Absorbs liquidation deficit through structured loss waterfall:
    1. Junior tranche absorbs loss first.
    2. Mezzanine tranche absorbs subsequent loss if Junior is wiped out.
    3. Senior tranche absorbs remaining loss only in catastrophic insolvency.
    """
    assert msg.sender == self.credit_manager or msg.sender == self.owner, "DebtEngine: unauthorized"
    rem_loss: uint256 = amount

    # Step 1: Junior loss absorption
    junior_assets: uint256 = self.tranche_assets[asset][JUNIOR_TRANCHE]
    junior_loss: uint256 = 0
    if rem_loss >= junior_assets:
        junior_loss = junior_assets
        rem_loss -= junior_assets
        self.tranche_assets[asset][JUNIOR_TRANCHE] = 0
    else:
        junior_loss = rem_loss
        self.tranche_assets[asset][JUNIOR_TRANCHE] -= rem_loss
        rem_loss = 0

    # Step 2: Mezzanine loss absorption
    mezz_loss: uint256 = 0
    if rem_loss > 0:
        mezz_assets: uint256 = self.tranche_assets[asset][MEZZANINE_TRANCHE]
        if rem_loss >= mezz_assets:
            mezz_loss = mezz_assets
            rem_loss -= mezz_assets
            self.tranche_assets[asset][MEZZANINE_TRANCHE] = 0
        else:
            mezz_loss = rem_loss
            self.tranche_assets[asset][MEZZANINE_TRANCHE] -= rem_loss
            rem_loss = 0

    # Step 3: Senior loss absorption
    senior_loss: uint256 = 0
    if rem_loss > 0:
        senior_assets: uint256 = self.tranche_assets[asset][SENIOR_TRANCHE]
        if rem_loss >= senior_assets:
            senior_loss = senior_assets
            self.tranche_assets[asset][SENIOR_TRANCHE] = 0
        else:
            senior_loss = rem_loss
            self.tranche_assets[asset][SENIOR_TRANCHE] -= rem_loss

    log BadDebtAbsorbed(
        asset=asset,
        junior_loss=junior_loss,
        mezz_loss=mezz_loss,
        senior_loss=senior_loss
    )
    return (junior_loss, mezz_loss, senior_loss)
