// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GovernanceToken.sol";
import "./DAOGovernor.sol";
import "./DAOTimeLock.sol";

/**
 * @title DAOFactory
 * @notice DAO 工厂合约 - 教学示范
 * @dev
 * ⚠️ 重要说明：此合约仅用于教学目的
 *
 * 合约大小限制说明：
 * - 以太坊主网合约大小限制：24KB
 * - 本工厂合约包含子合约字节码，约 38KB
 * - 在 Hardhat/测试网环境中可以正常工作
 *
 * 生产环境部署建议：
 * 1. 使用部署脚本（scripts/deploy-dao.js）直接部署各组件
 * 2. 或使用 CREATE2 工厂模式将字节码存储在外部
 * 3. 或使用 EIP-1167 最小代理模式
 *
 * 示例部署命令：
 * ```bash
 * # 部署治理代币
 * npx hardhat run scripts/deploy-token.js --network <network>
 *
 * # 部署时间锁
 * npx hardhat run scripts/deploy-timelock.js --network <network>
 *
 * # 部署治理合约
 * npx hardhat run scripts/deploy-governor.js --network <network>
 * ```
 */
contract DAOFactory {
    struct DAOConfig {
        string tokenName;
        string tokenSymbol;
        uint256 initialSupply;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 quorumFraction;
        uint256 timelockDelay;
    }

    struct DAOInstance {
        address token;
        address governor;
        address timelock;
    }

    DAOInstance[] public daos;
    mapping(address => address[]) public userDAOs;

    event DAOCreated(address indexed creator, address token, address governor, address timelock, uint256 timestamp);

    function createDAO(DAOConfig calldata config) external returns (DAOInstance memory dao) {
        GovernanceToken token = new GovernanceToken(config.tokenName, config.tokenSymbol, config.initialSupply);

        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        DAOTimeLock timelock = new DAOTimeLock(config.timelockDelay, proposers, executors);

        DAOGovernor governor = new DAOGovernor(
            IVotes(address(token)),
            timelock,
            config.votingDelay,
            config.votingPeriod,
            config.quorumFraction
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), address(this));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);

        token.transfer(msg.sender, config.initialSupply);

        dao = DAOInstance(address(token), address(governor), address(timelock));
        daos.push(dao);
        userDAOs[msg.sender].push(address(governor));

        emit DAOCreated(msg.sender, address(token), address(governor), address(timelock), block.timestamp);
        return dao;
    }

    function getUserDAOs(address user) external view returns (address[] memory) {
        return userDAOs[user];
    }

    function getAllDAOs() external view returns (DAOInstance[] memory) {
        return daos;
    }

    function getDAOCount() external view returns (uint256) {
        return daos.length;
    }
}
