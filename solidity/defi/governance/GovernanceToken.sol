// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernanceToken
 * @notice 治理代币合约 - 带有投票权委托功能
 * @dev 实现 ERC20 标准 + 投票权重管理 + 委托机制
 */
contract GovernanceToken is ERC20, Ownable {
    /// @notice 总供应量上限
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice 委托记录
    mapping(address => address) public delegates;

    /// @notice 检查点（用于历史投票权查询）
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    /// @notice 用户检查点
    mapping(address => Checkpoint[]) public checkpoints;

    /// @notice 总供应量检查点
    Checkpoint[] public totalSupplyCheckpoints;

    // ========== 事件 ==========

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    // ========== 构造函数 ==========

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_initialSupply <= MAX_SUPPLY, unicode"Exceeds max supply");
        _mint(msg.sender, _initialSupply);
        _mintCheckpoint(msg.sender, _initialSupply);
    }

    // ========== 核心功能：投票权重 ==========

    /**
     * @notice 获取当前投票权重
     * @param account 账户地址
     * @return 投票权重
     */
    function getVotes(address account) public view returns (uint256) {
        uint256 checkpointsNum = checkpoints[account].length;
        return checkpointsNum == 0 ? 0 : checkpoints[account][checkpointsNum - 1].votes;
    }

    /**
     * @notice 获取历史投票权重
     * @param account 账户地址
     * @param blockNumber 区块号
     * @return 该区块的投票权重
     */
    function getPastVotes(address account, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, unicode"Cannot query future blocks");

        uint256 checkpointsNum = checkpoints[account].length;
        if (checkpointsNum == 0) return 0;

        // 二分查找
        uint256 lower = 0;
        uint256 upper = checkpointsNum - 1;

        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock > blockNumber) {
                upper = center - 1;
            } else {
                lower = center;
            }
        }

        return checkpoints[account][lower].votes;
    }

    /**
     * @notice 委托投票权
     * @param delegatee 被委托人地址
     */
    function delegate(address delegatee) external {
        address currentDelegate = delegates[msg.sender];
        delegates[msg.sender] = delegatee;

        emit DelegateChanged(msg.sender, currentDelegate, delegatee);
        _moveDelegateVotes(currentDelegate, delegatee, balanceOf(msg.sender));
    }

    /**
     * @notice 转移投票权重
     */
    function _moveDelegateVotes(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint256 srcRepOld = getVotes(srcRep);
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint256 dstRepOld = getVotes(dstRep);
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepOld, dstRepNew);
            }
        }
    }

    /**
     * @notice 写入检查点
     */
    function _writeCheckpoint(address delegatee, uint256 oldWeight, uint256 newWeight) internal {
        Checkpoint[] storage cp = checkpoints[delegatee];

        if (cp.length == 0 || cp[cp.length - 1].fromBlock < block.number) {
            cp.push(Checkpoint({
                fromBlock: uint32(block.number),
                votes: uint224(newWeight)
            }));
        } else {
            cp[cp.length - 1].votes = uint224(newWeight);
        }

        emit DelegateVotesChanged(delegatee, oldWeight, newWeight);
    }

    /**
     * @notice 铸造代币时更新检查点
     */
    function _mintCheckpoint(address account, uint256 amount) internal {
        uint256 oldWeight = getVotes(account);
        uint256 newWeight = oldWeight + amount;
        _writeCheckpoint(account, oldWeight, newWeight);
    }

    /**
     * @notice 转账时更新投票权重
     */
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);

        if (from == address(0)) {
            uint256 oldSupply = getPastTotalSupply(block.number - 1);
            uint256 newSupply = oldSupply + amount;
            _writeTotalSupplyCheckpoint(oldSupply, newSupply);
        }

        if (to == address(0)) {
            uint256 oldSupply = getPastTotalSupply(block.number - 1);
            uint256 newSupply = oldSupply - amount;
            _writeTotalSupplyCheckpoint(oldSupply, newSupply);
        }

        if (delegates[from] == delegates[to]) return;

        _moveDelegateVotes(delegates[from], delegates[to], amount);
    }

    /**
     * @notice 写入总供应量检查点
     */
    function _writeTotalSupplyCheckpoint(uint256 oldSupply, uint256 newSupply) internal {
        totalSupplyCheckpoints.push(Checkpoint({
            fromBlock: uint32(block.number),
            votes: uint224(newSupply)
        }));
    }

    /**
     * @notice 获取历史总供应量
     */
    function getPastTotalSupply(uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, unicode"Cannot query future blocks");

        uint256 checkpointsNum = totalSupplyCheckpoints.length;
        if (checkpointsNum == 0) return 0;

        // 二分查找
        uint256 lower = 0;
        uint256 upper = checkpointsNum - 1;

        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            Checkpoint memory cp = totalSupplyCheckpoints[center];
            if (cp.fromBlock > blockNumber) {
                upper = center - 1;
            } else {
                lower = center;
            }
        }

        return totalSupplyCheckpoints[lower].votes;
    }
}
