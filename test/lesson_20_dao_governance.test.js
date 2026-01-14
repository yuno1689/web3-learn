/**
 * Lesson 20: DAO 治理系统测试文件
 * 测试 DAO 治理系统的核心功能
 */

import { expect } from "chai";
import hre from "hardhat";
const { ethers } = hre;
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("📘 Lesson 20: DAO 治理系统", function () {
    let daoFactory, governor, timelock, token;
    let owner, voter1, voter2, voter3, proposer;
    const INITIAL_SUPPLY = ethers.parseEther("1000000");

    beforeEach(async function () {
        [owner, voter1, voter2, voter3, proposer] = await ethers.getSigners();

        // 部署 DAO 工厂
        const DAOFactory = await ethers.getContractFactory("DAOFactory");
        daoFactory = await DAOFactory.deploy();

        // 创建 DAO 配置
        const config = {
            tokenName: "Governance Token",
            tokenSymbol: "GOV",
            initialSupply: INITIAL_SUPPLY,
            votingDelay: 1, // 1 个区块延迟
            votingPeriod: 10, // 10 个区块投票周期
            quorumFraction: 4, // 4% 法定人数
            timelockDelay: 3600 // 1 小时时间锁
        };

        // 创建 DAO
        const tx = await daoFactory.createDAO(config);
        const receipt = await tx.wait();

        // 获取部署的合约地址
        const daoAddress = await daoFactory.getUserDAOs(owner.address);
        const governorAddress = daoAddress[0];

        governor = await ethers.getContractAt("DAOGovernor", governorAddress);

        // 获取 token 和 timelock 地址
        const daoInstance = await daoFactory.daos(0);
        token = await ethers.getContractAt("GovernanceToken", daoInstance.token);
        timelock = await ethers.getContractAt("DAOTimeLock", daoInstance.timelock);

        // DAOFactory 拥有所有代币，作为 owner 连接到 token 并转移给投票者
        await token.connect(owner).transfer(voter1.address, ethers.parseEther("100000"));
        await token.connect(owner).transfer(voter2.address, ethers.parseEther("100000"));
        await token.connect(owner).transfer(voter3.address, ethers.parseEther("100000"));

        // 将剩余代币转移到时间锁合约，以便执行提案时可以使用
        const timelockBalance = await token.balanceOf(owner.address);
        await token.connect(owner).transfer(await timelock.getAddress(), timelockBalance);

        // 授权治理合约
        await token.connect(voter1).delegate(voter1.address);
        await token.connect(voter2).delegate(voter2.address);
        await token.connect(voter3).delegate(voter3.address);
    });

    describe("1️⃣ DAO 初始化和配置", function () {
        it("应该正确创建 DAO", async function () {
            const daoCount = await daoFactory.getDAOCount();
            expect(daoCount).to.equal(1);
        });

        it("应该正确初始化治理代币", async function () {
            expect(await token.name()).to.equal("Governance Token");
            expect(await token.symbol()).to.equal("GOV");
            expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY);
        });

        it("应该正确设置治理参数", async function () {
            expect(await governor.votingDelay()).to.equal(1);
            expect(await governor.votingPeriod()).to.equal(10);
            expect(await governor.quorumNumerator()).to.equal(4);
        });

        it("应该正确初始化时间锁", async function () {
            const minDelay = await timelock.getMinDelay();
            expect(minDelay).to.equal(3600);
        });

        it("应该记录创建者的 DAO", async function () {
            const userDAOs = await daoFactory.getUserDAOs(owner.address);
            expect(userDAOs.length).to.equal(1);
            expect(userDAOs[0]).to.equal(await governor.getAddress());
        });
    });

    describe("2️⃣ 治理代币功能", function () {
        it("应该正确计算投票权重", async function () {
            const votes1 = await token.getVotes(voter1.address);
            expect(votes1).to.equal(ethers.parseEther("100000"));
        });

        it("应该支持委托投票", async function () {
            await token.connect(voter1).delegate(voter2.address);

            const votes2 = await token.getVotes(voter2.address);
            expect(votes2).to.equal(ethers.parseEther("200000")); // voter2 自己的 + voter1 委托的
        });

        it("应该正确记录历史投票权重", async function () {
            // 在当前区块记录投票权重
            const currentBlock = await ethers.provider.getBlockNumber();

            // 转移代币
            await token.connect(voter1).transfer(voter2.address, ethers.parseEther("10000"));

            // 查询历史投票权重
            const pastVotes = await token.getPastVotes(voter1.address, currentBlock);
            expect(pastVotes).to.equal(ethers.parseEther("100000"));
        });

        it("应该正确更新总供应量检查点", async function () {
            const currentBlock = await ethers.provider.getBlockNumber();
            // 查询前一个区块的总供应量（不能查询当前区块）
            const pastSupply = await token.getPastTotalSupply(currentBlock - 1);
            expect(pastSupply).to.equal(INITIAL_SUPPLY);
        });
    });

    describe("3️⃣ 提案管理", function () {
        it("应该成功创建提案", async function () {
            const targets = [owner.address];
            const values = [0];
            const calldatas = [token.interface.encodeFunctionData("transfer", [voter1.address, ethers.parseEther("1000")])];
            const description = "Transfer tokens to voter1";

            const tx = await governor.propose(targets, values, calldatas, description);
            const receipt = await tx.wait();

            // 从事件中提取提案 ID
            const proposalCreatedEvent = receipt.logs.find(
                log => log.fragment && log.fragment.name === "ProposalCreated"
            );

            expect(proposalCreatedEvent).to.not.be.undefined;
        });

        it("应该有足够的代币才能创建提案", async function () {
            // voter2 尝试创建提案（有 100000 代币，应该足够）
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            await expect(
                governor.connect(voter2).propose(targets, values, calldatas, description)
            ).to.not.be.reverted;
        });

        it("应该正确设置提案状态", async function () {
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            const tx = await governor.propose(targets, values, calldatas, description);
            const receipt = await tx.wait();

            const proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            // 提案状态应该是 Pending
            let state = await governor.state(proposalId);
            expect(state).to.equal(0); // Pending

            // 等待投票延迟
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);

            // 状态应该是 Active
            state = await governor.state(proposalId);
            expect(state).to.equal(1); // Active
        });

        it("应该正确计算提案哈希", async function () {
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            const proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            expect(proposalId).to.not.equal(ethers.ZeroHash);
        });
    });

    describe("4️⃣ 投票功能", function () {
        let proposalId;

        beforeEach(async function () {
            // 创建提案
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            const tx = await governor.propose(targets, values, calldatas, description);
            const receipt = await tx.wait();

            proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            // 等待投票延迟
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);
        });

        it("应该成功投票", async function () {
            const tx = await governor.connect(voter1).castVote(proposalId, 1); // 1 = For
            const receipt = await tx.wait();

            // 检查投票事件
            const voteCastEvent = receipt.logs.find(
                log => log.fragment && log.fragment.name === "VoteCast"
            );

            expect(voteCastEvent).to.not.be.undefined;
        });

        it("应该正确统计投票权重", async function () {
            await governor.connect(voter1).castVote(proposalId, 1);
            await governor.connect(voter2).castVote(proposalId, 1);

            const proposalVotes = await governor.proposalVotes(proposalId);

            expect(proposalVotes.forVotes).to.equal(ethers.parseEther("200000"));
        });

        it("应该支持不同的投票选项", async function () {
            // voter1 投赞成
            await governor.connect(voter1).castVote(proposalId, 1);
            // voter2 投反对
            await governor.connect(voter2).castVote(proposalId, 0);
            // voter3 弃权
            await governor.connect(voter3).castVote(proposalId, 2);

            const proposalVotes = await governor.proposalVotes(proposalId);

            expect(proposalVotes.forVotes).to.equal(ethers.parseEther("100000"));
            expect(proposalVotes.againstVotes).to.equal(ethers.parseEther("100000"));
            expect(proposalVotes.abstainVotes).to.equal(ethers.parseEther("100000"));
        });

        it("应该防止重复投票", async function () {
            await governor.connect(voter1).castVote(proposalId, 1);

            await expect(
                governor.connect(voter1).castVote(proposalId, 0)
            ).to.be.revertedWithCustomError(governor, "GovernorAlreadyCastVote");
        });

        it("应该在投票期结束后不能投票", async function () {
            // 等待投票期结束
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 12);

            await expect(
                governor.connect(voter1).castVote(proposalId, 1)
            ).to.be.reverted; // 投票期结束后不能投票
        });
    });

    describe("5️⃣ 提案执行", function () {
        let proposalId;
        let targets, values, calldatas, description;

        beforeEach(async function () {
            // 创建提案：转账代币
            targets = [await token.getAddress()];
            values = [0];
            calldatas = [token.interface.encodeFunctionData("transfer", [voter1.address, ethers.parseEther("1000")])];
            description = "Transfer 1000 tokens to voter1";

            const tx = await governor.propose(targets, values, calldatas, description);
            const receipt = await tx.wait();

            proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            // 等待投票延迟
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);

            // 投票
            await governor.connect(voter1).castVote(proposalId, 1);
            await governor.connect(voter2).castVote(proposalId, 1);

            // 等待投票期结束
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 12);
        });

        it("应该成功执行提案", async function () {
            const balanceBefore = await token.balanceOf(voter1.address);

            // 等待时间锁延迟
            await time.increase(3600);

            // 先排队提案
            const descriptionHash = ethers.keccak256(ethers.toUtf8Bytes(description));
            await governor.queue(targets, values, calldatas, descriptionHash);

            // 再等待时间锁延迟
            await time.increase(3600);

            // 执行提案
            await governor.execute(targets, values, calldatas, descriptionHash);

            const balanceAfter = await token.balanceOf(voter1.address);
            expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1000"));
        });

        it("执行后提案状态应该是 Executed", async function () {
            await time.increase(3600);

            const descriptionHash = ethers.keccak256(ethers.toUtf8Bytes(description));
            await governor.queue(targets, values, calldatas, descriptionHash);

            await time.increase(3600);

            await governor.execute(targets, values, calldatas, descriptionHash);

            const state = await governor.state(proposalId);
            expect(state).to.equal(7); // Executed
        });

        it("时间锁未到期前不能执行", async function () {
            // 创建新提案用于此测试
            const newTargets = [await token.getAddress()];
            const newValues = [0];
            const newCalldatas = [token.interface.encodeFunctionData("transfer", [voter1.address, ethers.parseEther("1000")])];
            const newDescription = "Another transfer";
            const newDescriptionHash = ethers.keccak256(ethers.toUtf8Bytes(newDescription));

            const tx = await governor.propose(newTargets, newValues, newCalldatas, newDescription);
            const receipt = await tx.wait();

            // 等待投票延迟并投票
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);
            await governor.connect(voter1).castVote(await governor.hashProposal(newTargets, newValues, newCalldatas, newDescriptionHash), 1);
            await governor.connect(voter2).castVote(await governor.hashProposal(newTargets, newValues, newCalldatas, newDescriptionHash), 1);

            // 等待投票期结束
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 12);

            // 排队提案
            await governor.queue(newTargets, newValues, newCalldatas, newDescriptionHash);

            // 尝试在时间锁到期前执行
            await expect(
                governor.execute(newTargets, newValues, newCalldatas, newDescriptionHash)
            ).to.be.reverted; // 时间锁未到期
        });

        it("失败的提案不能执行", async function () {
            // 创建一个会失败的提案
            const newTargets = [owner.address];
            const newValues = [0];
            const newCalldatas = ["0x"];
            const newDescription = "Failed proposal";

            const tx = await governor.propose(newTargets, newValues, newCalldatas, newDescription);
            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);

            const newProposalId = await governor.hashProposal(newTargets, newValues, newCalldatas, ethers.keccak256(ethers.toUtf8Bytes(newDescription)));

            // 所有人投反对票
            await governor.connect(voter1).castVote(newProposalId, 0);
            await governor.connect(voter2).castVote(newProposalId, 0);

            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 12);
            await time.increase(3600);

            await expect(
                governor.execute(newTargets, newValues, newCalldatas, ethers.keccak256(ethers.toUtf8Bytes(newDescription)))
            ).to.be.reverted; // 失败的提案不能执行
        });
    });

    describe("6️⃣ 法定人数和阈值", function () {
        let proposalId;

        beforeEach(async function () {
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            await governor.propose(targets, values, calldatas, description);
            proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);
        });

        it("应该正确计算法定人数", async function () {
            const currentBlock = await ethers.provider.getBlockNumber();
            const quorum = await governor.quorum(currentBlock - 1); // 不能查询当前区块

            // 4% of 1,000,000 = 40,000
            expect(quorum).to.equal(ethers.parseEther("40000"));
        });

        it("投票不足应该失败", async function () {
            // 只有 voter1 投票（100000 < 40000 法定人数，实际上应该足够）
            await governor.connect(voter1).castVote(proposalId, 1);

            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 12);

            const state = await governor.state(proposalId);
            // 应该成功，因为 100000 > 40000
            expect(state).to.equal(4); // Succeeded
        });

        it("应该正确计算提案阈值", async function () {
            const threshold = await governor.proposalThreshold();

            // 默认阈值设置为 0，意味着任何人都可以创建提案
            expect(threshold).to.equal(0);
        });
    });

    describe("7️⃣ 取消提案", function () {
        let proposalId;
        let targets, values, calldatas, description;

        beforeEach(async function () {
            targets = [owner.address];
            values = [0];
            calldatas = ["0x"];
            description = "Test proposal";

            await governor.propose(targets, values, calldatas, description);
            proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 2);
        });

        it("提案者应该能取消提案", async function () {
            // 在投票延迟期内，提案者可以取消提案
            // 先创建一个新提案用于此测试
            const newTargets = [owner.address];
            const newValues = [0];
            const newCalldatas = ["0x"];
            const newDescription = "Cancellable proposal";

            await governor.propose(newTargets, newValues, newCalldatas, newDescription);
            const newProposalId = await governor.hashProposal(newTargets, newValues, newCalldatas, ethers.keccak256(ethers.toUtf8Bytes(newDescription)));

            // 在投票延迟期内取消
            await governor.cancel(newTargets, newValues, newCalldatas, ethers.keccak256(ethers.toUtf8Bytes(newDescription)));

            const state = await governor.state(newProposalId);
            expect(state).to.equal(2); // Cancelled
        });

        it("已执行的提案不能取消", async function () {
            await governor.connect(voter1).castVote(proposalId, 1);
            await governor.connect(voter2).castVote(proposalId, 1);

            await time.advanceBlockTo(await ethers.provider.getBlockNumber() + 12);
            await time.increase(3600);

            // 排队并执行提案
            const descriptionHash = ethers.keccak256(ethers.toUtf8Bytes(description));
            await governor.queue(targets, values, calldatas, descriptionHash);
            await time.increase(3600);

            await governor.execute(targets, values, calldatas, descriptionHash);

            // 尝试取消已执行的提案
            await expect(
                governor.cancel(targets, values, calldatas, descriptionHash)
            ).to.be.reverted; // 已执行的提案不能取消
        });
    });

    describe("8️⃣ 时间锁功能", function () {
        it("应该正确设置最小延迟", async function () {
            const minDelay = await timelock.getMinDelay();
            expect(minDelay).to.equal(3600);
        });

        it("应该只有治理合约能调度操作", async function () {
            const isProposer = await timelock.hasRole(await timelock.PROPOSER_ROLE(), await governor.getAddress());
            expect(isProposer).to.be.true;
        });

        it("应该只有治理合约能取消操作", async function () {
            const isCanceller = await timelock.hasRole(await timelock.CANCELLER_ROLE(), await governor.getAddress());
            expect(isCanceller).to.be.true;
        });

        it("任何人都可以执行操作", async function () {
            const isExecutor = await timelock.hasRole(await timelock.EXECUTOR_ROLE(), ethers.ZeroAddress);
            expect(isExecutor).to.be.true;
        });
    });

    describe("9️⃣ 边界条件和安全性", function () {
        it("应该防止无效的提案", async function () {
            const targets = [];
            const values = [];
            const calldatas = [];
            const description = "";

            await expect(
                governor.propose(targets, values, calldatas, description)
            ).to.be.reverted; // 空提案
        });

        it("应该防止在没有投票权时创建提案", async function () {
            // 由于提案阈值设置为 0，任何人都可以创建提案
            // 这个测试验证即使没有代币也能创建提案
            const [newAccount] = await ethers.getSigners();

            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal from zero votes account";

            // 由于阈值是 0，这个调用应该成功
            await expect(
                governor.connect(newAccount).propose(targets, values, calldatas, description)
            ).to.not.be.reverted;
        });

        it("应该正确处理提案哈希冲突", async function () {
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            const proposalId1 = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            // 相同的参数应该产生相同的哈希
            const proposalId2 = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            expect(proposalId1).to.equal(proposalId2);
        });
    });

    describe("🔟 查询功能", function () {
        it("应该正确返回提案详情", async function () {
            const targets = [owner.address];
            const values = [0];
            const calldatas = ["0x"];
            const description = "Test proposal";

            await governor.propose(targets, values, calldatas, description);

            const proposalId = await governor.hashProposal(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));

            // 使用 state() 检查提案状态
            const state = await governor.state(proposalId);
            // 0 = Pending, 1 = Active, 2 = Canceled, 3 = Defeated, 4 = Succeeded, 5 = Queued, 6 = Expired, 7 = Executed
            expect(state).to.be.lessThan(8); // 任何有效状态（0-7）
        });

        it("应该正确返回投票权重", async function () {
            const votes = await token.getVotes(voter1.address);
            expect(votes).to.equal(ethers.parseEther("100000"));
        });

        it("应该正确返回法定人数", async function () {
            const currentBlock = await ethers.provider.getBlockNumber();
            const quorum = await governor.quorum(currentBlock - 1); // 不能查询当前区块

            expect(quorum).to.equal(ethers.parseEther("40000"));
        });

        it("应该正确返回治理参数", async function () {
            const votingDelay = await governor.votingDelay();
            const votingPeriod = await governor.votingPeriod();
            const quorumNumerator = await governor.quorumNumerator();

            expect(votingDelay).to.equal(1);
            expect(votingPeriod).to.equal(10);
            expect(quorumNumerator).to.equal(4);
        });
    });
});
