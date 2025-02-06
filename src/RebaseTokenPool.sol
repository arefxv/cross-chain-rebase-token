// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TokenPool, IERC20} from "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pool} from "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IRebaseToken} from "./IRebaseToken.sol";

/**
 * @title RebaseTokenPool
 * @author ArefXV
 *  @notice Implements a token pool for rebase tokens with burn, and mint functionalities
 */
contract RebaseTokenPool is TokenPool {

    /**
     * 
     * @notice Initializes the RebaseTokenPool contract
     * @param token The ERC20 token associated with this pool
     * @param allowList List of addresses allowed to interact with the pool
     * @param rmnProxy Address of the RMN Proxy
     * @param router Address of the router
     */
    constructor(IERC20 token, address[] memory allowList, address rmnProxy, address router)
        TokenPool(token, 18, allowList, rmnProxy, router)
    {}

    /**
     * 
     * @notice Locks or burns tokens for cross-chain transfers
     * @param lockOrBurnIn The input parameters for the lock or burn function
     * @return lockOrBurnOut Output data for the lock or burn function
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);

        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);

        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /**
     * 
     * @notice Releases or mints tokens after a cross-chain transfer
     * @param releaseOrMintIn The input parameters for the release or mint function
     * @return releaseOrMintOut Output data for the release or mint function
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        override
        returns (Pool.ReleaseOrMintOutV1 memory releaseOrMintOut)
    {
        _validateReleaseOrMint(releaseOrMintIn);
        address receiver = releaseOrMintIn.receiver;

        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
