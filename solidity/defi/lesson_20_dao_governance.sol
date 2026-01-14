// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Lesson 20: DAO 治理系统 (Governance System)
 * @notice 本合约实现一个完整的 DAO 治理系统，包括提案、投票、执行、时间锁
 * @dev 核心功能：代币治理、提案管理、投票机制、时间锁执行
 *
 * 学习目标：
 * 1. 理解 DAO 治理的核心原理
 * 2. 掌握提案生命周期的各个阶段
 * 3. 学习不同的投票机制（权重、委托）
 * 4. 实现时间锁保护机制
 * 5. 理解治理代币的经济模型
 *
 * 模块化设计：
 * - GovernanceToken: 治理代币（带投票权重和委托）
 * - DAOGovernor: 治理合约（提案、投票、执行）
 * - DAOTimeLock: 时间锁控制器（延迟执行）
 * - DAOFactory: 工厂合约（一键部署完整 DAO）
 */

// ========== 导入治理模块 ==========

import "./governance/GovernanceToken.sol";
import "./governance/DAOGovernor.sol";
import "./governance/DAOTimeLock.sol";
import "./governance/DAOFactory.sol";

/**
 * @notice 本文件仅作为模块导入的入口
 * @dev 实际合约实现在 governance/ 目录中：
 *
 * ├── governance/
 * │   ├── GovernanceToken.sol  (治理代币 - ~250 行)
 * │   ├── DAOTimeLock.sol       (时间锁 - ~30 行)
 * │   ├── DAOGovernor.sol       (治理合约 - ~180 行)
 * │   └── DAOFactory.sol        (工厂合约 - ~150 行)
 *
 * 模块化优势：
 * 1. 每个合约独立部署，大小 < 24KB
 * 2. 代码复用性高
 * 3. 易于维护和测试
 * 4. 符合最小合约大小原则
 */

// ========== 导出的合约类型 ==========

// 使用示例：
// import "./governance/GovernanceToken.sol";
// import "./governance/DAOGovernor.sol";
// import "./governance/DAOTimeLock.sol";
// import "./governance/DAOFactory.sol";
