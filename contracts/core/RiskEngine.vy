# @version ^0.4.0
"""
@title RiskEngine
@notice Real-time cross-margin risk engine, dynamic haircut and portfolio health evaluator.
@dev Computes risk-weighted collateral value and total debt obligations against price oracle.
"""

interface IERC20Extended:
    def decimals() -> uint8: view
    def balanceOf(account: address) -> uint256: view

interface IPriceFeedRouter:
    def get_asset_price(asset: address) -> uint256: view

interface ICreditManager:
    def get_account_assets(account: address) -> DynArray[address, 16]: view
    def get_account_borrowed_assets(account: address) -> DynArray[address, 16]: view
    def get_account_debt(account: address, asset: address) -> uint256: view

interface ICreditAccount:
    def asset_balance(asset: address) -> uint256: view

owner: public(address)
price_router: public(address)
credit_manager: public(address)

# Risk parameters (in 18-decimal WAD)
# haircut_wad: e.g. 0.15 * 10^18 (15% discount for volatility risk)
# liquidation_threshold_wad: e.g. 0.85 * 10^18 (85% max borrowing power before liquidation)
# borrow_factor_wad: e.g. 1.00 * 10^18 (100% or higher for volatile borrows)
haircut_wad: public(HashMap[address, uint256])
liquidation_threshold_wad: public(HashMap[address, uint256])
borrow_factor_wad: public(HashMap[address, uint256])

WAD: constant(uint256) = 1_000_000_000_000_000_000
HEALTH_FACTOR_LIQUIDATION_THRESHOLD: constant(uint256) = 1_000_000_000_000_000_000 # 1.0 WAD

event RiskParametersSet:
    asset: indexed(address)
    haircut_wad: uint256
    liquidation_threshold_wad: uint256
    borrow_factor_wad: uint256

@deploy
def __init__(price_router_address: address):
    self.owner = msg.sender
    self.price_router = price_router_address

@external
def set_credit_manager(cm: address):
    assert msg.sender == self.owner, "RiskEngine: unauthorized"
    self.credit_manager = cm

@external
def set_asset_risk_parameters(
    asset: address,
    haircut: uint256,
    liq_threshold: uint256,
    borrow_factor: uint256
):
    assert msg.sender == self.owner, "RiskEngine: unauthorized"
    assert haircut < WAD, "RiskEngine: haircut >= 100%"
    assert liq_threshold <= WAD, "RiskEngine: threshold > 100%"
    assert borrow_factor >= WAD, "RiskEngine: borrow factor < 100%"

    self.haircut_wad[asset] = haircut
    self.liquidation_threshold_wad[asset] = liq_threshold
    self.borrow_factor_wad[asset] = borrow_factor
    log RiskParametersSet(
        asset=asset,
        haircut_wad=haircut,
        liquidation_threshold_wad=liq_threshold,
        borrow_factor_wad=borrow_factor
    )

@view
@internal
def _get_token_decimals(asset: address) -> uint8:
    return staticcall IERC20Extended(asset).decimals()

@view
@internal
def _scale_to_wad(amount: uint256, dec: uint8) -> uint256:
    if dec == 18:
        return amount
    elif dec < 18:
        mult: uint256 = 10 ** convert(18 - dec, uint256)
        return amount * mult
    else:
        div_val: uint256 = 10 ** convert(dec - 18, uint256)
        return amount // div_val

@view
@external
def compute_account_equity(account: address) -> (int256, uint256, uint256):
    """
    @notice Evaluates total collateral USD value and total debt USD value (both in WAD).
    @return equity_wad Net equity in USD (can be negative if underwater).
    @return total_collateral_usd Total market value of collateral in USD.
    @return total_debt_usd Total market value of debt in USD.
    """
    assert self.credit_manager != empty(address), "RiskEngine: credit manager not set"

    collateral_assets: DynArray[address, 16] = staticcall ICreditManager(self.credit_manager).get_account_assets(account)
    total_collateral_usd: uint256 = 0

    for asset: address in collateral_assets:
        bal: uint256 = staticcall ICreditAccount(account).asset_balance(asset)
        if bal > 0:
            dec: uint8 = self._get_token_decimals(asset)
            bal_wad: uint256 = self._scale_to_wad(bal, dec)
            price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(asset)
            asset_usd: uint256 = (bal_wad * price_wad) // WAD
            total_collateral_usd += asset_usd

    borrowed_assets: DynArray[address, 16] = staticcall ICreditManager(self.credit_manager).get_account_borrowed_assets(account)
    total_debt_usd: uint256 = 0

    for b_asset: address in borrowed_assets:
        debt_amount: uint256 = staticcall ICreditManager(self.credit_manager).get_account_debt(account, b_asset)
        if debt_amount > 0:
            dec: uint8 = self._get_token_decimals(b_asset)
            debt_wad: uint256 = self._scale_to_wad(debt_amount, dec)
            price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(b_asset)
            debt_usd: uint256 = (debt_wad * price_wad) // WAD
            total_debt_usd += debt_usd

    equity_wad: int256 = convert(total_collateral_usd, int256) - convert(total_debt_usd, int256)
    return (equity_wad, total_collateral_usd, total_debt_usd)

@view
@external
def compute_account_health(account: address) -> uint256:
    """
    @notice Computes Health Factor (HF) = Adjusted Collateral / Adjusted Debt.
    @dev Returns max_value(uint256) if debt is 0. Liquidatable if HF < 1.0 WAD.
    """
    assert self.credit_manager != empty(address), "RiskEngine: credit manager not set"

    collateral_assets: DynArray[address, 16] = staticcall ICreditManager(self.credit_manager).get_account_assets(account)
    adjusted_collateral: uint256 = 0

    for asset: address in collateral_assets:
        bal: uint256 = staticcall ICreditAccount(account).asset_balance(asset)
        if bal > 0:
            dec: uint8 = self._get_token_decimals(asset)
            bal_wad: uint256 = self._scale_to_wad(bal, dec)
            price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(asset)
            market_usd: uint256 = (bal_wad * price_wad) // WAD

            threshold: uint256 = self.liquidation_threshold_wad[asset]
            if threshold == 0:
                threshold = 850_000_000_000_000_000 # default 85%
            adj_val: uint256 = (market_usd * threshold) // WAD
            adjusted_collateral += adj_val

    borrowed_assets: DynArray[address, 16] = staticcall ICreditManager(self.credit_manager).get_account_borrowed_assets(account)
    adjusted_debt: uint256 = 0

    for b_asset: address in borrowed_assets:
        debt_amount: uint256 = staticcall ICreditManager(self.credit_manager).get_account_debt(account, b_asset)
        if debt_amount > 0:
            dec: uint8 = self._get_token_decimals(b_asset)
            debt_wad: uint256 = self._scale_to_wad(debt_amount, dec)
            price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(b_asset)
            debt_usd: uint256 = (debt_wad * price_wad) // WAD

            b_factor: uint256 = self.borrow_factor_wad[b_asset]
            if b_factor == 0:
                b_factor = WAD # default 100%
            adj_debt: uint256 = (debt_usd * b_factor) // WAD
            adjusted_debt += adj_debt

    if adjusted_debt == 0:
        return max_value(uint256)

    return (adjusted_collateral * WAD) // adjusted_debt

@view
@external
def is_account_liquidatable(account: address) -> bool:
    """
    @notice Returns True if account Health Factor < 1.0 WAD.
    """
    # Inline computation of health factor
    collateral_assets: DynArray[address, 16] = staticcall ICreditManager(self.credit_manager).get_account_assets(account)
    adjusted_collateral: uint256 = 0

    for asset: address in collateral_assets:
        bal: uint256 = staticcall ICreditAccount(account).asset_balance(asset)
        if bal > 0:
            dec: uint8 = self._get_token_decimals(asset)
            bal_wad: uint256 = self._scale_to_wad(bal, dec)
            price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(asset)
            market_usd: uint256 = (bal_wad * price_wad) // WAD
            threshold: uint256 = self.liquidation_threshold_wad[asset]
            if threshold == 0:
                threshold = 850_000_000_000_000_000
            adjusted_collateral += (market_usd * threshold) // WAD

    borrowed_assets: DynArray[address, 16] = staticcall ICreditManager(self.credit_manager).get_account_borrowed_assets(account)
    adjusted_debt: uint256 = 0

    for b_asset: address in borrowed_assets:
        debt_amount: uint256 = staticcall ICreditManager(self.credit_manager).get_account_debt(account, b_asset)
        if debt_amount > 0:
            dec: uint8 = self._get_token_decimals(b_asset)
            debt_wad: uint256 = self._scale_to_wad(debt_amount, dec)
            price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(b_asset)
            debt_usd: uint256 = (debt_wad * price_wad) // WAD
            b_factor: uint256 = self.borrow_factor_wad[b_asset]
            if b_factor == 0:
                b_factor = WAD
            adjusted_debt += (debt_usd * b_factor) // WAD

    if adjusted_debt == 0:
        return False

    return adjusted_collateral < adjusted_debt
