// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RejectReceiver
 * @notice 一个拒绝接收所有 Ether 的辅助合约，用于测试回滚场景
 */
contract RejectReceiver {
    fallback() external {
        revert("Rejects all transfers");
    }

    receive() external payable {
        revert("Rejects all transfers");
    }
}
