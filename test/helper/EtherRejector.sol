// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract EtherRejector {
    error Transfer_Failed();

    receive() external payable {
        revert Transfer_Failed();
    }

    fallback() external payable {
        revert Transfer_Failed();
    }
}
