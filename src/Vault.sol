// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IRebaseToken} from "./IRebaseToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console2} from "forge-std/console2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Vault
 * @author ArefXV
 * @notice A vault contract for depositing and redeeming rebase tokens
 */
contract Vault is ReentrancyGuard, Ownable {
    error Vault__AmountMustBeMoreThanZero();
    error Vault__RedeemFailed();
    error Vault__InsufficientBalance();

    IRebaseToken private immutable i_RebaseToken;

    event Deposited(address indexed user, uint256 indexed amount);
    event Redeemed(address indexed user, uint256 indexed amount);

    /**
     * @notice Initializes the vault contract
     * @param rebaseToken The rebase token used in the vault
     */
    constructor(IRebaseToken rebaseToken) Ownable(msg.sender) {
        i_RebaseToken = rebaseToken;
    }

    receive() external payable {}

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert Vault__AmountMustBeMoreThanZero();
        }
        _;
    }

    /// @notice Deposits ETH and mints corresponding rebase tokens
    function deposit() external payable moreThanZero(msg.value) {
        i_RebaseToken.mint(msg.sender, msg.value, i_RebaseToken.getInterestRate());
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Redeems rebase tokens for ETH
     * @param amount The amount of tokens to redeem
     */
    function redeem(uint256 amount) external nonReentrant moreThanZero(amount) {
        if (amount == type(uint256).max) {
            amount = i_RebaseToken.balanceOf(msg.sender);
        }

        if (amount > i_RebaseToken.balanceOf(msg.sender)) {
            revert Vault__InsufficientBalance();
        }

        i_RebaseToken.burn(msg.sender, amount);

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }

        emit Redeemed(msg.sender, amount);
    }

    function emergWithdraw(uint256 amount) external onlyOwner {
        (bool success,) = payable(owner()).call{value: amount}("");
        (success);
    }
}
