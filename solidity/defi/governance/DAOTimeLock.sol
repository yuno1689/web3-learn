// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DAOTimeLock
 * @notice 时间锁控制器 - 为治理操作添加时间延迟
 * @dev 继承 OpenZeppelin 的 TimelockController
 */
contract DAOTimeLock is TimelockController {
    /**
     * @notice 构造函数
     * @param minDelay 最小延迟时间（秒）
     * @param proposers 可以提案的地址列表
     * @param executors 可以执行的地址列表
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors, msg.sender) {}
}
