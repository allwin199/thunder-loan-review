// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AssetToken is ERC20 {
    error AssetToken__onlyThunderLoan();
    error AssetToken__ExhangeRateCanOnlyIncrease(uint256 oldExchangeRate, uint256 newExchangeRate);
    error AssetToken__ZeroAddress();

    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 private immutable i_underlying;
    address private immutable i_thunderLoan;

    // The underlying per asset exchange rate
    // ie: s_exchangeRate = 2
    // means 1 asset token is worth 2 underlying tokens
    // e underlying == USDC
    // e assetToken == LP (Liquidity Provider Token)
    // qanswered what does that rate do?
    // a it is the rate between underlying and asset token
    uint256 private s_exchangeRate;
    uint256 public constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 private constant STARTING_EXCHANGE_RATE = 1e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ExchangeRateUpdated(uint256 newExchangeRate);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyThunderLoan() {
        if (msg.sender != i_thunderLoan) {
            revert AssetToken__onlyThunderLoan();
        }
        _;
    }

    modifier revertIfZeroAddress(address someAddress) {
        if (someAddress == address(0)) {
            revert AssetToken__ZeroAddress();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address thunderLoan,
        IERC20 underlying, // e the token liquidity providers deposit for flash loans
        // qanswered why are we getting this information about `underlying`
        // qanswered are they stored in `AssetToken.sol` instead of `ThunderLoan.sol`
        // a the tokens are stored in the assetToken
        string memory assetName,
        string memory assetSymbol
    )
        ERC20(assetName, assetSymbol)
        revertIfZeroAddress(thunderLoan)
        revertIfZeroAddress(address(underlying))
    {
        i_thunderLoan = thunderLoan;
        i_underlying = underlying;
        // @audit-high STARTING_EXCHANGE_RATE is 1e18
        // but it should be 2e18
        // according to `s_exchangeRate` explanation
        s_exchangeRate = STARTING_EXCHANGE_RATE;
    }

    //
    function mint(address to, uint256 amount) external onlyThunderLoan {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyThunderLoan {
        _burn(account, amount);
    }

    function transferUnderlyingTo(address to, uint256 amount) external onlyThunderLoan {
        // weired erc20s???
        // qnotanswered what happens if USDC denylisted the thunderloan contract?
        // qnotanswered what happens if USDC denylisted the asset token contract?
        // @audit-medium the protocol will be fozen, and that would suck!!!
        i_underlying.safeTransfer(to, amount);
    }

    // e this `updateExchangeRate` is responsible for updating the exchnage rate of AssetToken -> Underlying
    function updateExchangeRate(uint256 fee) external onlyThunderLoan {
        // 1. Get the current exchange rate
        // 2. How big the fee is should be divided by the total supply
        // 3. So if the fee is 1e18, and the total supply is 2e18, the exchange rate be multiplied by 1.5
        // if the fee is 0.5 ETH, and the total supply is 4, the exchange rate should be multiplied by 1.125
        // it should always go up, never down -> INVARIANT!!!

        // qanswered why should `newExchangeRate` always go high?
        // if the `newExchangeRate` didn't go above than the previous
        // then liquidators will not make profit

        // newExchangeRate = oldExchangeRate * (totalSupply + fee) / totalSupply
        // newExchangeRate = 1 (4 + 0.5) / 4
        // newExchangeRate = 1.125

        // e whenver someone takes a flash loan
        // fee will be calculated for the flash loan
        // then `updateExchangeRate` will be called to update the exchange rate,
        // the reason we have to update the exchange rate is
        // someone took out a flash loan and paid it back with fee
        // that fee should go to the liquidity providers

        // let's say newExchangeRate = 1.125
        // totalSupply is 4
        // 4 * `newExchangeRate`
        // 4 * 1.125 = 4.5
        // therfore for depositing 4 tokens
        // this liquidator will get `0.5` tokens as profit if they withdraw right now
        // let's say 2 people deposited same underlying with 2 tokens each
        // then if they both withdraw they will get `0.25` tokens each

        // let's say none of them withdraw
        // one more flash loan was taken and fee was calculated and updateexchange rate is called
        // we already know newExchangeRate was 4.5 previously
        // which means that will the `oldExchangeRate` right now
        // and totalSupply increased to 4.5 last time
        // let's say fee is 0.5 again
        // let's calculate the `newExchangeRate`
        // newExchangeRate = oldExchangeRate * (totalSupply + fee) / totalSupply
        // newExchangeRate = 1.125 * (4.5 + 0.5) / 4.5
        // newExchangeRate = 1.25

        // totalSupply is 4.5
        // 4.5 * newExchangeRate
        // totalSupply = 5.625
        // this new totalSupply will be shared among all the liquidity providers
        // this is how they make profit

        // @audit-gas too many storage reads for `s_exchangeRate` -> cache it in memory
        uint256 newExchangeRate = s_exchangeRate * (totalSupply() + fee) / totalSupply();

        if (newExchangeRate <= s_exchangeRate) {
            revert AssetToken__ExhangeRateCanOnlyIncrease(s_exchangeRate, newExchangeRate);
        }
        s_exchangeRate = newExchangeRate;
        emit ExchangeRateUpdated(s_exchangeRate);
    }

    function getExchangeRate() external view returns (uint256) {
        return s_exchangeRate;
    }

    function getUnderlying() external view returns (IERC20) {
        return i_underlying;
    }
}
