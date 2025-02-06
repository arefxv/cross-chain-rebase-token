// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {IRebaseToken} from "../../src/IRebaseToken.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";

contract VaultAndRebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public USER = makeAddr("user");
    uint256 public constant USER_BALANCE = 10 ether;
    uint256 public constant SEND_VALUE = 1 ether;
    uint256 amountToSend = 1e5;

    uint256 private interestRate = 5e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    event Deposited(address indexed user, uint256 indexed amount);
    event Redeemed(address indexed user, uint256 indexed amount);

    function setUp() external {
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));

        vm.deal(USER, USER_BALANCE);
    }

    function testUserCanDeposit() public {
        uint256 startingContractBalance = address(vault).balance;
        vm.prank(USER);
        vault.deposit{value: SEND_VALUE}();

        uint256 endingContractBalance = address(vault).balance;

        assertGt(endingContractBalance, startingContractBalance);
    }

    function testDepositFailsIfAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert();
        vault.deposit();
    }

    function testDepositingEmitsAnEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Deposited(USER, SEND_VALUE);

        vm.prank(USER);
        vault.deposit{value: SEND_VALUE}();
    }

    function testUserCanRedeem() public {
        uint256 stUserBalance = rebaseToken.balanceOf(USER);
        assert(stUserBalance == 0);

        vm.prank(USER);
        vault.deposit{value: SEND_VALUE}();

        uint256 userInterestRate = rebaseToken.getUserInterestRate(USER);

        vm.prank(address(vault));
        rebaseToken.mint(USER, amountToSend, userInterestRate);

        vm.prank(USER);
        vault.redeem(SEND_VALUE);

        uint256 endUserBalance = rebaseToken.balanceOf(USER);
        console2.log("endUserBalance", endUserBalance);

        assertEq(endUserBalance, amountToSend);
    }

    function testPrincipalBalanceOf() public {
        uint256 stBalance = rebaseToken.principalBalanceOf(USER);
        console2.log("stBalance", stBalance);

        vm.prank(USER);
        vault.deposit{value: SEND_VALUE}();

        uint256 endBalance = rebaseToken.principalBalanceOf(USER);

        assertEq(stBalance, 0);
        assertEq(endBalance, SEND_VALUE);
    }

    function testRedeemWithMax() public {
        vm.startPrank(USER);
        vm.deal(USER, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();

        vault.redeem(type(uint256).max);
        uint256 balance = rebaseToken.balanceOf(USER);
        assert(balance == 0);
    }

    function testNonOwnerCantGrantRole() public {
        vm.prank(USER);
        vm.expectRevert();
        rebaseToken.grantMintAndBurnRole(USER);
    }

    function testTransferMaxBalance() public {
        address receiver = makeAddr("receiver");

        vm.prank(USER);
        vault.deposit{value: SEND_VALUE}();
        uint256 startUserBalance = rebaseToken.balanceOf(USER);
        uint256 startReceiverBalance = rebaseToken.balanceOf(receiver);

        vm.prank(USER);
        rebaseToken.transfer(receiver, type(uint256).max);
        uint256 endUserBalance = rebaseToken.balanceOf(USER);
        uint256 endReceiverBalance = rebaseToken.balanceOf(receiver);

        assertEq(endUserBalance, 0);
        assertEq(endReceiverBalance, startUserBalance);
        assertEq(startReceiverBalance, 0);
    }

    function testTransferFromMaxBalance() public {
        address receiver = makeAddr("receiver");

        vm.prank(USER);
        vault.deposit{value: SEND_VALUE}();
        uint256 startUserBalance = rebaseToken.balanceOf(USER);
        uint256 startReceiverBalance = rebaseToken.balanceOf(receiver);

        vm.startPrank(USER);
        rebaseToken.approve(USER, SEND_VALUE);
        rebaseToken.transferFrom(USER, receiver, type(uint256).max);
        vm.stopPrank();

        uint256 endUserBalance = rebaseToken.balanceOf(USER);
        uint256 endReceiverBalance = rebaseToken.balanceOf(receiver);

        assertEq(endUserBalance, 0);
        assertEq(endReceiverBalance, startUserBalance);
        assertEq(startReceiverBalance, 0);
    }

    function testGettersWork() public view {
        uint256 _interestRate = rebaseToken.getInterestRate();
        assertEq(_interestRate, interestRate);

        uint256 precisionFactor = rebaseToken.getPrecisionFactor();
        assertEq(precisionFactor, PRECISION_FACTOR);

        bytes32 role = rebaseToken.getMintAndBurnRole();
        assertEq(role, MINT_AND_BURN_ROLE);

        uint256 userInterestRate = rebaseToken.getUserInterestRate(USER);
        assertEq(userInterestRate, 0);

        uint256 time = rebaseToken.getUserTime(USER);
        assertEq(time, 0);
    }
}
