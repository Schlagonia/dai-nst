// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface NstDai {
    function daiToNst(address usr, uint256 wad) external;

    function nstToDai(address usr, uint256 wad) external;

    function nst() external view returns (address);
}

contract Strategy is BaseStrategy, AuctionSwapper {
    using SafeERC20 for ERC20;

    address public immutable nst;
    address public immutable nstDai;

    mapping(address => uint256) public minAmountToSellMapping;

    constructor(
        address _asset,
        string memory _name,
        address _nstDai
    ) BaseStrategy(_asset, _name) {
        nstDai = _nstDai;
        nst = NstDai(_nstDai).nst();
        asset.approve(_nstDai, 2**256 - 1);
        ERC20(nst).approve(_nstDai, 2**256 - 1);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        NstDai(nstDai).daiToNst(address(this), _amount);
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        NstDai(nstDai).nstToDai(address(this), _amount);
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets =
            asset.balanceOf(address(this)) +
            ERC20(nst).balanceOf(address(this));
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = Math.min(_amount, ERC20(nst).balanceOf(address(this)));
        _freeFunds(_amount);
    }

    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            require(Auction(_auction).want() == address(asset), "wrong want");
        }
        auction = _auction;
    }

    function _auctionKicked(address _token)
        internal
        virtual
        override
        returns (uint256 _kicked)
    {
        require(_token != address(asset) && _token != nst, "!allowed");
        _kicked = super._auctionKicked(_token);
        require(_kicked >= minAmountToSellMapping[_token], "too little");
    }

    function setMinAmountToSellMapping(address _token, uint256 _amount)
        external
        onlyManagement
    {
        minAmountToSellMapping[_token] = _amount;
    }
}
