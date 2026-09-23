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
