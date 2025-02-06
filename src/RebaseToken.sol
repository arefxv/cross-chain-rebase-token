// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/access/AccessControl.sol";


/**
 * @title RebaseToken
 * @author ArefXV
 * @dev An ERC20 token with rebase functionality, interest rate accrual, and role-based minting and burning.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /*///////////////////////////////////////////////////////////////
                                ERRORS
    ///////////////////////////////////////////////////////////////*/
    /// @notice Error emitted when trying to increase the interest rate
    error RebaseToken__InterestRateCanOnlyDecrease(uint256, uint256);

    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ///////////////////////////////////////////////////////////////*/
    uint256 private s_interestRate = 5e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdateTimestamp;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    ///////////////////////////////////////////////////////////////*/
    /// @notice Event emitted when the interest rate is updated
    event InterestRateSet(uint256 indexed newInterestRate);

    /*///////////////////////////////////////////////////////////////
                                FUNCTIONS
    ///////////////////////////////////////////////////////////////*/
    /**
     * @dev Constructor initializes the ERC20 token and assigns ownership
     */
    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    /*///////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////*/
    /**
     * @notice Grants the MINT_AND_BURN_ROLE to a specified address
     * @param _address The address to be granted the role
     */
    function grantMintAndBurnRole(address _address) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _address);
    }

    /**
     * @notice Sets a new interest rate for the token
     * @dev The new interest rate must be lower than the current one
     * @param newInterestRate The new interest rate to be set
     */
    function setInterestRate(uint256 newInterestRate) external onlyOwner {
        if (newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, newInterestRate);
        }

        s_interestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    /*///////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the principal balance of a user (without interest accrual)
     * @param account The address of the user
     * @return The principal balance of the user
     */
    function principalBalanceOf(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @notice Mints new tokens and updates the user's interest rate
     * @param to The recipient of the minted tokens
     * @param amount The amount of tokens to mint
     * @param userInterestRate The interest rate for the recipient
     */
    function mint(address to, uint256 amount, uint256 userInterestRate) public onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruesInterest(to);
        s_userInterestRate[to] = userInterestRate;
        _mint(to, amount);
    }

    /**
     * @notice Burns a specified amount of tokens from an account
     * @param from The address from which tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) public onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruesInterest(from);
        _burn(from, amount);
    }

    /**
     * @notice Transfers tokens between addresses while accruing interest
     * @param recipient The recipient address
     * @param amount The amount of tokens to transfer
     * @return A boolean indicating success
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender);
        }

        _mintAccruesInterest(msg.sender);
        _mintAccruesInterest(recipient);

        if (balanceOf(recipient) == 0) {
            s_userInterestRate[recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (amount == type(uint256).max) {
            amount = balanceOf(sender);
        }

        _mintAccruesInterest(sender);
        _mintAccruesInterest(recipient);

        if (balanceOf(recipient) == 0) {
            s_userInterestRate[recipient] = s_userInterestRate[sender];
        }

        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @notice Returns the user's balance including accrued interest
     * @param user The address of the user
     * @return The updated balance of the user
     */
    function balanceOf(address user) public view override returns (uint256) {
        uint256 currentPrincipalBalance = super.balanceOf(user);

        if (currentPrincipalBalance == 0) {
            return 0;
        }

        return (currentPrincipalBalance * _calculateUserAccumulatedInterestSinceLastUpdate(user)) / PRECISION_FACTOR;
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////*/
    /**
     * @dev Internal function to update interest accrual before minting new tokens
     * @param user The user whose balance is updated
     */
    function _mintAccruesInterest(address user) internal {
        uint256 previousUserBalance = super.balanceOf(user);
        uint256 currentUserBalance = balanceOf(user);
        uint256 balanceIncrease = currentUserBalance - previousUserBalance;

        _mint(user, balanceIncrease);
        s_userLastUpdateTimestamp[user] = block.timestamp;
    }

    /**
     * @dev Calculates the interest accumulated since the last update
     * @param user The user whose interest is being calculated
     * @return The new balance with interest applied
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address user) internal view returns (uint256) {
        uint256 timeDifference = block.timestamp - s_userLastUpdateTimestamp[user];
        uint256 linearInterest = (s_userInterestRate[user] * timeDifference) + PRECISION_FACTOR;
        return linearInterest;
    }

    /*///////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getPrecisionFactor() external pure returns (uint256) {
        return PRECISION_FACTOR;
    }

    function getMintAndBurnRole() external pure returns (bytes32) {
        return MINT_AND_BURN_ROLE;
    }

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }

    function getUserTime(address user) external view returns (uint256) {
        return s_userLastUpdateTimestamp[user];
    }
}
