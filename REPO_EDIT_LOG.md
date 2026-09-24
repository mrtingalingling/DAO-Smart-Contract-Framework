# Repository Edit Log

Each future functional change appends an entry here to maintain an auditable, minimal-diff record of modifications.

## 2026-09-23T22:50:00Z — feat/refactor-multistage-governance-erc1155
**What changed:** 
- Converted MemberToken to ERC-1155 Soulbound Token standard (`ERC1155Upgradeable`, `AccessControlUpgradeable`, `UUPSUpgradeable`) with block-checkpointed balance tracking (`Checkpoints.Trace208`) and transfer restrictions (`SoulboundTokenTransferDisabled`).
- Standardized `ICrsManager` interface to accept `(address account, uint256 tokenId)` and added `getPastCrs`.
- Concretized `ApprovalGovernor` for Stage 1 Value Ranking: CRS-weighted approval voting, membership snapshot verification via `getPastBalanceOf`, quorum checks, and `storage` gap.
- Concretized `QuadraticGovernor` for Stage 2 Resource Allocation: native in-contract credit allocation derived from CRS ($V = \lfloor\sqrt{C}\rfloor$), eliminating the double-root bug and volatile transient ERC20 token.
- Refactored `GovernorGeneral` state machine: coordinates stages (`Pending` -> `Approval` -> `Quadratic` -> `Succeeded` -> `Queued` -> `Executed`), handles permissionless stage advancement, batch queueing, and execution into `TimelockControllerUpgradeable`.
- Deleted obsolete `QuadraticToken.sol`.
- Refactored `ContractsFactory` for dual-mode deployment: self-governed standalone protocol deployment or federated independent agency DAO deployment with automated role assignment and ERC1967 proxy clones.
- Added comprehensive Foundry test suite (20 tests covering unit tests, end-to-end lifecycle, fuzz testing, and factory deployment).

**Why:** Addresses audited vulnerabilities and fulfills specifications:
1. Token standard migration from non-standard ERC20 to ERC-1155 Soulbound badges.
2. Fixes critical stage coordination and timelock batch execution in `GovernorGeneral`.
3. Fixes duplicate square root calculation and transient token supply inflation in `QuadraticGovernor`.
4. Fixes undeclared `Tokenizer` variable and broken proxy initialization in `ContractsFactory`.
5. Fixes non-standard `ICrsManager` signature mismatches.
6. Fulfills the federated DAO architecture where independent agencies deploy and customize their own multi-stage governance ecosystem.

**Files touched:**
- `contracts/MemberToken.sol`
- `contracts/ICrsManager.sol`
- `contracts/ApprovalGovernor.sol`
- `contracts/QuadraticGovernor.sol`
- `contracts/GovernorGeneral.sol`
- `contracts/ContractsFactory.sol`
- `contracts/QuadraticToken.sol` (deleted)
- `foundry.toml`
- `.gitignore`
- `script/DeployDirectDAO.s.sol`
- `script/DeployFactory.s.sol`
- `test/MemberToken.t.sol`
- `test/GovernorPipeline.t.sol`
- `test/ContractsFactory.t.sol`
- `test/QuadraticMath.t.sol`
- `test/mocks/MockCrsManager.sol`

**Tests added:** 20 tests total:
- 5 tests in `test/MemberToken.t.sol` (soulbound restrictions, mint, burn, checkpoint historical balances)
- 9 tests in `test/GovernorPipeline.t.sol` (Stage 1 Approval, Stage 2 Quadratic, duplicate vote guards, budget limits, full lifecycle to Timelock execution)
- 3 tests in `test/ContractsFactory.t.sol` (agency DAO deployment, role configuration, multiple isolated agency deployments)
- 3 tests in `test/QuadraticMath.t.sol` (fuzzing square root property, credit budget scaling, monotonicity)

**Deliberately not changed:**
- `contracts/IGovernor.sol` was left unchanged as its interface declarations remain compatible.
- The external Contribution Reputation Score calculation algorithm itself (mocked in tests via `ICrsManager`).

**Uncertainties:** none.

## 2026-09-23T23:01:00Z — feat/refactor-multistage-governance-erc1155
**What changed:**
- Refactored `ContractsFactory` to accept implementation contract addresses in `initialize(...)` and added `setImplementations(...)`, reducing contract size from 44.3KB to 8.6KB (well under the 24.576KB EIP-170 limit).
- Standardized `ApprovalGovernor` and `QuadraticGovernor` initializers to explicitly take `address _owner` and initialize `__Ownable_init(_owner)`.
- Restored original `README.md` documentation and added extensive sections covering architecture, UUPS upgradeability, agency customization guide, and Foundry testing. Restored `EnDAOsmentProcessFlow.svg` and `LICENSE`.
- Added `test/Upgradeability.t.sol` testing UUPS upgradeability and state preservation across all 5 upgradeable contracts.
- Verified on-chain deployments and agency DAO proxy instantiation against a local Anvil node.

**Why:** Satisfies user requirement to verify contract upgradeability, ensures EIP-170 EVM compliance for factory deployments, verifies deployment on Anvil, and preserves documentation for community developers building on the framework.

**Files touched:**
- `contracts/ContractsFactory.sol`
- `contracts/ApprovalGovernor.sol`
- `contracts/QuadraticGovernor.sol`
- `script/DeployFactory.s.sol`
- `test/ContractsFactory.t.sol`
- `test/Upgradeability.t.sol`
- `README.md`
- `.gitignore`
- `REPO_EDIT_LOG.md`

**Tests added:** 5 new tests in `test/Upgradeability.t.sol` (25 passing tests in total).

**Deliberately not changed:** none.

**Uncertainties:** none.

## 2026-09-23T23:13:00Z — docs: comprehensive documentation suite and dao explanation
**What changed:**
- Created dedicated `docs/` suite:
  - `docs/ARCHITECTURE.md`: In-depth breakdown of multi-stage governance, bounded rationality, state machine transitions, quadratic math formulations ($V = \lfloor\sqrt{C}\rfloor$), dynamic credit budgeting, and UUPS storage gap protection.
  - `docs/FEDERATED_AGENCY_GUIDE.md`: Developer guide explaining how independent agencies and organizations deploy customized DAOs via `ContractsFactory`, issue multi-tier ERC-1155 badges, and integrate custom reputation systems via `ICrsManager`.
  - `docs/DEPLOYMENT_AND_OPERATIONS.md`: Operations and deployment manual covering Anvil local simulation, testnet deployment, and end-to-end `cast` CLI command workflows for all proposal lifecycle stages.
- Enhanced `README.md` with deep links to `docs/`, clear lifecycle ASCII diagrams, and technical summaries while preserving all original text and diagrams.

**Why:** Addresses user request to ensure all documentation is clean, detailed, and thoroughly explains how the multi-stage DAO framework works.

**Files touched:**
- `docs/ARCHITECTURE.md`
- `docs/FEDERATED_AGENCY_GUIDE.md`
- `docs/DEPLOYMENT_AND_OPERATIONS.md`
- `README.md`
- `REPO_EDIT_LOG.md`

**Tests added:** none (documentation update only; all 25 existing tests pass).

**Deliberately not changed:** Smart contract bytecodes and logic were unchanged.

**Uncertainties:** none.

## 2026-09-24T00:59:00Z — chore: reconcile and merge origin/main into feature branch
**What changed:**
- Reconciled branch differences between `origin/main`, `origin/contractsInit`, and `feat/refactor-multistage-governance-erc1155`:
  - Removed 10,707 lines of redundant `.deps/npm/@openzeppelin/...` artifacts checked in from Remix on `contractsInit`.
  - Added `.deps/` to `.gitignore`.
  - Synchronized `EnDAOsmentProcessFlow.svg` with latest version on `origin/main`.
  - Merged `origin/main` cleanly into `feat/refactor-multistage-governance-erc1155`.
- Verified that merging into `origin/main` has zero conflicts (`git merge-tree` verified).
- Verified that all 25 tests pass cleanly.

**Why:** Addresses user request to compare and reconcile `main` and `contractsInit` so changes can be merged into `main`.

**Files touched:**
- `.deps/` (removed)
- `.gitignore`
- `EnDAOsmentProcessFlow.svg`
- `README.md`
- `REPO_EDIT_LOG.md`

**Tests added:** none (reconciliation and merge only; 25 tests passing).

**Deliberately not changed:** Smart contract implementations remain unchanged.

**Uncertainties:** none.
