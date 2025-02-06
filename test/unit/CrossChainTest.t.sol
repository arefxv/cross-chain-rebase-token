// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {IRebaseToken} from "../src/IRebaseToken.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from
    "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenPool, IERC20} from "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink-local/lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";


contract CrossChainTest is Test {
    address USER = makeAddr("user");
    uint256 SEND_VALUE = 5e10;
    uint256 USER_BALANCE = 10 ether;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    RebaseToken sourceRebaseToken;
    RebaseToken destRebaseToken;

    RebaseTokenPool sourcePool;
    RebaseTokenPool destPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomArbSepolia;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryArbSepolia;

    Vault vault;

    function setUp() external {
        address[] memory allowlist = new address[](0);

        sepoliaFork = vm.createSelectFork("eth");
        arbSepoliaFork = vm.createFork("arb");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(address(this));

        sourceRebaseToken = new RebaseToken();

        sourcePool = new RebaseTokenPool(
            IERC20(address(sourceRebaseToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        vault = new Vault(IRebaseToken(address(sourceRebaseToken)));

        vm.deal(address(vault), 1e18);

        sourceRebaseToken.grantMintAndBurnRole(address(sourcePool));
        sourceRebaseToken.grantMintAndBurnRole(address(vault));

        registryModuleOwnerCustomSepolia =
            RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);

        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sourceRebaseToken));

        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);

        tokenAdminRegistrySepolia.acceptAdminRole(address(sourceRebaseToken));
        tokenAdminRegistrySepolia.setPool(address(sourceRebaseToken), address(sourcePool));

        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        vm.startPrank(address(this));

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        destRebaseToken = new RebaseToken();

        destPool = new RebaseTokenPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        destRebaseToken.grantMintAndBurnRole(address(destPool));

        registryModuleOwnerCustomArbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);

        registryModuleOwnerCustomArbSepolia.registerAdminViaOwner(address(destRebaseToken));

        tokenAdminRegistryArbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);

        tokenAdminRegistryArbSepolia.acceptAdminRole(address(destRebaseToken));
        tokenAdminRegistryArbSepolia.setPool(address(destRebaseToken), address(destPool));

        vm.stopPrank();

        vm.deal(USER, USER_BALANCE);
    }

    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        RebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(address(this));
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddress = new bytes[](1);
        remotePoolAddress[0] = abi.encode(address(remotePool));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddress,
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        localPool.applyChainUpdates(remoteChainSelectorsToRemove, chains);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        vm.startPrank(USER);
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        tokenToSendDetails[0] = tokenAmount;

        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(USER),
            data: "",
            tokenAmounts: tokenToSendDetails,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: ""
        });

        vm.stopPrank();

        ccipLocalSimulatorFork.requestLinkFromFaucet(
            USER, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );

        vm.startPrank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(
            (localNetworkDetails.routerAddress),
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );

        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(USER);
        console2.log("Local balance before bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 balanceAfterBridge = IERC20(address(localToken)).balanceOf(USER);
        console2.log("Local balance after bridge: %d", balanceAfterBridge);

        assertEq(balanceAfterBridge, balanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 900);

        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(USER);
        console2.log("Remote balance before bridge: %d", initialArbBalance);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(USER);
        console2.log("Remote balance after bridge: %d", destBalance);

        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    function testBridgeAllTokens() public {
        configureTokenPool(sepoliaFork, sourcePool, destPool, destRebaseToken, arbSepoliaNetworkDetails);

        configureTokenPool(arbSepoliaFork, destPool, sourcePool, sourceRebaseToken, sepoliaNetworkDetails);

        vm.selectFork(sepoliaFork);

        vm.startPrank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(USER);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();

        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
    }

    function testBridgeAllTokensBack() public {
        configureTokenPool(sepoliaFork, sourcePool, destPool, destRebaseToken, arbSepoliaNetworkDetails);

        configureTokenPool(arbSepoliaFork, destPool, sourcePool, sourceRebaseToken, sepoliaNetworkDetails);

        vm.selectFork(sepoliaFork);
        vm.startPrank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        console2.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(USER);
        assertEq(startBalance, SEND_VALUE);

        vm.stopPrank();

        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        vm.selectFork(arbSepoliaFork);

        console2.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(USER));
        vm.warp(block.timestamp + 3600);
        console2.log("User Balance After Warp: %d", destRebaseToken.balanceOf(USER));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(USER);
        console2.log("Amount bridging back %d tokens ", destBalance);

        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }

    function testBridgeTwice() public {
        configureTokenPool(sepoliaFork, sourcePool, destPool, destRebaseToken, arbSepoliaNetworkDetails);

        configureTokenPool(arbSepoliaFork, destPool, sourcePool, sourceRebaseToken, sepoliaNetworkDetails);

        vm.selectFork(sepoliaFork);
        vm.startPrank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(USER);
        assertEq(startBalance, SEND_VALUE);

        vm.stopPrank();

        bridgeTokens(
            SEND_VALUE / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);

        uint256 newBalance = IERC20(address(sourceRebaseToken)).balanceOf(USER);

        bridgeTokens(
            newBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 3600);

        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(USER);

        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }
}
