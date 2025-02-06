// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {IRebaseToken} from "../../src/IRebaseToken.sol";
import {EtherRejector} from "../helper/EtherRejector.sol";

contract RebaseTokenAndVaultTest is Test {
    RebaseToken token;
    Vault vault;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 valueToSend = 1e5;

    function addRewardsToVault(uint256 amount) public {
        (bool success,) = payable(address(vault)).call{value: amount}("");
        (success);
    }

    function setUp() external {
        vm.prank(address(this));
        token = new RebaseToken();
        vault = new Vault(IRebaseToken(address(token)));
        token.grantMintAndBurnRole(address(vault));
        vm.stopPrank;
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        uint256 startingBalance = token.balanceOf(user);

        assertEq(startingBalance, amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = token.balanceOf(user);

        assertGt(middleBalance, startingBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endingBalance = token.balanceOf(user);

        assertGt(endingBalance, middleBalance);

        assertApproxEqAbs(endingBalance - middleBalance, middleBalance - startingBalance, 1);
    }

    function testDepositFailsIfDepositAmountIsZero(uint256 amount) public {
        amount = bound(amount, 0, 0);

        vm.startPrank(user);
        vm.deal(user, amount);

        vm.expectRevert(Vault.Vault__AmountMustBeMoreThanZero.selector);
        vault.deposit{value: amount}();
    }

    function testRedeemFailsIfAmountIsInvalid(uint256 amount) public {
        console2.log("contract balance before", address(vault).balance);
        amount = bound(amount, 1e6, type(uint96).max);

        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: 1e5}();
        console2.log("contract balance after", address(vault).balance);
        console2.log("user balance", token.balanceOf(user));

        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(Vault.Vault__InsufficientBalance.selector);
        vault.redeem(amount);
    }

    function testUserCanRedeem(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        vault.redeem(amount);
        uint256 userBalance = token.balanceOf(user);

        assertEq(userBalance, 0);
        vm.stopPrank();
    }

    function testRedeemFailsWhenTransferFails(uint256 amount) public {
        EtherRejector rejector = new EtherRejector();

        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(address(rejector), amount);

        vm.startPrank(address(rejector));
        vault.deposit{value: amount}();

        vm.expectRevert(Vault.Vault__RedeemFailed.selector);
        vault.redeem(amount);
        vm.stopPrank();
    }

    function testOwnerCanWithdraw(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        vm.stopPrank();

        vm.prank(address(this));
        vault.emergWithdraw(amount);
        uint256 contractBalance = token.balanceOf(address(vault));
        assertEq(contractBalance, 0);
    }

    function testNonOwnerCannotWithdraw(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint256).max);

        vm.prank(user);
        vm.deal(user, amount);
        vm.expectRevert();
        vault.emergWithdraw(amount);
    }

    function testRedeemAferTimeHasPassed(uint256 time, uint256 depositAmount) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        vm.warp(time);

        uint256 userBalance = token.balanceOf(user);
        uint256 reward = userBalance - depositAmount;

        vm.deal(owner, reward);
        vm.prank(owner);
        addRewardsToVault(reward);

        vm.prank(user);
        vault.redeem(userBalance);

        uint256 userEthBalance = user.balance;

        assertEq(userBalance, userEthBalance);
        assertGt(userBalance, depositAmount);
    }

    function testOwnerSetNewInterestRate(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, type(uint96).min, 5e9);
        uint256 interestRateBefore = token.getInterestRate();

        vm.prank(address(this));
        token.setInterestRate(newInterestRate);

        uint256 interestRateAfter = token.getInterestRate();

        assertLt(interestRateAfter, interestRateBefore);
    }

    function testNewInterestRateCantIncrease(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, 5e10, type(uint96).max);
        uint256 priviousInterestRate = token.getInterestRate();

        vm.prank(address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, priviousInterestRate, newInterestRate
            )
        );
        token.setInterestRate(newInterestRate);
    }

    function testUserCannotMint(uint256 amount) public {
        amount = bound(amount, type(uint96).min, type(uint96).max);
        uint256 userinterestRate = token.getUserInterestRate(user);

        vm.deal(user, amount);
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, amount, userinterestRate);
    }

    function testUserCannotBurn(uint256 amount) public {
        amount = bound(amount, type(uint96).min, type(uint96).max);

        vm.deal(user, amount);
        vm.prank(user);
        vm.expectRevert();
        token.burn(user, amount);
    }

    function testAllowedRoleCanMintAndBurn(uint256 amount) public {
        amount = bound(amount, type(uint96).min, type(uint96).max);
        uint256 userinterestRate = token.getUserInterestRate(user);

        address newRole = makeAddr("newRole");
        vm.prank(address(this));
        token.grantMintAndBurnRole(newRole);

        vm.startPrank(newRole);
        token.mint(user, amount, userinterestRate);
        uint256 userBalanceAfterMint = token.balanceOf(user);

        token.burn(user, amount);
        uint256 userBalanceAfterBurn = token.balanceOf(user);
        vm.stopPrank();

        assertEq(userBalanceAfterMint, amount);
        assertEq(userBalanceAfterBurn, 0);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);
        address receiver = makeAddr("receiver");

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 userBalance = token.balanceOf(user);
        uint256 receiverBalance = token.balanceOf(receiver);

        assertEq(userBalance, amount);
        assertEq(receiverBalance, 0);

        uint256 priviousInterestRate = token.getInterestRate();

        vm.prank(address(this));
        token.setInterestRate(4e10);

        uint256 newInterestRate = token.getInterestRate();

        assertLt(newInterestRate, priviousInterestRate);

        vm.prank(user);
        token.transfer(receiver, amountToSend);

        uint256 userBalanceAfterTransfer = token.balanceOf(user);
        uint256 receiverBalanceAfterTransfer = token.balanceOf(receiver);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(receiverBalanceAfterTransfer, receiverBalance + amountToSend);

        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = token.balanceOf(user);
        uint256 receiverBalanceAfterWarp = token.balanceOf(receiver);

        uint256 receiverInterestRate = token.getUserInterestRate(receiver);
        assertEq(receiverInterestRate, priviousInterestRate);

        uint256 userInterestRate = token.getUserInterestRate(user);
        assertEq(userInterestRate, priviousInterestRate);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(receiverBalanceAfterWarp, receiverBalanceAfterTransfer);
    }

    function testTransferFrom(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);
        address receiver = makeAddr("receiver");

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 userBalance = token.balanceOf(user);
        uint256 receiverBalance = token.balanceOf(receiver);

        assertEq(userBalance, amount);
        assertEq(receiverBalance, 0);

        uint256 priviousInterestRate = token.getInterestRate();

        vm.prank(address(this));
        token.setInterestRate(4e10);

        uint256 newInterestRate = token.getInterestRate();

        assertLt(newInterestRate, priviousInterestRate);

        vm.prank(user);
        token.approve(user, amountToSend);

        vm.prank(user);
        token.transferFrom(user, receiver, amountToSend);

        uint256 userBalanceAfterTransfer = token.balanceOf(user);
        uint256 receiverBalanceAfterTransfer = token.balanceOf(receiver);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(receiverBalanceAfterTransfer, receiverBalance + amountToSend);

        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = token.balanceOf(user);
        uint256 receiverBalanceAfterWarp = token.balanceOf(receiver);

        uint256 receiverInterestRate = token.getUserInterestRate(receiver);
        assertEq(receiverInterestRate, priviousInterestRate);

        uint256 userInterestRate = token.getUserInterestRate(user);
        assertEq(userInterestRate, priviousInterestRate);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(receiverBalanceAfterWarp, receiverBalanceAfterTransfer);
    }
}
